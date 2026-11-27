
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer REMOTE_SCHEDULE = 0,
    parameter integer RELIABLE_MEDIA = 0,
    // 100 MHz / ((2 + 2) * 2) = 12.5 MHz. Allow board/card input
    // settling margin; initialization still uses the controller's slow rate.
    parameter integer SPI_HIGH_SPEED_DIV = 2,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd5,
    // 载图看门狗：**失速**窗口（毫秒）。
    // ⚠️ 语义是「**多久没有新像素进来**就算卡住」，**不是**「整张图最多载多久」。
    //    早期版本是后者，在只收 640x480（约 0.4 s）时够用；C2-a 放开分辨率后
    //    1280x720 要 1.2 s，会被后者误判 -> 反复重发、永远出不了图。
    //    见下面 load_progress 那段注释里的实测换算。
    // 1 s 的余量：正常载图时像素是**连续**来的（一个源像素最多隔一个扇区读），
    // 所以"连续 1 s 一个像素都没有"确实只剩真卡住这一种解释。
    // LOAD_TIMEOUT_MS = 0 表示关掉看门狗（只为仿真做 A/B）。
    parameter integer LOAD_TIMEOUT_MS   = 1000,
    // bmp_read 内部的**载图停滞**超时（毫秒）。见 bmp_read.v 模块头的说明。
    // ⚠️ 它必须**比 LOAD_TIMEOUT_MS 短**：先由 bmp_read 自己松绑（回到 ST_IDLE、
    //    把 ready 放出来），外层这个 1000 ms 的看门狗才有机会记故障码并重发。
    //    顺序反了的话，外层超时时 bmp_ready 还是 0，重发那一支进不去 —— 死锁。
    // 0 = 关掉（只为仿真做 A/B）。
    parameter integer BMP_STALL_TIMEOUT_MS = 500,
    // ★ 载图越界守卫（见 bmp_read.v 的 LOAD_OVERRUN_GUARD）。
    //   它与上面那条停滞超时是**互补**的：停滞超时盖"东西不来了"，
    //   本条盖"read_end 照来、字节却不来了" —— 板上 state_code=4 恒久那一种。
    //   1 = 开（默认，正式 build 走这条）；0 = 关（只为仿真做 A/B）。
    parameter integer BMP_OVERRUN_GUARD = 1,
    // ★ 警报模式下每张紧急图的**停留**时间（毫秒）。
    //   2026-09-29：先缩到 1000 ms，上板反馈"两张报警图没看全就上疏散图了"，
    //   于是**恢复 2000 ms** —— 要求是：火灾报警图、静态疏散图**各自完整显示一遍**，
    //   然后才轮到动态疏散图。
    //   ⚠️ 要跟叠加层的 EVAC_PAGE1_HOLD_FRAMES 对齐（那边等页 1 播满同样长
    //      才让动态疏散图接管；现在两边都是 2 s）。
    //   ⚠️ 实现上是“数满若干个 1 s 的 tick 才算一次停留”（见下面 auto_tick
    //      的推导），所以这个值按 1 s 量化：2000 = 两个 tick，1000 = 一个 tick。
    parameter integer EMER_DWELL_MS    = 2000,
    // Ordinary commit-to-commit interval includes prefetch, not extra dwell.
    // Load the next inactive buffer immediately, then hold its complete frame
    // until the deadline. Emergency dwell and cache selection stay separate.
    parameter integer NORMAL_INTERVAL_MS = 3000,
    // Eight fade-out frames at ~60 Hz plus frame/synchronizer margin.
    parameter integer NORMAL_FADE_MS = 160,
    // Empty FAT scan retry interval.  A transient card/FAT failure at power-up
    // must not leave the terminal with no images until a manual power cycle.
    parameter integer SCAN_RETRY_MS    = 250,
    parameter integer SD_POWERUP_WAIT_MS = 100,
    parameter integer SD_INIT_TIMEOUT_MS = 2000
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    // 警报模式电平（S4 切换，在 video_clk 域产生）。慢变信号，
    // 这里做三级同步后使用，见下面的 emergency_on。
    input                       emergency,
    input [8:0]                 remote_phase,
    output [4:0]                carousel_feedback,
    output [1:0]                interval_selection,
    output reg                  brightness_step_toggle,
    output reg                  contrast_step_toggle,
    output [2:0]                page_index_out,
    output [3:0]                state_code,
    // 载图故障码（纯诊断，显示到数码管的某一位）。记录**最近一次**看门狗超时时
    // 故障落在哪一层：
    //   0 = 从未超时
    //   1 = 超时，bmp_read 还**没**空闲         -> SD 读 / 帧缓存握手
    //   2 = 超时，bmp_read 已空闲、一个像素没送 -> 头被拒 / 零长度
    //   3 = 超时，已空闲、像素送过但整帧写不完  -> 写通路
    //   4 = 写侧缩放器的行缓冲被追上（源图过小，正常不会出现）
    // 非 0 就说明"这次上电真的出过问题"，不是"重烧一次就好了"。
    output reg [3:0]            load_fault,
    // 1 = 故障**不止一次**（一次=偶发，多次=每次都犯）。占小数点位，省一个数码管。
    output wire                 load_fault_recurring,
    // Repeated-timeout recovery request. The top level uses this to
    // reset the SD controller and frame writer, then re-scan/reload.
    output reg                  hard_recover,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    // 当前**显示中**那张图的源分辨率（给 OSD 用）。
    // ⚠️ 必须在 load_commit 那一拍锁存，不能直接把 bmp_src_w/h 接出去：
    //    bmp_src_w/h 是 bmp_read 里**正在装载**那张图的宽高，而装载期间
    //    屏幕上显示的还是**上一张** —— 直接接出去会"图还没换、分辨率先变了"。
    // disp_src_toggle 每次锁存翻转一次，给 video_clk 域做数据+toggle 握手
    // （16 位总线不能靠逐位两级同步）。
    output reg [15:0]           disp_src_w,
    output reg [15:0]           disp_src_h,
    output reg                  disp_src_toggle,
    // ★ 透传 bmp_read 的"快读完了"（见 bmp_read.v 的 NEARLY_DONE_SECTORS）。
    //   叠加层用它决定**何时开始淡出** —— 替代原来"用上一张的载图时长预测
    //   这一张"的做法，后者在 C2-a 放开分辨率之后两个方向都会坏。
    //   在 sd_card_clk 域，消费方（video_clk）要自己打两拍同步。
    output                      load_nearly_done,
    // Registered video intent: background prefetch must not darken the screen.
    output reg                  load_visual_active,

    input                       write_finish_toggle,
    output                      auto_play_en_out,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO,
    // Audio metadata only; latched with complete display/cache selection.
    output reg                  disp_audio_emergency
);

wire key_next_press;
wire key_auto_press;
wire key_next_long_step;
wire key_auto_long_step;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire [15:0]      bmp_src_w;         // 已解析的源图宽高（来自 bmp_read）
wire [15:0]      bmp_src_h;
wire             bmp_data_start;    // 进入 ST_LOAD_DATA 的脉冲 -> 缩放器 src_sof
wire [23:0]      scaler_pixel;
wire scaler_valid;
wire             scaler_overflow;   // 缩放器被"生产者追上消费者"（正常应恒 0）
wire             sd_init_done;
wire             bmp_ready;
wire             bmp_load_complete;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg [4:0] img_slots;
wire [2:0] scan_found_slot;
wire [2:0] first_normal=RELIABLE_MEDIA?(img_slots[2]?3'd2:img_slots[3]?3'd3:3'd4):3'd2;
reg              auto_play_en;
localparam integer AUTO_WIDTH=REMOTE_SCHEDULE?12:32;
reg [AUTO_WIDTH-1:0] auto_cnt;
localparam integer MS_DIV=CLK_FREQ_HZ/1000;
localparam integer MS_WIDTH=$clog2(MS_DIV)>0?$clog2(MS_DIV):1;
reg [MS_WIDTH-1:0] ms_divider;
wire ms_enable=!REMOTE_SCHEDULE || ms_divider==MS_DIV-1;
always @(posedge clk or posedge rst)
 if(rst)ms_divider<=0;else if(ms_enable)ms_divider<=0;else ms_divider<=ms_divider+1'b1;
reg [2:0]        img_found_count;
reg [2:0]        img_idx;              // 当前真正显示中的图片编号（0..4，最多 5 张）
reg [2:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_sector4;          // 第 5 张（警报模式要用）
reg              next_req_pending;
reg [2:0]        next_req_idx;         // 手动切图请求锁存的目标页
reg              load_busy;
reg              normal_prefetch;
reg              static_prefetch;
reg              load_abort;           // one-shot abort for bmp_read

// ---- 载图看门狗：超时后重发同一张图，并把故障原因记下来 ----
//
// 为什么必须有（2026-09-19 板上实测 + 代码复核）：
//   load_busy 一旦置起，**只有收到 write_finish_pulse 才会清**，中间没有任何超时。
//   而那条脉冲要走完
//     frame_fifo_write(S_END) -> frame_write_toggle_mem   [ext_mem_clk]
//     -> wrfin_tgl_sync                                   [sd_card_clk]
//   整条链路 —— 其中 ext_mem_clk/SDRAM 那一段**静态时序根本不覆盖**
//   （SDRAM 到芯片的 I/O 时序、板级走线不在 STA 范围内）。任何一环丢了都让
//   load_busy 永久卡在 1，而**所有**发起载图的分支都带 !load_busy
//   ⇒ 自动轮播彻底停摆。板上现象就是"显示几张之后图片卡着不动"。
//
//   看门狗把"永久卡死"降级成"停 ~1 s 后重发同一张"，位移很小；同时把
//   **故障码**送出去 —— 它是**可观测数据**，不会把根因掩盖成"好像自己好了"。
reg [26:0]       load_wd_cnt;          // 1 s @100 MHz = 1e8 < 2^27
reg              load_retry_pending;   // 超时后待重发同一张
reg              load_data_seen;       // 本次载图真往帧缓存送过像素
reg              load_started_seen;    // bmp_read actually left IDLE for this load
reg [3:0]        load_timeout_count;   // 超时累计次数（饱和 F），只用来判"是否复发"
reg [3:0]        load_error_total;     // total saturating faults for the dot
reg [5:0]        hard_recover_cnt;
// load_fault 是 output reg，已在端口表里声明，这里不能再声明一次

assign load_fault_recurring = (load_error_total >= 4'd2);
// 计数上限（= TICKS - 1）。写足位宽，免得综合出 32 位的比较器。
localparam integer LOAD_TIMEOUT_TICKS = (CLK_FREQ_HZ / 1000) * LOAD_TIMEOUT_MS;
localparam [26:0]  LOAD_TIMEOUT_LAST  = LOAD_TIMEOUT_TICKS - 1;
wire load_wd_en = (LOAD_TIMEOUT_MS != 0);

// Empty-scan recovery (see the scan_done/img_found_count logic below).
localparam integer SCAN_RETRY_TICKS = (CLK_FREQ_HZ / 1000) * SCAN_RETRY_MS;
localparam [26:0]  SCAN_RETRY_LAST  = SCAN_RETRY_TICKS - 1;
reg        scan_retry_pending;
reg [26:0] scan_retry_cnt;
reg [2:0]  empty_scan_count;

// 警报模式（S4）跨时钟域同步：emergency 来自 video_clk 域。
reg [2:0]        emergency_sync;
reg              emergency_on_d;
wire             emergency_on   = emergency_sync[2];
// 进入警报模式的那一拍：立刻把画面切到前两张紧急图，不用等满一个轮播周期
wire             emergency_rise = emergency_on & ~emergency_on_d;
// 退出警报模式的那一拍：普通模式从此**不允许**再显示前两张紧急图
// （在飞的那张紧急图要压掉提交，并立刻回到普通组第一张，见下面的分支）
wire             emergency_fall = ~emergency_on & emergency_on_d;
// 警报模式下轮播强制开启，不受 S3 开关影响；退出警报后回到 S3 的开关状态
wire             auto_play_eff  = auto_play_en | emergency_on;
// ★ 普通模式**只在普通组内部轮播**（扫描顺序第 3 张起，索引 2/3/4），
//   S4 按下时才在索引 0/1（两张紧急图）之间轮播。
//   ⚠️ 2026-09-29 修正：这里不能按“普通组必须有两张”去卡 —— 卡上张数不由我们决定。
//      门槛恢复成 `img_found_count > 2`（与最初一致），"只有一张普通图"这种情况
//      改由下面两条“**下一张 == 当前页就不要重载**”来兜：既不黑屏，也不会原地
//      重载同一张（原地重载的表现就是"按了没反应 + 黑一下"，上板被当成链路坏了）。
wire             rotate_available = RELIABLE_MEDIA ? (emergency_on ? (img_slots[0] && img_slots[1]) : ((img_slots[2] && img_slots[3]) || (img_slots[2] && img_slots[4]) || (img_slots[3] && img_slots[4]))) : (emergency_on ? (img_found_count>1) : (img_found_count>2));
wire             normal_group_ready = RELIABLE_MEDIA ? |img_slots[4:2] : (img_found_count>2);

// 源完成用 bmp_load_complete 锁存；bmp_ready 只表示空闲，不能作为成功依据。
// 真正切显示还要等 write_finish_toggle 同步后。
reg              source_done_seen;
reg              write_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [2:0] next_from_current;

// ---------------------------------------------------------------------------
// C2-a：写通路上插一级「任意分辨率 -> 640x480」缩放器
//
// 原来这里是把 bmp_read 的像素流**原样**透传（只做 24->32 位补齐）。
// 现在源图可以是任意 W x H（1..4095），必须先缩放到帧缓存的固定 640x480 再写。
//
// ⚠️ 缩放器的输出速率与源像素速率**不同**（放大时快、缩小时慢），
//    但一帧的总字数**恰好** 307200 —— 这是 frame_fifo_write 那个零余量
//    完成判据（307200 <= 306944 + 256）成立的前提。tb 逐帧核过。
//
// ⚠️ src_sof 用 bmp_read 的 data_start（进入 ST_LOAD_DATA 那一拍），
//    不是 load_start_pulse —— 后者发出去时文件头还没解析，width/height 还是上一张的。
// ---------------------------------------------------------------------------
// ★ 2026-09-29：**换回最近邻写缩放器**（`bmp_write_scaler`），不再用双线性那份。
//   两份模块端口完全一样，就在同一个文件 rtl/bmp_write_scaler.v 里。
//   为什么换：2026-09-27 那版上板验证过的交付里写得很清楚 ——
//     "写缩放器改回板上验证过的最近邻实现，避免双线性写通路在真实 SD 节拍下停止输出"。
//   它的失效现象与本项目长期症状完全一致：写侧停一拍，整帧就凑不满
//   frame_fifo_write 那个零余量的完成判据（307200 个像素），于是这一张永远提交不了
//   —— 屏幕上就是"黑着不动"，偶尔够巧才出一张。
//   最近邻那份还更省资源（少一组行缓存/插值逻辑）。
bmp_write_scaler #(.ANTIALIAS(RELIABLE_MEDIA)) u_bmp_write_scaler (
    .clk       (clk),
    .rst       (rst | hard_recover | load_abort),
    // 显式取低 12 位（头解析那里已经保证 1..4095，高位恒 0）
    .src_w     (bmp_src_w[11:0]),
    .src_h     (bmp_src_h[11:0]),
    .src_sof   (bmp_data_start),
    .src_valid (bmp_data_wr_en),
    .src_pixel (bmp_data),
    .dst_valid (scaler_valid),
    .dst_pixel (scaler_pixel),
    .overflow  (scaler_overflow)
);


assign write_data = {scaler_pixel[23:16], scaler_pixel[15:8], scaler_pixel[7:0], 8'b0};
// 对外报告的是"轮播实际在不在跑"，警报模式下强制为 1（led[1] 因此如实反映）
assign auto_play_en_out = auto_play_eff;
assign page_index_out = img_idx;
// Ordinary interval includes loading; emergency uses its original dwell ticks.
// ★ 这里**不再**给警报模式另挂一个 32 位比较器 + 32 位 mux：本工程 mslices
//   已经贴着器件上限（4900），那种写法白扔一个 LUT 堆。改成“数满
//   EMER_TICK_PHASES 个 1 s 的 tick 才算一次停留”，只多一个 3 位计数器。
localparam [31:0] AUTO_TICK_NORMAL =
    ((REMOTE_SCHEDULE?1:(CLK_FREQ_HZ/1000))*NORMAL_INTERVAL_MS)-1;
localparam [31:0] NORMAL_FADE_START = (REMOTE_SCHEDULE?1:(CLK_FREQ_HZ/1000)) *
    ((NORMAL_INTERVAL_MS > NORMAL_FADE_MS) ? (NORMAL_INTERVAL_MS-NORMAL_FADE_MS) : 0);
localparam [31:0] AUTO_TICK_1S     = REMOTE_SCHEDULE?999:CLK_FREQ_HZ-1;
localparam [31:0] EMER_FADE_START = (REMOTE_SCHEDULE?1:(CLK_FREQ_HZ/1000)) *
    ((1000 > NORMAL_FADE_MS) ? (1000-NORMAL_FADE_MS) : 0);
localparam integer EMER_TICK_PHASES = (EMER_DWELL_MS + 999) / 1000;
localparam [2:0]   EMER_PHASE_LAST  = EMER_TICK_PHASES - 1;
reg  [2:0]         emer_dwell_phase;
wire [31:0]        auto_tick_limit = emergency_on ? AUTO_TICK_1S : AUTO_TICK_NORMAL;
wire               auto_tick_base  = (auto_cnt == auto_tick_limit);
wire auto_tick_1s=emergency_on && auto_tick_base && ms_enable;
wire remote_online=REMOTE_SCHEDULE && remote_phase[8];
wire remote_current=remote_online && remote_phase[5] && remote_phase[0]==disp_src_toggle;
assign interval_selection=remote_online?remote_phase[4:3]:2'd0;
assign carousel_feedback={normal_prefetch && load_visual_active,
                          normal_prefetch && source_done_seen && write_done_seen,
                          auto_play_en,display_valid,disp_src_toggle};
assign auto_tick=emergency_on ? (auto_tick_1s && emer_dwell_phase>=EMER_PHASE_LAST) :
                 (remote_online ? (remote_current && remote_phase[2]) : auto_tick_base);
assign next_from_current = next_index_limited(img_idx, img_found_count, emergency_on);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

// ---------------------------------------------------------------------------
// Emergency entry uses a completed SDRAM buffer-2 cache. The alarm can be
// selected immediately without reading TF again; buffers 0/1 remain ordinary.
// Abort drains the old sector, resets the scaler and excludes late completion.
// If the cache is unavailable, load alarm first using the same protected path.
reg  emer_preempt;
reg  emer_req_pending;
// Buffer 2 is reserved for a completed fire-alarm frame. Normal buffers stay 0/1.
reg alarm_cache_ready, alarm_cache_loading, alarm_cache_attempted;
reg [15:0] alarm_cache_w, alarm_cache_h;
// Keep the last committed ordinary frame across emergency. Static loads use
// the other 0/1 buffer; buffer 2 remains the independent alarm cache.
reg normal_cache_ready;
reg [1:0] normal_cache_buf;
reg [2:0] normal_cache_idx;
reg [15:0] normal_cache_w, normal_cache_h;
wire [1:0] next_load_buf = (emergency_on && normal_cache_ready) ?
                          (normal_cache_buf == 2'd0 ? 2'd1 : 2'd0) :
                          next_buf_lut(disp_buf_idx, display_valid);
assign write_en = scaler_valid && load_busy && !load_abort && !emer_preempt;
// 组合判据：**本拍**按下应急键、且本拍正好有普通图在飞。提交分支与置位都用它，
// 免得"按下那一拍正好提交"漏掉（漏掉的话那张普通图还是会闪一下）。
wire emer_preempt_now = emergency_rise && load_busy && (load_idx != 3'd0);
// A prepared static frame may become commit-eligible on the same clock
// that emergency falls. Suppress that commit before the exit flag latches.
wire emer_exit_preempt_now = emergency_fall && load_busy &&
                            ((load_idx < 3'd2) || normal_cache_ready);
// Ordinary prefetch is visually silent until both completions are latched
// and the last NORMAL_FADE_MS of the uniform interval begins. A late read
// freezes the timer before this window, keeping the old frame fully visible.
// Manual/emergency loads retain the existing progress-based transition.
wire bmp_nearly_done;
wire background_alarm = alarm_cache_loading && display_valid && !emergency_on;
wire normal_fade_window = normal_prefetch && auto_play_eff &&
                         source_done_seen && write_done_seen &&
                         (remote_online ? (remote_current && remote_phase[1]) : (auto_cnt >= NORMAL_FADE_START));
wire static_fade_window = static_prefetch && emergency_on &&
                         source_done_seen && write_done_seen &&
                         (emer_dwell_phase >= EMER_PHASE_LAST) &&
                         (auto_cnt >= EMER_FADE_START);
wire visual_window = normal_prefetch ? normal_fade_window :
                     (static_prefetch ? static_fade_window : !background_alarm);
assign load_nearly_done = load_busy && (normal_prefetch ? normal_fade_window :
                         (static_prefetch ? static_fade_window : (bmp_nearly_done && !background_alarm))) &&
                         !emer_preempt && !emer_preempt_now;
always @(posedge clk or posedge rst) begin
    if(rst) load_visual_active <= 1'b0;
    else load_visual_active <= sd_init_done && display_valid && load_busy && !load_abort &&
        (write_buf_idx != disp_buf_idx) &&
        visual_window && !emer_preempt && !emer_preempt_now;
end

// Follow the vendor example: latch source completion and frame-write completion
// independently.  Either side may finish first; only commit once both are true.
// A complete automatic prefetch waits for its deadline; this completed hold
// is exempt from the stall watchdog, while incomplete reads remain protected.
wire load_frame_ready = load_busy && source_done_seen && write_done_seen;
wire load_commit = load_frame_ready &&
                   (!normal_prefetch || emergency_on || (auto_play_eff && auto_tick)) &&
                   (!static_prefetch || !emergency_on || auto_tick);
// Returning to IDLE without explicit completion is a failed source read,
// including reads that produced part of a frame before failing.
// Catch it as soon as the source FSM reports ready, instead of waiting the
// full 1 s load watchdog.
wire load_source_fail = load_busy && load_started_seen && bmp_ready &&
                        !source_done_seen && !bmp_load_complete;
// 缩放器自己的溢出（生产者追上消费者，见 bmp_write_scaler.v 的速率预算）：
// 正常尺寸下**永远不该发生**（余量 10~25 倍），一旦发生说明源图小得离谱。
// 复用它走同一条"放弃 + 重发"的路径，并给它单独的故障码 4。
wire load_ovf_expire = load_busy && scaler_overflow;
wire recovery_wait = !load_busy && !bmp_ready &&
                     (load_retry_pending || next_req_pending || emer_req_pending || emer_preempt);
// Production registers the long timeout comparison before its recovery fanout.
// It adds one clock to the one-second stall limit; success still wins atomically.
reg load_wd_limit;
always @(posedge clk or posedge rst)
 if(rst)load_wd_limit<=0;else load_wd_limit<=load_wd_cnt==LOAD_TIMEOUT_LAST;
wire load_wd_expire  = (load_wd_en && (load_busy || recovery_wait) && !load_frame_ready &&
                        (RELIABLE_MEDIA?load_wd_limit:(load_wd_cnt == LOAD_TIMEOUT_LAST))) ||
                       load_ovf_expire || load_source_fail;

// ★ "有进展" —— 看门狗测的必须是**卡住**，不是**总时长**。
//
// 看门狗第一版只有"load_busy 一直高就往上数"，只有 !load_busy 才清零。
// 那在 640x480 时代没问题（载一张实测约 0.4 s，1000 ms 有 2.5 倍余量），
// 但 C2-a 放开分辨率之后**必然出事**：
//
//     板上 SPI 实测约 2.3 MB/s（921654 字节 / 0.4 s）
//       640x480  =  921,654 字节 -> 0.40 s   余量 2.5x  ✔
//       800x600  = 1,440,054 字节 -> 0.62 s   余量 1.6x  ← 已经很薄
//       1280x720 = 2,764,854 字节 -> 1.20 s   **超过 1000 ms**  ✘
//
// 1280x720 撞上之后会怎样：超时 -> 重发同一张 -> 又是 1.2 s -> 再超时……
// 板上表现是**停在那张图反复重试**，而故障码显示 1/2/3 中的某一个，
// 看起来像 SD 或写通路坏了 —— 其实是"这图本来就比超时窗口慢"。
// 换句话说：看门狗本来是用来消掉"卡死"的，却给大图**造了一个新的卡死**。
//
// 所以改成**失速检测**：只要还有像素在往缩放器里送，就说明载图在前进，
// 计数器清零。只有**真的一个像素都进不来**才算卡住。
// 这样超时窗口和图片大小彻底解耦 —— 4K 图（若真用到）也不会误判。
//
// 为什么取 `bmp_data_wr_en`（bmp_read 刚解出来的像素）而不是 SD 的字节流：
//   它是"载图前进"最贴近的那一个信号。SD 字节在流、但 bmp_read 卡住
//   （比如不在 ST_LOAD_DATA）这种情况下，字节流仍会跳，用它就永远不超时了。
//
// ⚠️ 语义变化要说清楚：`LOAD_TIMEOUT_MS` 现在读作
//    「**多久没有新像素进来**就算卡住」，不再是「整张图最多载多久」。
//
// 两个信号都要算进展：源像素在进来（bmp_data_wr_en），**或者**缩放器还在把
// 行缓存里剩的往外排（write_en）。只取前者的话，源刚送完、缩放器正在收尾
// 那一小段也会被当成"没进展"（虽然它短得不可能撞上 1 s，但判据写全更省事）。
// 两个都不会误报持久：write_en 只有在缩放器手里真有数据时才可能跳。
wire load_progress = bmp_data_wr_en | write_en;

// 按键语义：短按触发 short_pulse，按住超过 HOLD_MS 后改发 long_step。
//
// 旧参数（消抖 20 ms / 长按 700 ms）在真实板子上有两个问题：
//   1. 消抖 20 ms 意味着手必须按满 20 ms 才被认账，快速轻点会被整下吞掉；
//   2. 短按只在"松手"时判定，而 700 ms 的长按门槛太容易越过——用户按
//      S2 想切下一张，手指多停半秒就变成调亮度，表现就是"切不了图"。
// 现在消抖收到 6 ms（机械抖动典型 < 5 ms），长按门槛提到 1400 ms，
// 正常按压一定判为短按。
key_short_long #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (6),
    .HOLD_MS     (1400),
    .REPEAT_MS   (300)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .short_pulse(key_next_press),
    .long_step  (key_next_long_step)
);

key_short_long #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (6),
    .HOLD_MS     (1400),
    .REPEAT_MS   (300)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .short_pulse(key_auto_press),
    .long_step  (key_auto_long_step)
);

// Parameter events belong to user controls, independently of SD init/recovery.
// Reset only with the system reset: SD retries must neither lose a long press
// nor reset a high toggle to zero and generate a phantom increment downstream.
always @(posedge clk or posedge rst)begin
 if(rst)begin brightness_step_toggle<=0;contrast_step_toggle<=0;end
 else begin
  if(key_next_long_step)brightness_step_toggle<=~brightness_step_toggle;
  if(key_auto_long_step)contrast_step_toggle<=~contrast_step_toggle;
 end
end

// 下一张图的编号。
// 最终卡组固定 5 张：
//   正常模式 = 2/3/4（扫描顺序最后 3 张）—— **永远不碰 0/1**
//   警报模式 = 0/1（扫描顺序前 2 张）—— 只有 S4 按下才走这一支
// 硬编码这 5 个槽位避免在 SD 时钟域生成宽减法/大 mux。
//
// ★ 2026-09-29：原来 count < 5 时**无条件返回 3'd0**，而页 0 正是火灾报警
//   图！只要卡上没扫满 5 张（少一张、某张头不合规、图排在 64 MB 之外……），
//   普通轮播就会把紧急图轮出来。现在普通分支按 count 算普通组范围，
//   任何 count 都只返回 >= 2 的索引，紧急图不可能再进普通轮播。
function [2:0] next_index_limited;
    input [2:0] cur;
    input [2:0] count;
    input       emer;
    begin
        if(RELIABLE_MEDIA)begin
            if(emer)next_index_limited=(cur==0 && img_slots[1])?1:(img_slots[0]?0:1);
            else case(cur)
                2:next_index_limited=img_slots[3]?3:img_slots[4]?4:first_normal;
                3:next_index_limited=img_slots[4]?4:first_normal;
                default:next_index_limited=first_normal;
            endcase
        end else if (emer) begin
            // 警报组 = 扫描顺序前两张（0/1）
            if (count > 3'd1)
                next_index_limited = (cur == 3'd1) ? 3'd0 : 3'd1;
            else
                next_index_limited = 3'd0;   // 卡上只有一张图，只能显示它
        end else begin
            // 普通组 = 2 .. count-1；count<=3 时只有一张普通图，原地不动
            case (cur)
                3'd2: next_index_limited = (count > 3'd3) ? 3'd3 : 3'd2;
                3'd3: next_index_limited = (count > 3'd4) ? 3'd4 : 3'd2;
                default: next_index_limited = 3'd2;
            endcase
        end
    end
endfunction

function [31:0] sector_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: sector_lut = img_sector0;
            3'd1: sector_lut = img_sector1;
            3'd2: sector_lut = img_sector2;
            3'd3: sector_lut = img_sector3;
            3'd4: sector_lut = img_sector4;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;img_slots<=0;
        img_idx               <= 3'd0;
        load_idx              <= 3'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        img_sector4           <= 32'd0;
        next_req_pending      <= 1'b0;
        next_req_idx          <= 3'd0;
        load_busy             <= 1'b0;
        normal_prefetch       <= 1'b0;
        static_prefetch       <= 1'b0;
        load_abort            <= 1'b0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        display_valid         <= 1'b0;
        disp_src_w            <= 16'd0;
        disp_src_h            <= 16'd0;
        disp_src_toggle       <= 1'b0;
        disp_audio_emergency  <= 1'b0;
        emergency_sync         <= 3'b000;
        emergency_on_d         <= 1'b0;
        hard_recover           <= 1'b0;
        hard_recover_cnt       <= 6'd0;
        emer_preempt           <= 1'b0;
        emer_req_pending       <= 1'b0;
        load_error_total       <= 4'd0;
        load_fault             <= 4'd0;
        load_wd_cnt            <= 27'd0;
        load_retry_pending     <= 1'b0;
        load_timeout_count     <= 4'd0;
        load_data_seen         <= 1'b0;
        load_started_seen      <= 1'b0;
        scan_retry_pending     <= 1'b0;
        scan_retry_cnt         <= 27'd0;
        empty_scan_count       <= 3'd0;
        alarm_cache_ready <= 1'b0;
        alarm_cache_loading <= 1'b0;
        alarm_cache_attempted <= 1'b0;
        alarm_cache_w <= 16'd0;
        alarm_cache_h <= 16'd0;
        normal_cache_ready <= 1'b0;
        normal_cache_buf <= 2'd0;
        normal_cache_idx <= 3'd2;
        normal_cache_w <= 16'd0;
        normal_cache_h <= 16'd0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        load_abort       <= 1'b0;

        // 警报模式的三级同步 + 边沿检测，独立于 sd_init_done（纯 CDC，不参与复位策略）
        emergency_sync <= {emergency_sync[1:0], emergency};
        emergency_on_d <= emergency_on;

        // Hold the one-shot recovery level long enough for the SD and
        // SDRAM controllers to fully reinitialize. This counter lives
        // outside the normal scan state so dropping sd_init_done cannot
        // accidentally cancel the pulse.
        if (hard_recover) begin
            if (hard_recover_cnt == 6'd0)
                hard_recover <= 1'b0;
            else
                hard_recover_cnt <= hard_recover_cnt - 6'd1;
        end

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;img_slots<=0;
            img_idx               <= 3'd0;
            load_idx              <= 3'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            img_sector4           <= 32'd0;
            next_req_pending      <= 1'b0;
            next_req_idx          <= 3'd0;
            load_busy             <= 1'b0;
            normal_prefetch       <= 1'b0;
            static_prefetch       <= 1'b0;
            load_abort            <= 1'b0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            display_valid         <= 1'b0;
            load_wd_cnt            <= 27'd0;
            load_retry_pending     <= 1'b0;
            load_timeout_count     <= 4'd0;
            // Keep the last fault and recurrence count across self-recovery.
            load_data_seen         <= 1'b0;
            load_started_seen      <= 1'b0;
            emer_preempt           <= 1'b0;
            emer_req_pending       <= 1'b0;
            scan_retry_pending     <= 1'b0;
            scan_retry_cnt         <= 27'd0;
            empty_scan_count       <= 3'd0;
            alarm_cache_ready <= 1'b0;
            alarm_cache_loading <= 1'b0;
            alarm_cache_attempted <= 1'b0;
            alarm_cache_w <= 16'd0;
            alarm_cache_h <= 16'd0;
            normal_cache_ready <= 1'b0;
        end else begin
            // A cached frame ceases to be usable before its buffer is reused.
            // Emergency allocation above prevents this for the protected page.
            if(load_start_pulse && normal_cache_ready && write_buf_idx == normal_cache_buf)
                normal_cache_ready <= 1'b0;
            // 扫描阶段缓存前 5 张图的起始 sector
            // （第 1/2 张就是警报模式要轮播的紧急两张）
            if (scan_found_valid) begin
                empty_scan_count <= 3'd0;
                case (RELIABLE_MEDIA?scan_found_slot:img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    3'd4: img_sector4 <= scan_found_sector;
                    default: ;
                endcase

                if(RELIABLE_MEDIA)begin
                    img_slots[scan_found_slot]<=1'b1;
                    if(scan_found_slot>=img_found_count)img_found_count<=scan_found_slot+1'b1;
                end else if(img_found_count<5)img_found_count<=img_found_count+1'b1;
            end

            // 本次载图**源侧**有没有真的吐过像素。
            // 全部超时都是「bmp_read 已空闲」，靠它区分两种性质完全不同的根因：
            //   没送过 -> 头被拒 / 零长度（根因在 bmp_read 的解析）
            //   送过了 -> 整帧写永远完不成（根因在写通路）
            //
            // ⚠️ 判据必须是 `bmp_data_wr_en`（bmp_read 刚解出来的源像素），
            //    **不能**用 `write_en` —— C2-a(b) 把写侧缩放器插进这条路之后，
            //    `write_en` 已经变成**缩放器的输出**了：缩放器要先把一整行源像素
            //    收进行缓存才可能吐第一个像素。于是"源图明明送了数据、只是还没攒满
            //    一行"会被错报成故障码 2（"一个像素都没送"），指向"头被拒"这个
            //    完全不相干的根因。
            //    实测就是这样：`tb_load_watchdog` 的 B2 从 3 变成 2、B4（复发）从 1 变 0。
            //    改回 bmp_data_wr_en 之后，语义与 bilin2（缩放器还没接进去时）**逐字一致**。
            // Incomplete-scan recovery.  Normal mode needs at least one page
            // in the 2/3/4 group, so fewer than three valid images must not
            // be treated as a usable scan.  Retry after a short delay;
            // repeated failures reinitialize the SD path.  This also recovers
            // a card inserted after power-up.
            if (scan_done && !normal_group_ready &&
                !load_busy && !scan_retry_pending) begin
                scan_retry_pending <= 1'b1;
                scan_retry_cnt     <= SCAN_RETRY_LAST;
                if (empty_scan_count != 3'd7)
                    empty_scan_count <= empty_scan_count + 3'd1;
            end else if (scan_retry_pending) begin
                if (scan_retry_cnt == 27'd0) begin
                    scan_retry_pending <= 1'b0;
                    scan_retry_cnt     <= 27'd0;
                    scan_kicked        <= 1'b0;
                    if (empty_scan_count >= 3'd2) begin
                        hard_recover     <= 1'b1;
                        hard_recover_cnt <= 6'd31;
                        empty_scan_count <= 3'd0;
                    end
                end else begin
                    scan_retry_cnt <= scan_retry_cnt - 27'd1;
                end
            end

            if(RELIABLE_MEDIA && emergency_on && !img_slots[0])emer_req_pending<=0;
            if (!load_busy)
                load_started_seen <= 1'b0;
            else if (!bmp_ready)
                load_started_seen <= 1'b1;

            if (load_busy && bmp_data_wr_en)
                load_data_seen <= 1'b1;

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && bmp_load_complete)
                source_done_seen <= 1'b1;

            // Latch the write-side completion independently.  If the frame-writer
            // pulse arrives before the source side reports ready, it must not be
            // lost, otherwise the page switch stalls until the load watchdog.
            if (load_busy && load_data_seen && write_finish_pulse)
                write_done_seen <= 1'b1;

            // 只有真正收到 write_finish_toggle 脉冲，才提交新图并切换显示缓冲区
            if (load_commit) begin
                load_busy             <= 1'b0;
                normal_prefetch       <= 1'b0;
                static_prefetch       <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                // A successful commit breaks the consecutive-failure chain.
                // load_error_total remains latched for the diagnostic dot.
                load_timeout_count    <= 4'd0;
                // ★ 应急抢载：这次提交**不上屏**（见 emer_preempt 的说明）。
                //   load_busy 照常放开 ⇒ 紧接着的应急请求下一拍就能发起，
                //   write_buf_idx 也还是那一块（非显示块），不用动。
                if (alarm_cache_loading) begin
                    alarm_cache_ready <= 1'b1;
                    alarm_cache_loading <= 1'b0;
                    alarm_cache_w <= bmp_src_w;
                    alarm_cache_h <= bmp_src_h;
                    if (emergency_on) begin
                        disp_buf_idx <= 2'd2;
                        img_idx <= 3'd0;
                        display_valid <= 1'b1;
                        first_image_committed <= 1'b1;
                        disp_src_w <= bmp_src_w;
                        disp_src_h <= bmp_src_h;
                        disp_audio_emergency <= 1'b1;
                        disp_src_toggle <= ~disp_src_toggle;
                    end
                end else if (emer_preempt || emer_preempt_now || emer_exit_preempt_now) begin
                    emer_preempt          <= 1'b0;
                end
                else begin
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    // 与 display_valid / disp_buf_idx **同一拍**锁存，三者永远对齐：
                    // OSD 上的分辨率一定属于屏幕上正在显示的那张图。
                    disp_src_w            <= bmp_src_w;
                    disp_src_h            <= bmp_src_h;
                    disp_audio_emergency <= emergency_on;
                    disp_src_toggle       <= ~disp_src_toggle;
                    if(load_idx >= 3'd2 && pending_buf_idx < 2'd2)begin
                        normal_cache_ready <= 1'b1;
                        normal_cache_buf <= pending_buf_idx;
                        normal_cache_idx <= load_idx;
                        normal_cache_w <= bmp_src_w;
                        normal_cache_h <= bmp_src_h;
                    end
                end
            end

            // ------------------------------------------------------------------
            // 载图看门狗：超时就把 load_busy 放开并安排"重发同一张"
            //
            // 板上实测（2026-09-19，smart_terminal_bilin 第二次烧录）：
            //   显示了几张之后图片卡着不动，数码管 state_code 变 0
            //   （= sd_init_done 掉了 / 整个 SD 侧被复位），而**所有**发起载图的
            //   分支都带 !load_busy ⇒ 一旦 load_busy 卡死，轮播就彻底停摆。
            //   正常一次载图约 0.4 s，所以 1 s 有 2.5 倍余量。
            //
            // 重试**不推进** load_idx / load_sector / pending_buf_idx / write_buf_idx，
            // 也不动 disp_buf_idx ⇒ 画面在整个重试期间仍然是上一张好图，
            // 不会黑屏、不会花屏。
            // ------------------------------------------------------------------
            // ★ load_progress 也要清零 —— 见上面 load_progress 的注释：
            //   有像素在进来就说明没卡住，不管已经载了多久。
            if ((!load_busy && !recovery_wait) || load_frame_ready || !load_wd_en || load_progress)
                load_wd_cnt <= 27'd0;
            else if (load_wd_cnt != LOAD_TIMEOUT_LAST)
                load_wd_cnt <= load_wd_cnt + 27'd1;

            if (load_wd_expire) begin
                load_busy          <= 1'b0;
                normal_prefetch    <= 1'b0;
                static_prefetch    <= 1'b0;
                load_abort         <= 1'b1;
                alarm_cache_loading <= 1'b0;
                source_done_seen   <= 1'b0;
                write_done_seen    <= 1'b0;
                load_wd_cnt        <= 27'd0;
                // 被抢载的那张超时了：压 nearly 的窗口跟着关掉（重试由下面的
                // 应急抢载分支接管，见 emer_req_pending）
                emer_preempt       <= 1'b0;
                if (load_timeout_count != 4'hF)
                    load_timeout_count <= load_timeout_count + 4'd1;
                if (load_error_total != 4'hF)
                    load_error_total <= load_error_total + 4'd1;

                // 记下**这次超时卡在哪一层**（取最近一次；板子正卡着时它就是当前这次）
                //   4 = 写侧缩放器的行缓冲被追上了（源图过小，正常不会出现）
                load_fault <= scaler_overflow ? 4'd4 :
                              (bmp_ready ? (load_data_seen ? 4'd3 : 4'd2)
                                         : 4'd1);

                // ★ 2026-09-29（照官方例程 lab_ex4_tf 的思路改）：
                //   官方文档的原则是"图片损坏/截断/分辨率不对时，1 s 超时就**强制放弃这一张**，
                //   把控制权交回来，保证系统继续运行"。本工程原来是"超时 -> 重发同一张 ->
                //   再超时就 hard_recover（重新初始化 SD + 重新扫卡）"，一旦卡上有一张
                //   残图/坏图，就会一直卡在它身上，画面断在那里 —— 正是上板看到的"会断"。
                //   现在：**第一次超时原图重发一次（可能是偶发），第二次起直接跳下一张**，
                //   坏图自动绕过去，系统继续轮播。
                if (load_timeout_count == 4'd0) begin
                    load_retry_pending <= 1'b1;
                end else begin
                    load_retry_pending <= 1'b0;
                    next_req_idx       <= next_index_limited(load_idx, img_found_count, emergency_on);
                    next_req_pending   <= 1'b1;
                    auto_cnt           <= 32'd0;
                end

                // 只有当**连着**栽了 4 次才动 hard_recover：那基本是 SD 控制器/写通路真卡死了，
                // 重扫一次（几秒黑屏）比原地打转值得。门槛从原来的 2 提到 4，
                // 免得一张坏图就把整条链路重启一遍。
                if (!hard_recover && (recovery_wait || (load_timeout_count >= 4'd3))) begin
                    hard_recover     <= 1'b1;
                    hard_recover_cnt <= 6'd31;
                end
            end

            // 上电后自动发起一次“扫描前 5 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b1;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;img_slots<=0;
                img_idx               <= 3'd0;
                load_idx              <= 3'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                normal_prefetch       <= 1'b0;
                static_prefetch       <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                load_wd_cnt           <= 27'd0;
                load_retry_pending    <= 1'b0;
                load_timeout_count    <= 4'd0;
                // Re-scanning must not erase the failure that caused it.
                load_data_seen        <= 1'b0;
                emer_dwell_phase      <= 3'd0;
                emer_preempt          <= 1'b0;
                emer_req_pending      <= 1'b0;
                next_req_idx          <= 3'd0;
                scan_retry_pending    <= 1'b0;
                scan_retry_cnt        <= 27'd0;
                normal_cache_ready <= 1'b0;
            end else begin
                // 手动切图请求：忙的时候也只记 1 次，不会累积成连跳两张。
                // 如果当前正在载入的恰好就是本拍请求的下一张，则不再重复排队，
                // 这张载完后直接上屏即可，避免"按一下却多跳一张"的双重等待。
                // ★ 目标页 == 当前页就别发起载图（本组只有一张时 next_from_current
                //   就是当前页）：重载同一张只会走一遍"淡出→写帧缓存→淡入"，
                //   上板看到的就是"按了没反应还黑一下"。S2/自动轮播共用这条判据。
                if (key_next_press && scan_done && (img_found_count > 3'd0) &&
                    (next_from_current != img_idx)) begin
                    if (!load_busy) begin
                        next_req_idx     <= next_from_current;
                        next_req_pending <= 1'b1;
                    end else if (load_idx == next_from_current) begin
                        next_req_pending <= 1'b0;
                        // Manual next releases a matching prefetch as soon as
                        // both completions exist; it never submits partial data.
                        normal_prefetch <= 1'b0;
                        static_prefetch <= 1'b0;
                    end else begin
                        next_req_idx     <= next_from_current;
                        next_req_pending <= 1'b1;
                    end
                end

                // 按下 S4 进入警报模式：**立刻抢载页 0（火灾报警图）**。
                // ★ 第五轮：此刻若正好有载图在飞，那张普通图会先提交上屏
                //   （上板现象"先轮播到下一张，再放火灾报警图"），所以让那次
                //   提交不上屏（emer_preempt）并压掉它的 nearly；提交完立刻
                //   抢载页 0（emer_req_pending）。
                //   在飞的本来就是页 0 ⇒ 什么都不做，它自己就是火灾报警图。
                if (emergency_rise && scan_done && (img_found_count > 3'd1)) begin
                    normal_prefetch <= 1'b0;
                    static_prefetch <= 1'b0;
                    auto_cnt <= 32'd0;
                    emer_dwell_phase <= 3'd0;
                    next_req_pending <= 1'b0;
                    load_retry_pending <= 1'b0;
                    if (alarm_cache_ready) begin
                        disp_buf_idx <= 2'd2;
                        img_idx <= 3'd0;
                        display_valid <= 1'b1;
                        first_image_committed <= 1'b1;
                        disp_src_w <= alarm_cache_w;
                        disp_src_h <= alarm_cache_h;
                        disp_audio_emergency <= 1'b1;
                        disp_src_toggle <= ~disp_src_toggle;
                        emer_req_pending <= load_busy && (load_idx != 3'd0);
                    end else if (!load_busy || (load_idx != 3'd0)) begin
                        emer_req_pending <= 1'b1;
                    end
                    // Drop the old source only through the existing abort/drain
                    // handshake. Reset scaler output before the writer restarts.
                    if (load_busy && (load_idx != 3'd0)) begin
                        load_abort <= 1'b1;
                        load_busy <= 1'b0;
                        source_done_seen <= 1'b0;
                        write_done_seen <= 1'b0;
                        load_started_seen <= 1'b0;
                        load_data_seen <= 1'b0;
                        load_wd_cnt <= 27'd0;
                        alarm_cache_loading <= 1'b0;
                        emer_preempt <= 1'b1;
                        emer_req_pending <= 1'b1;
                    end
                end

                // ★ 退出警报（S4 再按一次）：普通模式从这一拍起不允许再显示
                //   前两张紧急图。
                //     1) 在飞的载图如果是紧急图（页 0/1），压掉它的提交
                //        （复用应急抢载的 emer_preempt，见提交分支）；
                //     2) 立刻排队载入普通组第一张（页 2），不用等下一个轮播 tick；
                //     3) 清掉可能还没执行的抢载请求，免得它之后在普通模式下
                //        把火灾报警图载上来（S4 连按两下时就会踩到）。
                if (emergency_fall) begin
                    normal_prefetch <= 1'b0;
                    static_prefetch <= 1'b0;
                    auto_cnt         <= 32'd0;
                    emer_req_pending <= 1'b0;
                    load_retry_pending <= 1'b0;
                    if (scan_done && normal_cache_ready) begin
                        // Select existing complete SDRAM data immediately.
                        // Cancel old requests/writes; never restart a TF read
                        // merely to restore the page that was already visible.
                        disp_buf_idx <= normal_cache_buf;
                        img_idx <= normal_cache_idx;
                        display_valid <= 1'b1;
                        first_image_committed <= 1'b1;
                        disp_src_w <= normal_cache_w;
                        disp_src_h <= normal_cache_h;
                        disp_audio_emergency <= 1'b0;
                        disp_src_toggle <= ~disp_src_toggle;
                        next_req_pending <= 1'b0;
                        if(load_busy)begin
                            load_abort <= 1'b1;
                            load_busy <= 1'b0;
                            source_done_seen <= 1'b0;
                            write_done_seen <= 1'b0;
                            load_started_seen <= 1'b0;
                            load_data_seen <= 1'b0;
                            load_wd_cnt <= 27'd0;
                            alarm_cache_loading <= 1'b0;
                            emer_preempt <= 1'b1;
                        end
                    end else if (scan_done && (img_found_count > 3'd2)) begin
                        if (load_busy) begin
                            // 在飞的已经是普通图（页 2/3/4）就让它正常提交
                            if (load_idx < 3'd2) begin
                                // A held or partial static read must not pin
                                // restoration behind its old write completion.
                                // Abort/drain it through the same safe sector
                                // handshake used on entry, then restore normal.
                                load_abort <= 1'b1;
                                load_busy <= 1'b0;
                                source_done_seen <= 1'b0;
                                write_done_seen <= 1'b0;
                                load_started_seen <= 1'b0;
                                load_data_seen <= 1'b0;
                                load_wd_cnt <= 27'd0;
                                alarm_cache_loading <= 1'b0;
                                emer_preempt     <= 1'b1;
                                next_req_idx     <= first_normal;
                                next_req_pending <= 1'b1;
                            end
                        end else begin
                            next_req_idx     <= first_normal;
                            next_req_pending <= 1'b1;
                        end
                    end
                end

                // 自动播放开/关（警报模式下 auto_play_eff 恒为 1，这里改的是退出警报后的状态）
                if (key_auto_press && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // Ordinary time runs during prefetch and complete-frame hold.
                // If loading misses the fade window, freeze before darkening;
                // after completion give the fade its full window before commit.
                // The first background alarm cache and the static emergency
                // prefetch count within the existing 3 s / 2 s intervals.
                // Late static data freezes before its fade window as well.
                if ((load_commit && !background_alarm) || emergency_rise || emergency_fall || key_auto_press)
                    auto_cnt <= 32'd0;
                else if (remote_online && !emergency_on)auto_cnt<=0;
                else if (scan_done && auto_play_eff && display_valid &&
                         (!load_busy || normal_prefetch || static_prefetch || background_alarm) &&
                         first_image_committed && rotate_available) begin
                    if (emergency_on) begin
                        if (static_prefetch && (emer_dwell_phase >= EMER_PHASE_LAST) &&
                            (auto_cnt >= EMER_FADE_START) && !load_frame_ready)
                            auto_cnt <= auto_cnt;
                        else if (auto_tick_1s) auto_cnt <= 32'd0;
                        else if(ms_enable)auto_cnt <= auto_cnt + 1'b1;
                    end else if (auto_cnt < AUTO_TICK_NORMAL) begin
                        if (ms_enable && ((auto_cnt < NORMAL_FADE_START) || load_frame_ready))
                            auto_cnt <= auto_cnt + 1'b1;
                    end
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 警报模式的停留相位：每过 1 s 翻一格，数满 EMER_TICK_PHASES 格
                // 才算一张紧急图停留结束（见上面 auto_tick 的推导）。
                // 退出警报 / 关掉轮播就归零，下次进警报重新数。
                if (!emergency_on || !auto_play_eff)
                    emer_dwell_phase <= 3'd0;
                else if (auto_tick_1s)
                    emer_dwell_phase <= (emer_dwell_phase >= EMER_PHASE_LAST) ? 3'd0
                                                                            : (emer_dwell_phase + 3'd1);

                // ★ 应急抢载：**最高优先级**，目标永远是页 0（见 emer_req_pending）。
                //   放在所有发起分支（含重试）之前 —— 重试要重发的是一张普通图，
                //   不能压过火灾报警图。
                // ★ 多了个 emergency_on 门：抢载请求只有在警报模式**仍然有效**时
                //   才执行。S4 连按两下（进了又出）时，残留的请求不会在普通模式
                //   下把页 0 载上来。
                // Show the first ordinary frame before loading the alarm cache.
                // Cache fills silently behind that first picture; the ordinary
                // 3-second timer includes this work. Cold emergency takes priority.
                if (emergency_fall) begin
                    // Exit owns this clock. Do not allocate using the old
                    // display index while the cache selection is taking effect.
                end else if (scan_done && bmp_ready && !load_busy && normal_group_ready &&
                    !alarm_cache_attempted && (!RELIABLE_MEDIA || img_slots[0]) && (first_image_committed || emergency_on)) begin
                    alarm_cache_attempted <= 1'b1;
                    alarm_cache_loading <= 1'b1;
                    load_idx <= 3'd0;
                    load_sector <= img_sector0;
                    pending_buf_idx <= 2'd2;
                    write_buf_idx <= 2'd2;
                    load_start_pulse <= 1'b1;
                    load_busy <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen <= 1'b0;
                    load_data_seen <= 1'b0;
                    load_started_seen <= 1'b0;
                    load_retry_pending <= 1'b0;
                    emer_req_pending <= 1'b0;
                    emer_preempt <= 1'b0;
                    if (emergency_on) auto_cnt <= 32'd0;
                end else if (scan_done && bmp_ready && !load_busy && emer_req_pending &&
                             emergency_on && (img_found_count != 3'd0) && (!RELIABLE_MEDIA || img_slots[0])) begin
                    if (alarm_cache_ready) begin
                        emer_req_pending <= 1'b0;
                        emer_preempt <= 1'b0;
                    end else begin
                        load_idx <= 3'd0;
                        load_sector <= img_sector0;
                        pending_buf_idx <= 2'd2;
                        write_buf_idx <= 2'd2;
                        alarm_cache_loading <= 1'b1;
                        load_start_pulse <= 1'b1;
                        load_busy <= 1'b1;
                        source_done_seen <= 1'b0;
                        write_done_seen <= 1'b0;
                        emer_req_pending <= 1'b0;
                        next_req_pending <= 1'b0;
                        next_req_idx <= 3'd0;
                        load_retry_pending <= 1'b0;
                        load_data_seen <= 1'b0;
                        auto_cnt <= 32'd0;
                        emer_preempt <= 1'b0;
                    end
                end
                // 看门狗超时后的重试：重发**同一张**图。
                // 优先级仅次于应急抢载。
                else if (scan_done && bmp_ready && !load_busy && load_retry_pending && !emergency_rise) begin
                    alarm_cache_loading <= emergency_on && (load_idx == 3'd0) && (pending_buf_idx == 2'd2);
                    // ★ 普通模式绝不允许重发紧急图（页 0/1）：那张图超时了要重试，
                    //   就改成重发普通组第一张（页 2）。否则"进应急载图超时 ->
                    //   退出应急 -> 重试"会在普通轮播里把火灾报警图刷出来。
                    if (!emergency_on && (load_idx < 3'd2) && (img_found_count > 3'd2)) begin
                        load_idx         <= first_normal;
                        load_sector      <= sector_lut(first_normal);
                        pending_buf_idx  <= next_load_buf;
                        write_buf_idx    <= next_load_buf;
                    end
                    load_start_pulse   <= 1'b1;
                    load_busy          <= 1'b1;
                    source_done_seen   <= 1'b0;
                    write_done_seen    <= 1'b0;
                    load_retry_pending <= 1'b0;
                    load_data_seen     <= 1'b0;
                    auto_cnt           <= 32'd0;
                end
                // 首图自动加载到 buffer0；必须从普通组第一张（固定索引2）
                // 开始，不能先露出只应在 S4 显示的前两张紧急图。
                else if (scan_done && !first_image_committed && bmp_ready && !load_busy && normal_group_ready && !emergency_rise) begin
                    alarm_cache_loading <= 1'b0;
                    // ★ 2026-09-29 修正：首图如果**反复载失败**，上面的看门狗会安排
                    //   "跳下一张"（next_req_pending + next_req_idx）。这一支的优先级
                    //   比手动/自动那两支都高，原来在这里**死写索引 2**，会把跳转请求吃掉
                    //   —— 于是首图每次失败都从第 3 张重来，屏幕永远黑的（上板现象：
                    //   "完全读不出图"）。现在：有跳转请求就听它的，没有才走常规首图。
                    if (next_req_pending) begin
                        load_idx    <= next_req_idx;
                        load_sector <= sector_lut(next_req_idx);
                    end else begin
                        // 常规首图：普通组第一张（固定索引 2），
                        // 绝不能先露出只应在 S4 显示的紧急图 0/1。
                        load_idx    <= first_normal;
                        load_sector <= sector_lut(first_normal);
                    end
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    next_req_idx     <= 3'd0;
                    load_retry_pending <= 1'b0;
                    load_data_seen     <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张 / 应急抢载优先：写到“非当前显示”的另一块 buffer。
                // ★ 这里**不需要**再给"提交后紧接下一次载图"留收尾窗口：
                //   叠加层的淡入已经改成默认分支（只要不在淡出窗口里就把画面
                //   淡回来），load_in_flight 低够不够久都不再影响淡入。
                //   见 smart_terminal_overlay_pipelined.v 的 fade_alpha。
                else if (scan_done && bmp_ready && display_valid && !load_busy && next_req_pending &&
                         (img_found_count != 3'd0) && !emergency_rise) begin
                    alarm_cache_loading <= 1'b0;
                    emer_preempt <= 1'b0;
                    load_idx         <= next_req_idx;
                    load_sector      <= sector_lut(next_req_idx);
                    pending_buf_idx  <= next_load_buf;
                    write_buf_idx    <= next_load_buf;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    next_req_pending <= 1'b0;
                    next_req_idx     <= 3'd0;
                    load_retry_pending <= 1'b0;
                    load_data_seen     <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                // ★ 警报模式轮播到页 1（静态疏散图）就**停住**：不再 1->0 反复重载。
                //   否则每 1~2 s 就来一次淡出/淡入（还带黑幕），而页 1 正是
                //   动态疏散图的底图，晃一下就被看出来；停住也让页 1 有完整的停留。
                else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_eff &&
                         rotate_available && (next_from_current != img_idx) &&
                         (!emergency_on || (img_idx != 3'd1)) && !emergency_rise) begin
                    alarm_cache_loading <= 1'b0;
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_load_buf;
                    write_buf_idx    <= next_load_buf;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    normal_prefetch  <= !emergency_on;
                    static_prefetch  <= emergency_on;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    load_retry_pending <= 1'b0;
                    load_data_seen     <= 1'b0;
                    // Static emergency prefetch also includes read time in
                    // the existing 2-second alarm dwell; do not restart it.
                end
            end
        end
    end
end

bmp_read #(
    // bmp_read 内部的"载图停滞超时"要按同一个时钟频率折算（见 bmp_read.v 模块头）
    .CLK_FREQ_HZ            (CLK_FREQ_HZ),
    .STALL_TIMEOUT_MS       (BMP_STALL_TIMEOUT_MS),
    .LOAD_OVERRUN_GUARD     (BMP_OVERRUN_GUARD),
    .RELIABLE_MEDIA        (RELIABLE_MEDIA)
) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst | hard_recover),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .scan_found_slot        (scan_found_slot),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .load_complete          (bmp_load_complete),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .src_w                  (bmp_src_w),
    .src_h                  (bmp_src_h),
    .pixel_start            (bmp_data_start),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .load_nearly_done       (bmp_nearly_done)
);

sd_card_top #(.SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV),
    .CLK_FREQ_HZ(CLK_FREQ_HZ), .POWERUP_WAIT_MS(SD_POWERUP_WAIT_MS),
    .INIT_TIMEOUT_MS(SD_INIT_TIMEOUT_MS)) sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst | hard_recover),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_short_long #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer HOLD_MS = 700,
    parameter integer REPEAT_MS = 250
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  short_pulse,
    output reg  long_step,
    output wire button_down
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
localparam integer HOLD_CYCLES = (CLK_FREQ_HZ / 1000) * HOLD_MS;
localparam integer REPEAT_CYCLES = (CLK_FREQ_HZ / 1000) * REPEAT_MS;

// Each counter resets at its constant limit; retain the original thresholds
// while avoiding 32-bit counters for debounce/hold/repeat on every button.
function integer key_counter_width;
    input integer cycles;
    integer value;
    begin
        if (cycles <= 0) key_counter_width = 32;
        else begin
            key_counter_width = 1;
            for (value = cycles - 1; value > 1; value = value >> 1)
                key_counter_width = key_counter_width + 1;
        end
    end
endfunction
localparam integer DEBOUNCE_WIDTH = key_counter_width(DEBOUNCE_CYCLES);
localparam integer HOLD_WIDTH = key_counter_width(HOLD_CYCLES);
localparam integer REPEAT_WIDTH = key_counter_width(REPEAT_CYCLES);
localparam [DEBOUNCE_WIDTH-1:0] DEBOUNCE_LAST = DEBOUNCE_CYCLES - 1;
localparam [HOLD_WIDTH-1:0] HOLD_LAST = HOLD_CYCLES - 1;
localparam [REPEAT_WIDTH-1:0] REPEAT_LAST = REPEAT_CYCLES - 1;

reg sync0;
reg sync1;
reg stable;
assign button_down = !stable;
reg held_long;
reg [DEBOUNCE_WIDTH-1:0] debounce_cnt;
// First-hold and repeat phases are mutually exclusive. Share their timer.
localparam integer TIMER_WIDTH = HOLD_WIDTH > REPEAT_WIDTH ? HOLD_WIDTH : REPEAT_WIDTH;
reg [TIMER_WIDTH-1:0] hold_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync0        <= 1'b1;
        sync1        <= 1'b1;
        stable       <= 1'b1;
        held_long    <= 1'b0;
        debounce_cnt <= 32'd0;
        hold_cnt     <= 32'd0;
        short_pulse  <= 1'b0;
        long_step    <= 1'b0;
    end else begin
        sync0       <= button_in;
        sync1       <= sync0;
        short_pulse <= 1'b0;
        long_step   <= 1'b0;

        if (sync1 == stable) begin
            debounce_cnt <= 32'd0;
        end else if (debounce_cnt >= DEBOUNCE_LAST) begin
            debounce_cnt <= 32'd0;
            stable       <= sync1;

            if (stable && !sync1) begin
                held_long  <= 1'b0;
                hold_cnt   <= 32'd0;
            end else if (!stable && sync1) begin
                if (!held_long)
                    short_pulse <= 1'b1;
                held_long <= 1'b0;
                hold_cnt  <= 32'd0;
            end
        end else begin
            debounce_cnt <= debounce_cnt + 32'd1;
        end

        if (!stable && !sync1 && debounce_cnt == 32'd0) begin
            if (!held_long) begin
                if (hold_cnt >= HOLD_LAST) begin
                    held_long  <= 1'b1;
                    hold_cnt   <= 32'd0;
                        long_step  <= 1'b1;
                end else begin
                    hold_cnt <= hold_cnt + 32'd1;
                end
            end else if (hold_cnt >= REPEAT_LAST) begin
                hold_cnt <= 32'd0;
                long_step  <= 1'b1;
            end else begin
                hold_cnt <= hold_cnt + 32'd1;
            end
        end
    end
end

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
