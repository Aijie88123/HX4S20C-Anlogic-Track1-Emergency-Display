`timescale 1ns/1ps

// 上板使用的四层叠加流水线（L0 图像 / L1 转场 / L2 OSD / L3 音频可视化）
//
// 相对上一版的主要变化：
//   1. 底部滚动字幕放大为 32x32 字模（BANNER_SCALE=4），不再用 8x8；
//      因此 scroll_phase 加宽到 12 位，滚动周期按放大后的字条宽度计算。
//   2. 应急红色警戒框改为闪烁：由 blink_on 门控，blink_on 在
//      BLINK_HALF_FRAMES 帧亮 / BLINK_HALF_FRAMES 帧灭之间翻转。
//   3. 运行时间 TIME 的秒计数原来按 25_200_000 帧比较，实际上永远
//      不会进位（25M 帧约等于 4.8 天）。改为按 FRAMES_PER_SECOND 计。
//   4. 重新接入音频可视化（feature_mask[3]）：左侧实时波形 + 右下音频条。
//      旧版本把这一层写死为 0，导致扩展功能 05 在主工程里实际不可见。
module smart_terminal_overlay_pipelined #(
    parameter integer ENABLE_STARTUP_UI = 0,
    parameter integer USE_COLOUR_PALETTE = 0,
    parameter integer NUMBERED_SIX = 0,
    parameter integer ENABLE_PERIOD_OSD = 0,
    parameter integer ENABLE_PLAYBACK_OSD = 0,
    parameter integer EXTERNAL_SPECTRUM = 0,
    parameter integer ENHANCED_AUDIO_VIS = 0,
    parameter integer EXTERNAL_MAP_PIXELS = 0,
    parameter integer REMOTE_MAP = 0,
    parameter integer SCREEN_W = 640,
    parameter integer SCREEN_H = 480,
    parameter integer BANNER_SCALE = 4,
    parameter integer BLINK_HALF_FRAMES = 30,
    parameter integer FRAMES_PER_SECOND = 60,
    // ---- 音频可视化区域 ----
    // 波形框 2026-09-18 第二次上板反馈"再缩小一点"：256x180 -> 192x140。
    // 宽度 192 = 48 个采样点 × POINT_PX(4)。点数不再写死 64，而是由
    // WAVE_W/POINT_PX 推导（见 audio_waveform_overlay 里的 N_POINTS）——
    // 以前 WAVE_W 和采集深度是两处独立常数，改一处就会静默错位。
    // 高度 140 不是随手取的：绘制时静音在中线、满幅偏 63 px，半高必须
    // >= 63 加余量；140 的半高是 70，留 7 px 不蹭边框，也不会削顶。
    // **这两个数就是"框大小"的唯一旋钮**。
    parameter integer WAVE_W = 192,
    parameter integer WAVE_H = 140,
    parameter integer WAVE_X = 40,
    parameter integer WAVE_Y = 130,
    parameter integer POINT_PX = 4,     // 每个波形采样点占的横向像素数
    parameter integer SAMPLE_STEP = 5,  // 每 N 个 I2S 样本取一个点
    // Twelve analysis points at 32-pixel pitch; 20-pixel colored columns.
    // Keep the previous bottom/right margins, clear of the scrolling banner.
    parameter integer BAR_W = 384,
    parameter integer BAR_H = 160,

    // ---- 转场方式（扩展2）----
    // 0 = 淡入淡出（赛题 slide 18 点名的做法，默认）
    // 1 = 水平滑动擦除（旧实现，保留供现场对比演示）
    parameter integer ENABLE_PARTICLES = 0,
    parameter integer ENABLE_PARTICLE_MOTION = 0,
    parameter integer TRANSITION_MODE = 0,
    // 淡出用多少帧走完。**这不是从载图一开始就计的** —— 见下面的 fade_out_start：
    // 淡出被"卡"到预测提交时刻前 FADE_OUT_FRAMES 帧才开始，所以走完的下一刻
    // 正好是切图那一刻，中间没有黑屏空档。
    // 2026-09-28：由 12 帧缩短到 8 帧，减少按键/轮播的可见反应时间。
    parameter [15:0]  FADE_OUT_FRAMES = 16'd8,
    // 淡入帧数。2026-09-28：由 15 帧缩短到 10 帧，同时保留平滑转场。
    parameter [15:0]  FADE_IN_FRAMES  = 16'd10,
    // 第一次载图还没有历史可参考时的预测值。实测 K 卡一次载图约 0.4 s ≈ 24 帧。
    parameter [15:0]  LOAD_EST_FRAMES = 16'd24,
    // 载图超时保护：超过这么多帧还没切图，就把画面放回来
    // （退回旧行为 = 载图期间继续显示上一张，代价是这次切图变成硬切），
    // 免得遇上退化扫描时一直全黑、现场看起来像"死机"。
    //
    // ★ 2026-09-21 上板反馈后重标：原值 **90 帧（1.5 s）** 是"每张都 640x480、
    //   都约 24 帧（0.4 s）"的年代定的 —— 那时余量 3.75 倍。
    //   C2-a 放开分辨率之后 1280x720 一张要 **~1.2 s（72 帧）**，余量只剩 1.25 倍，
    //   板上实测**每次切到 1280 都越界**，于是：
    //       放弃淡出 -> 画面放回来（"先显示上一张"）
    //       -> 之后真提交时缓冲区硬切（"再跳变到 1280 那张"）
    //   这正是上板原话。现在按最长的 1280x720 留足余量：
    //   240 帧 @60Hz = **4 s**，是 1280x720 的 3.3 倍，仍远小于退化扫描的 15 s。
    parameter [15:0]  LOAD_HOLD_MAX = 16'd240,
    // ---- 创新二：动态校园疏散地图 ----
    // 应急进入后 ALARM(2) 保持多少帧再自动推进到 EVACUATION(3)。@60Hz，60 帧 = 1 s。
    // 2026-09-29：由 90 缩到 60 —— 应急界面节奏整体提速（危险区→主线失效→备用线
    // 接管这一段也要跟着变快，否则地图看起来"卡在报警态"）。
    parameter integer ALARM_TO_EVAC_FRAMES = 60,
    // ---- 创新二：疏散图"淡入"用多少帧 ----
    // 疏散图抢占整屏之前先花这么多帧把 alpha 从 0 推到 255（12 帧 @60Hz ≈ 0.2 s）。
    // 不做硬切是因为底图是另一张（SD 卡上的静态疏散图），硬切会像"画面跳了一下"。
    // 置 1 即"立刻不透明"（整层回归 tb 用它，好让颜色判据仍然精确）。
    parameter integer EVAC_FADE_FRAMES = 51,
    // ★ 页 1（卡上的静态疏散平面图）要**连续显示满**这么多帧，动态疏散图才允许接管。
    //   @60Hz，120 帧 = 2 s。
    //   2026-09-29：先缩到 60 帧，上板反馈"两张报警图没看全就上疏散图了"，
    //   于是**恢复 120 帧**，与 sd_card_bmp 的 EMER_DWELL_MS=2000 对齐：
    //   火灾报警图 2 s → 静态疏散图 2 s → 之后才淡入动态疏散图。
    //   为什么需要：以前是“页号一变 1 就 armed”，动态图 0.2 s（EVAC_FADE_FRAMES）
    //   就把静态疏散图盖住了 —— 上板反馈“静态疏散图根本没播完”。
    //   ⚠️ 要跟 sd_card_bmp 的 EMER_DWELL_MS（警报模式页面停留，现在 2 s）对齐：
    //      对不齐要么盖早了（没播完），要么页 0 已经轮回来、底图换了色。
    parameter integer EVAC_PAGE1_HOLD_FRAMES = 2 * FRAMES_PER_SECOND
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        i_hs,
    input  wire        i_vs,
    input  wire        i_de,
    input  wire [23:0] i_rgb,
    input  wire        emergency,
    input wire startup_loading,input wire [8:0] startup_progress,
    // ---- 创新二：动态校园疏散地图 ----
    // 事件类型：0 火灾 / 1 地震 / 2 实验室事故 / 3 演练。
    // 来自 hw_top 的 emergency_event 寄存器（S4 长按循环）。慢变信号，不需要握手。
    input  wire [1:0]  emergency_event,
    input wire map_pixels_valid,map_pixels_stale,
    input wire map_live,input wire [187:0] map_scene,output wire map_frame_tick,
    // 载图进行中（来自 sd_card_bmp 的 write_buf_idx != disp_buf_idx）。
    // 淡出由它触发：它在"开始载图"那一拍拉高，在"提交新图并切换显示缓冲区"
    // 那一拍拉低 —— 正好把整段载图时间夹在中间，所以不需要任何跨时钟握手。
    input  wire        load_in_flight,
    // ★ 载图"快读完了"（已在 hw_top 里从 sd_card_clk 同步到 video_clk）。
    //   本模块用它触发**淡出**，取代原来"用上一张的载图时长预测这一张"的
    //   做法 —— 后者在 C2-a 放开分辨率之后两个方向都会坏（大图提前变黑、
    //   小图亮着硬切）。见 bmp_read.v 的 NEARLY_DONE_SECTORS。
    input  wire        load_nearly_done,
    // 转场图案选择（板上 4 个拨码开关的前 3 个，见 transition_fx.v 的图案表）
    input  wire [2:0]  fx_sel,
    input wire [56:0] particle_motion,input wire particle_ready,input wire [7:0] particle_code,output wire [12:0] particle_address,
    // 转场总开关（拨码开关第 4 个）。0 = 开特效（默认），1 = 关掉变硬切，
    // 现场用来做"有特效 / 无特效"的对照演示。
    input  wire        fx_off,
    input  wire [15:0] audio_mag,
    input  wire        audio_sample_valid,
    input  wire [23:0] audio_sample,
    input wire external_band_valid,external_spectrum_live,
    input wire [19:0] external_band_data,
    input  wire [2:0]  page_index,        // 最多 5 张图，需要 3 bit
    input  wire [2:0]  brightness,
    input  wire [2:0]  contrast,
    input wire [1:0] interval_selection,
    input wire playback_running,
    input  wire [1:0]  palette_bank,
    input  wire        palette_write_enable,
    input  wire [9:0]  palette_write_address,
    input  wire [7:0]  palette_write_value,
    input  wire [3:0]  feature_mask,
    // 当前显示中的那张图的**源分辨率**（BMP 头里读出来的原始宽高）。
    // ⚠️ 这两个信号来自 sd_card_clk 域，**必须由上层用 toggle 握手同步进来**
    //    （见 smart_terminal_hw_top.v 的 res_tgl_sync）—— 直接接过去会在
    //    跨域处编出又长又抖的路径。本模块只负责把它格式化成 OSD 用的 ASCII 串。
    input  wire [15:0] src_w,
    input  wire [15:0] src_h,

    output reg         o_hs,
    output reg         o_vs,
    output reg         o_de,
    output reg  [23:0] o_rgb,
    output reg  [11:0] o_x,
    output reg  [11:0] o_y
);

    reg        de_d;
    reg        vs_d;
    reg [11:0] x;
    reg [11:0] y;
    reg [2:0]  page_sync0;
    reg [2:0]  page_sync1;
    reg [2:0]  page_last;
    reg [11:0] scroll_phase;
    reg [6:0]  elapsed_seconds;
    reg [6:0]  second_divider;
    reg [15:0] blink_divider;
    reg        blink_on;
    reg        transition_active;
    reg [11:0] transition_x;
    reg        frame_tick;
    assign map_frame_tick=frame_tick;
    // 淡入淡出：0 = 原画，255 = 整屏全黑。见下面 frame_tick 里的状态机。
    reg        load_sync0;
    reg        load_sync1;
    reg        load_sync1_d;
    // 载图"快读完了"的两拍同步（hw_top 已经同步过一次，这里再打一拍与
    // load_sync 家族对齐；慢变电平，多一拍无害）。
    reg        nearly_sync0;
    reg        nearly_sync1;
    reg [7:0]  fade_alpha;
    reg [15:0] load_frames;      // 本次载图已经持续了多少帧
    reg [15:0] last_load_frames; // 上一次载图总共用了多少帧 —— 用来预测下一次的提交时刻
    // 转场图案（拨码开关是机械触点，两拍同步进 video_clk）
    reg [2:0]  fx_sync0;
    reg [2:0]  fx_sync1;
    reg        fxo_sync0;
    reg        fxo_sync1;
    reg [7:0]  s1_fx_alpha;      // 本像素最终的转场 alpha，与 s1_rgb 同拍
    reg [71:0] res_str;          // OSD 上的分辨率串：9 个 ASCII 字符

    // ------------------------------------------------------------------
    // 分辨率串格式化（给 OSD 右上角信息栏用）
    //
    // 为什么要写成一个小状态机、而不是一行组合逻辑：
    //   "16 bit -> 十进制 4 位" 要么挂除法器（TD 会起 DSP / 长进位链），
    //   要么挂一长串 shift-add。它跨进 video_clk 之后还要串进 font_row 的
    //   组合查找 —— 本工程在 video_clk 上已经被时序门拦下过好几次。
    //   而这个值**每张图才变一次**（秒级），完全不值得为它开一条长路径。
    //   ⇒ 每拍只做**一次** /10，11 拍出结果。代价是切图后 OSD 上的分辨率
    //     最多晚 ~11 拍（≈150 ns @74.25 MHz）更新，肉眼不可见。
    //
    // 串的布局（9 个字符，右对齐，去掉前导零）：
    //      [71:64] 最左 ... [7:0] 最右
    //      例："  640X480" / " 1280X720"
    // ------------------------------------------------------------------
    localparam [3:0] RF_IDLE = 4'd0;
    localparam [3:0] RF_W0   = 4'd1;    // 1..4 = 拆 W 的个/十/百/千
    localparam [3:0] RF_HLD  = 4'd5;    // 换 H，重新起除数与位数
    localparam [3:0] RF_H0   = 4'd6;    // 6..9 = 拆 H 的个/十/百/千
    localparam [3:0] RF_OUT  = 4'd10;   // 拼串

    reg [3:0]  rf_ph;
    reg [15:0] rf_dv;
    reg [15:0] rf_w_q, rf_h_q;
    reg [31:0] rf_dw, rf_dh;      // 拆出来的 4 个 ASCII 数字，[31:24] = 最高位
    reg [3:0]  rf_nw, rf_nh;      // 有效十进制位数 1..4

    // 只做**一次** /10：不级联，深度只有一条常数乘加
    wire [15:0] rf_q = rf_dv / 16'd10;
    wire [3:0]  rf_d = rf_dv % 16'd10;

    function [3:0] dec_len;
        input [15:0] v;
        begin
            dec_len = (v >= 16'd1000) ? 4'd4 :
                      (v >= 16'd100)  ? 4'd3 :
                      (v >= 16'd10)   ? 4'd2 : 4'd1;
        end
    endfunction

    // 从 "4 个 ASCII 数字（[31:24] 最高位）+ 有效位数" 里取第 rel 位（0 = 最左有效位）
    function [7:0] pick4;
        input [31:0] a;
        input [3:0]  len;
        input [3:0]  rel;
        reg [3:0] p;
        begin
            p = len - 4'd1 - rel;
            case (p)
                4'd0:    pick4 = a[7:0];
                4'd1:    pick4 = a[15:8];
                4'd2:    pick4 = a[23:16];
                default: pick4 = a[31:24];
            endcase
        end
    endfunction

    // 把两组数字拼成 9 字符的右对齐串（纯 mux，没有除法）
    function [71:0] build_res;
        input [31:0] wa;
        input [3:0]  nw;
        input [31:0] ha;
        input [3:0]  nh;
        reg [3:0] wl, hl, start, xpos;
        reg [3:0] pp;
        reg [7:0] cc;
        reg [71:0] t;
        integer i;
        begin
            wl    = nw;
            hl    = nh;
            start = 4'd9 - (wl + 4'd1 + hl);   // 3..9 的串长 -> 左补空格的位置
            xpos  = start + wl;                // 'X' 落在第几格
            t = 72'd0;
            for (i = 0; i < 9; i = i + 1) begin
                pp = i[3:0];
                if (pp < start)
                    cc = 8'h20;
                else if (pp < xpos)
                    cc = pick4(wa, wl, pp - start);
                else if (pp == xpos)
                    cc = "X";
                else
                    cc = pick4(ha, hl, pp - xpos - 4'd1);
                t = {t[63:0], cc};             // 先填的落在最左
            end
            build_res = t;
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rf_ph  <= RF_IDLE;
            rf_dv  <= 16'd0;
            rf_w_q <= 16'd0;
            rf_h_q <= 16'd0;
            rf_dw  <= 32'd0;
            rf_dh  <= 32'd0;
            rf_nw  <= 4'd0;
            rf_nh  <= 4'd0;
            res_str <= 72'd0;
        end else begin
            case (rf_ph)
                RF_IDLE: begin
                    // 只要分辨率变了就重算一次（上电时 rf_nw == 0 也强制算一次）
                    if ((src_w != rf_w_q) || (src_h != rf_h_q) || (rf_nw == 4'd0)) begin
                        rf_w_q <= src_w;
                        rf_h_q <= src_h;
                        rf_dv  <= src_w;
                        rf_nw  <= dec_len(src_w);
                        rf_dw  <= 32'd0;
                        rf_ph  <= RF_W0;
                    end
                end
                // W 的 4 位：从个位开始，每拍往高位推一格
                4'd1, 4'd2, 4'd3, 4'd4: begin
                    rf_dw <= {8'h30 + {4'b0, rf_d}, rf_dw[31:8]};
                    rf_dv <= rf_q;
                    rf_ph <= (rf_ph == 4'd4) ? RF_HLD : (rf_ph + 4'd1);
                end
                RF_HLD: begin
                    rf_dv <= rf_h_q;
                    rf_nh <= dec_len(rf_h_q);
                    rf_dh <= 32'd0;
                    rf_ph <= RF_H0;
                end
                4'd6, 4'd7, 4'd8, 4'd9: begin
                    rf_dh <= {8'h30 + {4'b0, rf_d}, rf_dh[31:8]};
                    rf_dv <= rf_q;
                    rf_ph <= (rf_ph == 4'd9) ? RF_OUT : (rf_ph + 4'd1);
                end
                default: begin                     // RF_OUT
                    res_str <= build_res(rf_dw, rf_nw, rf_dh, rf_nh);
                    rf_ph   <= RF_IDLE;
                end
            endcase
        end
    end

    wire [23:0] enhanced_base;
    wire [23:0] processed_base;
    wire [23:0] transition_mixed;
    wire [23:0] text_mixed;
    wire [23:0] bars_mixed;
    wire [23:0] wave_mixed;

    wire [23:0] text_rgb;
    wire [7:0]  text_alpha;
    wire [23:0] title_rgb;
    wire [7:0]  title_alpha;
    wire [23:0] waveform_rgb;
    wire [7:0]  waveform_alpha;
    wire [23:0] audio_bars_rgb;
    wire [7:0]  audio_bars_alpha;
    wire [7:0]  active_wave_alpha;
    wire [7:0]  active_bars_alpha;
    // ---- 创新二：动态校园疏散地图（L4）----
    // emergency_map_top 输出的是“打满 5 拍、与 s6_rgb 同像素”的窗口像素，本层只负责把它寄一拍。
    wire [23:0] evac_map_rgb;
    wire [7:0]  evac_map_alpha;
    reg  [23:0] s6_evac_rgb;
    reg  [7:0]  s6_evac_alpha;
    reg  [7:0]  s6_evac_fade;      // 与 s6_evac_rgb 同拍的本帧淡入 alpha
    // 应急状态机：0 正常 / 2 报警（危险区先出现）/ 3 疏散（主线失效、备用线接管）
    reg emergency_r;
    reg  [2:0]  emergency_state_r;
    reg  [15:0] emergency_alarm_cnt;
    reg [1:0] emergency_event_frame;
    localparam [15:0] ALARM_TO_EVAC_LIM = ALARM_TO_EVAC_FRAMES - 1;

    // ---- 创新二：疏散图"什么时候才允许出现" ----
    // evac_armed：按下应急键之后，还要**等火灾报警图播完**才置起。
    // 判据用 sd_card_bmp 的页面号（page_index -> page_sync1）：
    //   警报模式下只在前两张紧急图之间轮播（0 = 火灾报警 / 1 = 疏散图），
    //   按下 K4 的那一拍它会立刻抢载 0 号图，停留 EMER_DWELL_MS（2 s）后轮到 1 号图。
    //   所以"page_sync1 变成 1"就精确等于"火灾报警图播完了" ——
    //   和载图时长、图片分辨率、卡上图片大小都无关，不用去猜帧数。
    //   1 号图只可能出现在警报模式（普通模式轮播的是 2/3/4），不会误触发。
    // ⚠️ 这个兜底要**大于**“页 1 最晚到位时刻 + EVAC_PAGE1_HOLD_FRAMES”：
    //   按应急键 -> 若正有载图在飞还要等它写完（~1.3 s，载图不可中途取消）
    //   + 页 0 载图（0.4 s）+ 页 0 停留（2 s）+ 页 1 载图（0.4 s）+ 页 1 停留（2 s）
    //   ≈ 6.1 s，留一倍余量取 10 s。
    //   卡上图片不足 2 张时 sd_card_bmp 根本不轮播（永远轮不到页 1），
    //   10 s 后照样把疏散图放出来，避免这块功能彻底哑掉。
    localparam [15:0] EVAC_ARM_TIMEOUT_LIM = 10 * FRAMES_PER_SECOND - 1;
    // 页 1 停留的帧数判据（含“本帧边界这一帧”的增量，见下面的 page1_hold_nxt）
    // ⚠️ 8 位：EG4S20 的 mslices 余量已经只剩 1%，能省一位是一位；
    //    EVAC_PAGE1_HOLD_FRAMES 因此必须 ≤ 255（默认 120 = 2 s）。
    localparam [7:0]  EVAC_PAGE1_HOLD_LIM = EVAC_PAGE1_HOLD_FRAMES;
    localparam [7:0]  EVAC_FADE_STEP = (255 + EVAC_FADE_FRAMES - 1) / EVAC_FADE_FRAMES;
    reg        evac_armed;
    reg [15:0] evac_arm_cnt;
    reg [7:0]  evac_fade;
    // 页 1（静态疏散图）到了没有 / 已经连续显示多少帧
    reg        evac_seen_page1;
    reg [7:0]  page1_hold_cnt;


    reg        s1_hs, s1_vs, s1_de;
    reg        s2_hs, s2_vs, s2_de;
    reg        s3_hs, s3_vs, s3_de;
    reg        s4_hs, s4_vs, s4_de;
    reg        s5_hs, s5_vs, s5_de;
    reg        s6_hs, s6_vs, s6_de;
    reg [11:0] s1_x, s1_y;
    reg [11:0] s2_x, s2_y;
    reg [11:0] s3_x, s3_y;
    reg [11:0] s4_x, s4_y;
    reg [11:0] s5_x, s5_y;
    reg [11:0] s6_x, s6_y;
    wire [23:0] s1_rgb;
    reg [23:0] s2_rgb, s3_rgb, s4_rgb, s5_rgb, s6_rgb;
    reg [23:0] s4_text_rgb;
    reg [7:0]  s4_text_alpha;
    reg [23:0] s4_bars_rgb;
    reg [7:0]  s4_bars_alpha;
    reg [23:0] s4_wave_rgb;
    reg [7:0]  s4_wave_alpha;
    reg [23:0] s5_bars_rgb;
    reg [7:0]  s5_bars_alpha;
    reg [23:0] s5_wave_rgb;
    reg [7:0]  s5_wave_alpha;
    reg [23:0] s6_wave_rgb;
    reg [7:0]  s6_wave_alpha;
    reg        s1_trans_black;
    reg        s1_trans_edge;

    localparam integer BANNER_CHARS = 15;
    localparam integer BANNER_CELL  = 8 * BANNER_SCALE;
    localparam integer BANNER_W     = BANNER_CHARS * BANNER_CELL;
    localparam integer SCROLL_MAX   = SCREEN_W + BANNER_W - 1;

    // 每帧步进量由帧数反推，参数里只暴露"多少帧走完"，免得现场调两个魔法数字。
    localparam [7:0] FADE_OUT_STEP = (255 + FADE_OUT_FRAMES - 1) / FADE_OUT_FRAMES;
    localparam [7:0] FADE_IN_STEP  = (255 + FADE_IN_FRAMES  - 1) / FADE_IN_FRAMES;
    // ------------------------------------------------------------------
    // ★ 淡出起点 —— 2026-09-21 上板反馈后**换掉了判据**
    //
    // 旧做法：预测本次提交时刻（= 上一次载图用了多少帧），往前推 FADE_OUT_FRAMES
    //   帧开始变暗。在"每张都 640x480、都约 24 帧"的年代这是对的。
    //   **但 C2-a 放开分辨率之后，同一张卡上载图时长差 3 倍**
    //   （640x480≈24 帧 / 800x600≈37 / **1280x720≈72**），拿上一张预测这一张，
    //   两个方向都会坏：
    //       图变大 -> 淡出起得太早 -> 提前全黑、白等几十帧（上板："黑屏时间有点长"）
    //       图变小 -> 淡出还没开始就提交了 -> 亮着硬切（上板："转场不流畅"）
    //
    // 新做法：由**载图进度**给起点 —— bmp_read 的 load_nearly_done，
    //   判据是"离读完还差 NEARLY_DONE_SECTORS 个扇区"，而那个常数
    //   （900）正是**淡出 12 帧所需的字节数**（推导见 bmp_read.v）。
    //   ⇒ 淡出走完的下一刻 ≈ 提交时刻，**与图有多大无关**。
    //
    // 仍留一条**兜底**：万一 load_nearly_done 因为别的缘故一直不来，
    //   就在"放弃阈值前 FADE_OUT_FRAMES 帧"强启淡出，至少不会亮着硬切。
    //
    // 注：last_load_frames / fade_out_start 保留在下面（历史记录 + 兜底不用它），
    //     不再参与触发。留着是为了让这段来龙去脉可读；综合器会把没用的剪掉。
    // ------------------------------------------------------------------
    localparam [15:0] FADE_OUT_BACKSTOP = LOAD_HOLD_MAX - FADE_OUT_FRAMES;
    wire [15:0] fade_out_start = (last_load_frames > FADE_OUT_FRAMES) ?
                                 (last_load_frames - FADE_OUT_FRAMES) : 16'd0;

    // 转场判断提前一拍：用当前像素坐标 x 比较，随 s1_x 一起打拍。
    // 这样 s1 -> s2 这一段就只剩"选层 + alpha 混合"，
    // 把 12 位比较器从时间最紧的那一级里挪走
    // （移到之前 setup 差 -0.015ns 的那条路径上就是这一级）。
    wire startup_skip_fade;
    wire trans_black_c = feature_mask[1] && !startup_skip_fade &&
                         transition_active && (x < transition_x);
    wire trans_edge_c  = feature_mask[1] && !startup_skip_fade &&
                         transition_active &&
                         (x >= transition_x) &&
                         (x < (transition_x + 12'd12));

    wire transition_black = s1_trans_black;
    wire transition_edge  = s1_trans_edge;

    // ---- 转场层（扩展2）----
    // 两种转场共用同一条 alpha 混合通路，只是"铺什么颜色的幕布、alpha 从哪来"不同。
    //   TRANSITION_MODE=1：左侧黑幕(235) + 12px 青色亮线(220) 推进 ← 旧实现
    //   TRANSITION_MODE=0：整屏黑幕，alpha = fade_alpha，由下面的状态机驱动
    // TRANSITION_MODE 是常量，综合时这个 mux 会折叠掉，没选中的那路逻辑被剪除。
    wire [7:0]  wipe_alpha = transition_edge ? 8'd220 :
                             (transition_black ? 8'd235 : 8'd0);
    wire [23:0] wipe_rgb   = transition_edge ? 24'h00D8FF : 24'h000000;

    // ---- 转场图案相位（扩展2，A 类：单缓冲图案化淡入淡出）----
    // 每个像素按自己的相位错开变暗/变亮，屏幕上就出现百叶窗、棋盘、菱形扩散等效果。
    wire [7:0] fx_phase_c;

    transition_fx #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H)
    ) u_transition_fx (
        .x      (x),
        .y      (y),
        .fx_sel (fx_sync1),
        .phase  (fx_phase_c)
    );

    // local = clamp(alpha_wide - phase, 0, 255)
    // alpha_wide = 1.5 倍 fade_alpha，保证 fade_alpha=255（切图那一拍）时
    // 相位取满 128 的区域 local 仍有 254 —— 全黑，缓冲区切换不可见。
    // 增益 1.5（= x + x/2）：均匀图案（fx=0）时保持原样，图案化时把范围撑到 0..382
    // Preserve the original switch synchronizers; removed codes use uniform alpha.
    // Prefetch the atlas one pixel ahead of the existing x/y register.
    // Atlas sampling is 8x enlargement with seamless 1024x512 tiling.
    wire frame_boundary=!i_vs && vs_d;
    // Present either a whole loading frame or a whole media frame. The
    // qualifier may change during VS; only retire the loading UI at VS end.
    reg startup_loading_frame;
    reg startup_fade_inhibit;
    always @(posedge clk)begin
      if(rst)begin
        startup_loading_frame<=ENABLE_STARTUP_UI!=0;
        startup_fade_inhibit<=ENABLE_STARTUP_UI!=0;
      end else begin
        if(ENABLE_STARTUP_UI && startup_loading_frame)
          startup_fade_inhibit<=1;
        else if(!load_sync1 || !nearly_sync1)
          startup_fade_inhibit<=0;
        if(frame_boundary)startup_loading_frame<=ENABLE_STARTUP_UI && startup_loading;
      end
    end
    wire startup_wait=ENABLE_STARTUP_UI && startup_loading_frame;
    assign startup_skip_fade=ENABLE_STARTUP_UI && (startup_loading_frame || startup_fade_inhibit);

    wire [11:0] particle_x_next=frame_boundary?12'd0:i_de?(!de_d?12'd1:x+12'd1):de_d?12'd0:x;
    wire [11:0] particle_y_next=frame_boundary?12'd0:(!i_de && de_d)?y+12'd1:y;
    reg [56:0] motion_frame;
    always @(posedge clk or posedge rst)
      if(rst)motion_frame<=0;else if(frame_boundary)motion_frame<=particle_motion;
    wire [5:0] row_offset=motion_frame[9+particle_y_next[9:7]*6 +:6];
    wire [6:0] moving_x=particle_x_next>=640?particle_x_next[9:3]-row_offset:particle_x_next[9:3]+row_offset;
    wire [5:0] moving_y=particle_y_next[8:3]+motion_frame[8:3];
    assign particle_address=ENABLE_PARTICLE_MOTION?{moving_y,moving_x}:{particle_y_next[8:3],particle_x_next[9:3]};
    reg particle_armed;
    always @(posedge clk)if(rst)particle_armed<=0;
      else if(frame_boundary && fade_alpha==0)particle_armed<=ENABLE_PARTICLES && particle_ready;
    wire particle_active=ENABLE_PARTICLES && particle_armed && fx_sync1==6 && !fxo_sync1;
    // Ordinary modes 0/4/5/7 were removed. Keep their switch codes as hard cuts.
    // Particle data not yet ready also uses a hard cut, never a uniform fallback.
    wire ordinary_fx_active=particle_active ||
        (!fxo_sync1 && !fx_sync1[2] && (|fx_sync1[1:0]));
    // The dedicated emergency-photo/map entry fade is intentionally retained.
    wire uniform_fade=emergency_r && !particle_active;
    wire [8:0] alpha_wide = {1'b0, fade_alpha} +
                            (uniform_fade ? 9'd0 : {2'b0, fade_alpha[7:1]});

    // alpha_wide is 0..382 and phase is 0..255. A signed 10-bit
    // difference covers -255..382; its sign and bit 8 give both clamp flags.
    // This replaces compare -> subtract/mux -> compare, with no added stage.
    wire [7:0] selected_phase=particle_active?{1'b0,particle_code[7:3],2'b00}:fx_phase_c;
    wire signed [9:0] fx_delta=$signed({1'b0,alpha_wide})-$signed({2'b0,selected_phase});
    wire [4:0] particle_age=fade_alpha[7:3];
    wire [4:0] particle_distance=particle_age>particle_code[7:3]?particle_age-particle_code[7:3]:particle_code[7:3]-particle_age;
    wire particle_hot=particle_active && fade_alpha!=0 && fade_alpha!=255 && particle_distance<4 && particle_code[2:0]!=0;
    wire [7:0] particle_blue={particle_code[2:0],5'b11111};
    wire [7:0] particle_green={1'b0,particle_code[2:0],4'b1111};
    reg [23:0] s1_particle_rgb;
    always @(posedge clk)if(rst)s1_particle_rgb<=0;
      else s1_particle_rgb<=particle_hot?{8'd0,particle_green,particle_blue}:24'd0;
    wire [8:0] fx_sub=fx_delta[9]?9'd0:fx_delta[8:0];
    wire [7:0] fx_local=fx_delta[9]?8'd0:(fx_delta[8]?8'd255:fx_delta[7:0]);
    wire [7:0]  transition_alpha = (TRANSITION_MODE == 1) ? wipe_alpha : s1_fx_alpha;
    wire [23:0] transition_rgb   = (TRANSITION_MODE == 1) ? wipe_rgb : s1_particle_rgb;

    // 音频可视化：由 feature_mask[3] 打开
    assign active_bars_alpha  = (feature_mask[3] && !emergency_r) ? audio_bars_alpha : 8'd0;
    assign active_wave_alpha  = (feature_mask[3] && !emergency_r) ? waveform_alpha : 8'd0;
    reg [1:0] map_stale_sync;
    always @(posedge clk)if(rst)map_stale_sync<=0;else map_stale_sync<={map_stale_sync[0],map_pixels_stale};
    wire [23:0] frame_input_rgb=EXTERNAL_MAP_PIXELS && map_pixels_valid && map_stale_sync[1] && x<64 && y>=704?24'hB34D31:i_rgb;
    generate if(USE_COLOUR_PALETTE)begin: colour_palette
      video_palette_lookup u_lookup(.clk(clk),.rst(rst),.enable(feature_mask[2]),
        .in_rgb(frame_input_rgb),.bank(palette_bank),.write_enable(palette_write_enable),
        .write_address(palette_write_address),.write_value(palette_write_value),.out_rgb(s1_rgb));
    end else begin: colour_compatibility
      assign processed_base=feature_mask[2]?enhanced_base:frame_input_rgb;
      video_enhance u_video_enhance (
        .in_rgb     (frame_input_rgb),
        .brightness (brightness),
        .contrast   (contrast),
        .out_rgb    (enhanced_base)
      );
      reg [23:0] registered_base;
      always @(posedge clk)if(rst)registered_base<=0;else registered_base<=processed_base;
      assign s1_rgb=registered_base;
    end endgenerate

    // Use the existing otherwise-empty s2 -> s3 stage for the addition and
    // /255 correction. DSP products register at s2, corrected RGB at s3.
    // Total video latency, coordinates, OSD and audio alignment are unchanged.
    alpha_blend_products u_transition_blend (
        .clk       (clk),
        .rst       (rst),
        .base_rgb  (s1_rgb),
        .layer_rgb (transition_rgb),
        .alpha     (transition_alpha),
        .out_rgb   (transition_mixed)
    );

    // ------------------------------------------------------------------
    // ★ emergency 的寄存器边界 —— **这一级是时序门拦下来的，不是风格问题**
    //
    // emergency 是 hw_top 里的一个 video_clk 寄存器，fanout 到 sd_card_bmp /
    // hdmi / led 等多处。如果在下面把它**直接组合**进 text_overlay_8x8 的整片
    // 译码（警戒框 / 字模表 / 底条三路 mux）再送进 alpha_blend 的乘法器，
    // 综合器会把「源头那个高扇出寄存器 -> 一整片译码 -> 乘法器输入寄存器」
    // 挤成同一条路径。
    //
    // 实测（bilin11 首次构建，project/timing_gate.sh 逐域判）：
    //     emergency_mode_reg -> u_smart_terminal_overlay/u_text_blend/mult1_syn_1.b[16]
    //     13 级（LUT5=9 ADDER=2 MULT18=1 LUT4=1）、13.865 ns
    //     其中 7.714 ns（**56%**）是走线；超 13.333 ns 预算 -0.984 ns、15 个端点
    //     —— 而**本次真正改动的 sd_card_clk 域是 SWNS=+0.197 / 0 违例**。
    //    同一份源**重跑一次，读数逐位复现** ⇒ TD 在这里是确定性的，
    //    所以"重跑碰运气"这条路**已证伪**（它对 ext_mem_clk 有效，这次不适用）。
    //    ⇒ 逻辑深度没变、是布局被上游扰动推过线的典型形态。
    //
    // 加这一级**功能上零代价**：emergency 只在 S4 按键时翻转，晚一拍生效无感。
    // 换来的是综合器手里一个**就近布局、低扇出**的起点，那段走线不再是关键路径。
    // 与下面 s1_fx_alpha 那一级同族 —— "让 alpha_blend 的 alpha 输入仍然是一个
    // 寄存器，那级乘法器余量本来就不多"。
    //
    // ⚠️ 声明必须**在下面例化之前**：写在后面会变成一条隐式线网（同名不同网），
    //    模式位根本不生效，而综合未必报错 —— 同一个坑在 tb/fake_sd_card_fat32.v
    //    的 empty_mode 上踩过一次。
    // ------------------------------------------------------------------

    reg normal_return_fast;
    // Fast entry applies only while the emergency sequence is being brought
    // up (before the dynamic evacuation map is armed).  Once armed, the
    // existing emergency-map timing is unchanged.
    wire emergency_picture_fade=(page_sync1==3'd1) ||
        (page_sync1==3'd0 && load_sync1 && nearly_sync1);
    wire emergency_entry_fast=emergency_r && !evac_armed && !emergency_picture_fade;
    wire mode_switch_fast = emergency_entry_fast || normal_return_fast;

    // ---- 创新二：疏散图"什么时候才允许出现"（组合判据，放在 emergency_r 之后）----
    // 时序（页号来自 sd_card_bmp，两级同步后 = page_sync1）：
    //   按应急键 -> 抢载页 0（火灾报警图）-> 停留 EMER_DWELL_MS
    //            -> 载页 1（静态疏散平面图）-> 停留 EVAC_PAGE1_HOLD_FRAMES
    //            -> 动态疏散图淡入接管。
    // ★ 关键：不再是"页号一变 1 就 armed"。页 1 要**连续站满**
    //   EVAC_PAGE1_HOLD_FRAMES 帧才放行动态图，否则静态疏散图刚上屏就被盖住
    //   （上板反馈"静态疏散图没播完"）。
    // page1_hold_nxt 把"本帧边界这一帧"也算进去，于是 LIM=1 时行为与旧版逐帧一致
    // （回归台 tb_overlay_evac 仍可按帧号断言）。
    wire [7:0]  page1_hold_nxt = (page_sync1 == 3'd1)
                               ? ((page1_hold_cnt == EVAC_PAGE1_HOLD_LIM) ? page1_hold_cnt
                                                                         : (page1_hold_cnt + 8'd1))
                               : 8'd0;
    wire evac_seen_page1_nxt = evac_seen_page1 | (page_sync1 == 3'd1);
    wire evac_page1_ready    = (page_sync1 == 3'd1) && evac_seen_page1_nxt && (page1_hold_nxt >= EVAC_PAGE1_HOLD_LIM);
    // "本帧边界就该就位"：供状态机与淡入在同一拍使用，避免多出一帧"只出底板"。
    wire evac_arm_now = emergency_r && !evac_armed &&
                        (evac_page1_ready || (evac_arm_cnt >= EVAC_ARM_TIMEOUT_LIM));
    wire evac_active = emergency_r & evac_armed; // complete scene also works after TF fallback timeout

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            emergency_r <= 1'b0;
            normal_return_fast <= 1'b0;
        end else begin
            emergency_r <= emergency;
            if(emergency) normal_return_fast <= 1'b0;
            else if(emergency_r) normal_return_fast <= 1'b1;
            else if(frame_tick && page_sync1 >= 3'd2)
                normal_return_fast <= 1'b0;
        end
    end

    // Slow playback state crosses into video separately from the pixel path.
    reg [1:0] playback_sync;
    reg playback_frame;
    always @(posedge clk or posedge rst)
     if(rst)begin playback_sync<=2'b11;playback_frame<=1;end
     else begin
      playback_sync<={playback_sync[0],playback_running};
      if(frame_tick)playback_frame<=playback_sync[1];
     end
    wire [2:0] osd_page;
    generate if(NUMBERED_SIX)begin: numbered_osd
     reg [2:0] numbered_page;
     always @(posedge clk)if(rst)numbered_page<=0;else case(page_sync1)
      0:numbered_page<=4;1:numbered_page<=5;2:numbered_page<=0;3:numbered_page<=1;4:numbered_page<=2;default:numbered_page<=3;
     endcase
     assign osd_page=numbered_page;
    end else begin assign osd_page=page_sync1;end endgenerate
    text_overlay_8x8 #(
        .ENABLE_STARTUP_UI(ENABLE_STARTUP_UI),
        .USE_BANNER_ROM (1),
        .ENABLE_PERIOD_OSD (ENABLE_PERIOD_OSD),
        .ENABLE_PLAYBACK_OSD (ENABLE_PLAYBACK_OSD),
        .SCREEN_W     (SCREEN_W),
        .SCREEN_H     (SCREEN_H),
        .BANNER_SCALE (BANNER_SCALE)
    ) u_text_overlay (
        .clk             (clk),
        .rst             (rst),
        .emergency       (emergency_r && !evac_armed),
        .startup_loading(startup_wait),.startup_progress(startup_progress),
        .blink_on        (blink_on),
        .x               (s3_x),
        .y               (s3_y),
        // 信息栏那一块单独在 s2 坐标上译码、打一拍，正好在 s3 对齐 ——
        // 见 text_overlay_8x8.v 里 status_hit 的注释（18 字符加宽后
        // video_clk 域吃掉了 0.15 ns，需要把这段锥切出去）。
        .x_pre           (s2_x),
        .y_pre           (s2_y),
        .page_index      (osd_page),
        .brightness      (brightness),
        .contrast        (contrast),
        .interval_selection(interval_selection),
        .playback_running(playback_frame),
        .elapsed_seconds (elapsed_seconds),
        .scroll_phase    (scroll_phase),
        .scroll_phase_pre(rst ? 12'd0 : ((!i_vs && vs_d) ?
            ((scroll_phase>=SCROLL_MAX)?12'd0:scroll_phase+12'd1) : scroll_phase)),
        .feature_mask    (emergency_r ? 4'd0 : feature_mask),
        .res_str         (res_str),
        .text_rgb        (text_rgb),
        .text_alpha      (text_alpha)
    );

    chinese_title_overlay_pipelined #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H),
        .REGISTER_OUTPUT (1)
    ) u_chinese_title_overlay (
        .clk         (clk),
        .rst         (rst),
        .x           (s1_x),
        .y           (s1_y),
        .title_rgb   (title_rgb),
        .title_alpha (title_alpha)
    );

    // ---- Twelve points: eight normal notes and four higher-frequency points.
    // 放在叠加层内部，这样 hw_top 的接口不用动。
    wire        ff_band_valid;
    wire [4:0]  ff_band_idx;
    wire [15:0] ff_band_mag;

    // P_WIN=64 + Hamming 窗：见 audio_fft.v 里 win_coef 上方的推导。
    // 原先是 256 且不加窗，导致音阶 8 个音的峰值柱高在 24 dB 范围里乱跳。
    generate if(EXTERNAL_SPECTRUM)begin:remote_analysis
        assign ff_band_valid=external_band_valid && external_spectrum_live && feature_mask[3];
        assign ff_band_idx={1'b0,external_band_data[19:16]};
        assign ff_band_mag=external_band_data[15:0];
    end else begin:local_analysis
    audio_fft #(
        .P_BINS (12),
        .P_WIN  (64)
    ) u_audio_fft (
        .clk           (clk),
        .rst           (rst || !feature_mask[3]),
        .I_audio       (audio_sample),
        .I_audio_valid (feature_mask[3] && audio_sample_valid),
        .O_band_valid  (ff_band_valid),
        .O_band        (ff_band_idx),
        .O_mag         (ff_band_mag)
    );
    end endgenerate

    wire [23:0] legacy_bars_rgb,legacy_wave_rgb,precise_bars_rgb,precise_wave_rgb;
    wire [7:0] legacy_bars_alpha,legacy_wave_alpha,precise_bars_alpha,precise_wave_alpha;
    assign audio_bars_rgb=ENHANCED_AUDIO_VIS?precise_bars_rgb:legacy_bars_rgb;
    assign audio_bars_alpha=ENHANCED_AUDIO_VIS?precise_bars_alpha:legacy_bars_alpha;
    assign waveform_rgb=ENHANCED_AUDIO_VIS?precise_wave_rgb:legacy_wave_rgb;
    assign waveform_alpha=ENHANCED_AUDIO_VIS?precise_wave_alpha:legacy_wave_alpha;
    generate if(ENHANCED_AUDIO_VIS)begin:precise_audio
      audio_spectrum_precise_overlay #(.SCREEN_W(SCREEN_W),.SCREEN_H(SCREEN_H),.BAR_W(BAR_W),.BAR_H(BAR_H),
       .BAR_X(SCREEN_W-BAR_W-44),.BAR_Y(SCREEN_H-BAR_H-76),.N_BANDS(12)) u_spectrum(
       .clk(clk),.rst(rst||!feature_mask[3]),.frame_tick(frame_tick),.band_valid(ff_band_valid),
       .band_idx(ff_band_idx),.band_mag(ff_band_mag),.source_live(external_spectrum_live),.x(s1_x),.y(s1_y),
       .bars_rgb(precise_bars_rgb),.bars_alpha(precise_bars_alpha));
      audio_waveform_precise_overlay #(.SCREEN_W(SCREEN_W),.SCREEN_H(SCREEN_H),.WAVE_W(WAVE_W),.WAVE_H(WAVE_H),
       .WAVE_X(WAVE_X),.WAVE_Y(WAVE_Y),.POINT_PX(POINT_PX),.SAMPLE_STEP(SAMPLE_STEP)) u_wave(
       .clk(clk),.rst(rst||!feature_mask[3]),.frame_tick(frame_tick),.audio_sample_valid(feature_mask[3]&&audio_sample_valid),
       .audio_sample(audio_sample),.x(s1_x),.y(s1_y),.wave_rgb(precise_wave_rgb),.wave_alpha(precise_wave_alpha));
    end else begin:no_precise_audio
      assign precise_bars_rgb=0;assign precise_bars_alpha=0;assign precise_wave_rgb=0;assign precise_wave_alpha=0;
    end endgenerate

    // 右下角：真频谱柱（接替原来的能量条，位置和配色不变）。
    // 和波形模块一样接 s2 坐标——模块内部自带一级流水，输出正好落在
    // s4 采样，和其它图层对齐。
    audio_spectrum_overlay #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H),
        .BAR_W    (BAR_W),
        .BAR_H    (BAR_H),
        .BAR_X    (SCREEN_W - BAR_W - 44),
        .BAR_Y    (SCREEN_H - BAR_H - 76),
        .N_BANDS  (12),
        .HEIGHT_SCALE_13_8 (1),
        .PITCH_DETAIL (1),
        .EXTERNAL_SOURCE (EXTERNAL_SPECTRUM)
    ) u_audio_spectrum_overlay (
        .clk        (clk),
        .rst        (rst || !feature_mask[3]),
        .frame_tick (frame_tick),
        .band_valid (ff_band_valid),
        .band_idx   (ff_band_idx),
        .band_mag   (ff_band_mag),
        .source_live(external_spectrum_live),
        .x          (s2_x),
        .y          (s2_y),
        .bars_rgb   (legacy_bars_rgb),
        .bars_alpha (legacy_bars_alpha)
    );

    audio_waveform_overlay #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H),
        .WAVE_W   (ENHANCED_AUDIO_VIS?192:WAVE_W),
        .WAVE_H   (ENHANCED_AUDIO_VIS?140:WAVE_H),
        .WAVE_X   (WAVE_X),
        .WAVE_Y      (WAVE_Y),
        .POINT_PX    (ENHANCED_AUDIO_VIS?4:POINT_PX),
        .SAMPLE_STEP (ENHANCED_AUDIO_VIS?5:SAMPLE_STEP)
    ) u_audio_waveform_overlay (
        .clk                (clk),
        .rst                (rst || !feature_mask[3]),
        .frame_tick         (frame_tick),
        .audio_sample_valid (feature_mask[3] && audio_sample_valid),
        .audio_sample       (audio_sample),
        // 波形模块内部有两级流水（见 audio_waveform_overlay 注释），
        // 所以坐标取 s1 而不是 s3，输出正好落在 s4 与其它图层对齐。
        .x                  (s1_x),
        .y                  (s1_y),
        .wave_rgb           (legacy_wave_rgb),
        .wave_alpha         (legacy_wave_alpha)
    );

    // One aligned stage separates OSD selection from the blend multiplier.
    reg t_hs,t_vs,t_de;reg [11:0] t_x,t_y;
    reg [23:0] t_rgb,t_text_rgb,t_bars_rgb,t_wave_rgb;
    reg [7:0] t_text_alpha,t_bars_alpha,t_wave_alpha;
    always @(posedge clk)begin
     if(rst)begin
      t_hs<=0;t_vs<=0;t_de<=0;t_x<=0;t_y<=0;t_rgb<=0;
      t_text_rgb<=0;t_text_alpha<=0;t_bars_rgb<=0;t_bars_alpha<=0;t_wave_rgb<=0;t_wave_alpha<=0;
     end else begin
      t_hs<=s4_hs;t_vs<=s4_vs;t_de<=s4_de;t_x<=s4_x;t_y<=s4_y;t_rgb<=s4_rgb;
      t_text_rgb<=s4_text_rgb;t_text_alpha<=s4_text_alpha;t_bars_rgb<=s4_bars_rgb;t_bars_alpha<=s4_bars_alpha;
      t_wave_rgb<=s4_wave_rgb;t_wave_alpha<=s4_wave_alpha;
     end
    end
    alpha_blend u_text_blend (
        .base_rgb  (t_rgb),
        .layer_rgb (t_text_rgb),
        .alpha     (t_text_alpha),
        .out_rgb   (text_mixed)
    );

    alpha_blend u_bars_blend (
        .base_rgb  (s5_rgb),
        .layer_rgb (s5_bars_rgb),
        .alpha     (s5_bars_alpha),
        .out_rgb   (bars_mixed)
    );

    // ---- 创新二：动态校园疏散地图（L4，最高优先级）----
    //
    // 坐标口径（本模块与基线唯一的差别，理由见 emergency_map_top.v 头注）：
    //   emergency_map_top 吃**本级的 x/y（第 0 拍）**，在窗口内自己打满 5 拍，
    //   于是它输出的颜色与宿主 s6_rgb 是同一个像素 —— 下面 s5->s6 边界再寄一拍
    //   （s6_evac_*）正好落在 s6_rgb 上，不新增流水级、不产生 1 px 偏移。
    // 老版 evac_map_layer 把整块窗口（底板/道路/建筑/路线/箭头/危险区/文字）的
    // 译码全挤在 s5 一拍里，实测 19.5 ns、预算 13.3 ns，是全设计最差路径；
    // 这一版把译码切成 5 级流水，最长的一段只剩“单层的成员判定”。
    generate if(EXTERNAL_MAP_PIXELS)begin: received_map_pixels
     // B has already rendered the complete frame. The ordinary pixel path
     // applies the fade once; a second copy of the map would bypass it.
     assign evac_map_rgb=0;assign evac_map_alpha=0;
    end else begin: local_map_reference
    emergency_map_top #(
        .REMOTE_MAP (REMOTE_MAP),
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H)
    ) u_emergency_map (
        .clk         (clk),
        .rst         (rst),
        .active      (evac_active),
        .state       (emergency_state_r),
        .event_type  (emergency_event),
        .remote_live (map_live),.remote_scene(map_scene),
        .blink_on    (blink_on),
        .frame_tick  (frame_tick),
        .cx          (x),
        .cy          (y),
        .map_rgb     (evac_map_rgb),
        .map_alpha   (evac_map_alpha)
    );
    end endgenerate

    reg [23:0] evac_rgb_d;reg [7:0] evac_alpha_d,evac_fade_d;
    // 窗口内整块不透明、窗口外一个像素都不参与 —— 与基线相同的“二选一”，
    // 不新增乘法器：video_clk 是 build17 最紧的域（基线只剩 +0.139 ns）。
    // rst 与主流水线一致走同步复位（本文件所有 always 都是 posedge clk + if (rst)）。
    always @(posedge clk) begin
        if (rst) begin
            evac_rgb_d<=0;evac_alpha_d<=0;evac_fade_d<=0;
            s6_evac_rgb   <= 24'd0;
            s6_evac_alpha <= 8'd0;
            s6_evac_fade  <= 8'd0;
        end
        else begin
            evac_rgb_d<=evac_map_rgb;evac_alpha_d<=evac_map_alpha;evac_fade_d<=evac_fade;
            s6_evac_rgb   <= evac_rgb_d;
            s6_evac_alpha <= evac_alpha_d;
            s6_evac_fade  <= evac_fade_d;
        end
    end

    // 地图窗口内整体不透明（emergency_map_top 已经把窗口外判成 alpha=0）：
    // 直接拿来叠校园图片也不会透出底图（不会出现 18% 鬼影）。
    // 疏散图现在是**整屏不透明**（窗口 = 全屏），所以这里的 alpha 用淡入值：
    // 出现的前 EVAC_FADE_FRAMES 帧是"疏散图 <-> SD 卡静态疏散图"的交叉淡入，
    // 淡到 255 之后就完全由硬件疏散图接管。
    wire [23:0] top_rgb_c   = (s6_evac_alpha != 8'd0) ? s6_evac_rgb  : s6_wave_rgb;
    wire [7:0] top_alpha_c = (s6_evac_alpha != 8'd0) ?
        s6_evac_fade : s6_wave_alpha; // full scene alpha is always 255 when valid

    alpha_blend u_wave_blend (
        .base_rgb  (s6_rgb),
        .layer_rgb (top_rgb_c),
        .alpha     (top_alpha_c),
        .out_rgb   (wave_mixed)
    );

    // 警报播放时去掉顶部的居中中文标题：把它的 alpha 压成 0，
    // 让位给下方的图片内容。警报屏上只留闪烁的红色警戒框和中央 EMERGENCY 白字
    // （左上 TIME / 右上状态 / 底部滚动字幕本来就由 text_overlay_8x8 里的
    //   !emergency 门控隐藏，这里是最后一块漏网的叠加层）。
    // 标题模块本身不动，只门控它的输出。
    // 用 emergency_r（见 text_overlay_8x8 例化前那一级的说明）。
    wire [23:0] title_rgb_g   = emergency_r ? 24'd0  : title_rgb;
    wire [7:0]  title_alpha_g = emergency_r ? 8'd0  : title_alpha;

    // 中文标题和音频条位于同一层，二者位置不重叠，用 alpha 做优先级选择
    wire [23:0] aux_rgb   = (title_alpha_g != 8'd0) ? title_rgb_g   : audio_bars_rgb;
    wire [7:0]  aux_alpha = (title_alpha_g != 8'd0) ? title_alpha_g : active_bars_alpha;

    always @(posedge clk) begin
        if (rst) begin
            de_d <= 1'b0;
            vs_d <= 1'b1;
            x <= 12'd0;
            y <= 12'd0;
            page_sync0 <= 2'd0;
            page_sync1 <= 2'd0;
            page_last <= 2'd0;
            scroll_phase <= 12'd0;
            elapsed_seconds <= 7'd0;
            second_divider <= 7'd0;
            blink_divider <= 16'd0;
            blink_on <= 1'b1;
            transition_active <= 1'b0;
            transition_x <= 12'd0;
            frame_tick <= 1'b0;
            emergency_state_r <= 3'd0;
            emergency_alarm_cnt <= 16'd0;
            emergency_event_frame <= 2'd0;
            evac_armed <= 1'b0;
            evac_arm_cnt <= 16'd0;
            evac_fade <= 8'd0;
            evac_seen_page1 <= 1'b0;
            page1_hold_cnt <= 8'd0;
            load_sync0 <= 1'b0;
            load_sync1 <= 1'b0;
            load_sync1_d <= 1'b0;
            nearly_sync0 <= 1'b0;
            nearly_sync1 <= 1'b0;
            fade_alpha <= 8'd0;
            load_frames <= 16'd0;
            last_load_frames <= LOAD_EST_FRAMES;
            fx_sync0 <= 3'd0;
            fx_sync1 <= 3'd0;
            fxo_sync0 <= 1'b0;
            fxo_sync1 <= 1'b0;
        end
        else begin
            de_d <= i_de;
            vs_d <= i_vs;
            page_sync0 <= page_index;
            page_sync1 <= page_sync0;
            // load_in_flight 在 sd_card_clk(100MHz) 域，这里两拍同步进 video_clk
            load_sync0 <= load_in_flight;
            load_sync1 <= load_sync0;
            load_sync1_d <= load_sync1;
            nearly_sync0 <= load_nearly_done;
            nearly_sync1 <= nearly_sync0;
            // 拨码开关：机械触点，两拍同步即可（慢变信号，抖动无害）
            fx_sync0 <= fx_sel;
            fx_sync1 <= fx_sync0;
            fxo_sync0 <= fx_off;
            fxo_sync1 <= fxo_sync0;
            frame_tick <= (!i_vs && vs_d);

            if (!i_vs && vs_d) begin
                // 滚动字幕：每个帧边界前进一像素
                if (scroll_phase >= SCROLL_MAX)
                    scroll_phase <= 12'd0;
                else
                    scroll_phase <= scroll_phase + 12'd1;

                // 运行时间：按帧计数，FRAMES_PER_SECOND 帧进位一次
                if (second_divider >= (FRAMES_PER_SECOND - 1)) begin
                    second_divider <= 7'd0;
                    if (elapsed_seconds == 7'd99)
                        elapsed_seconds <= 7'd0;
                    else
                        elapsed_seconds <= elapsed_seconds + 7'd1;
                end
                else begin
                    second_divider <= second_divider + 7'd1;
                end

                // 应急警戒框闪烁：BLINK_HALF_FRAMES 帧亮 / 同样帧数灭
                if (blink_divider >= (BLINK_HALF_FRAMES - 1)) begin
                    blink_divider <= 16'd0;
                    blink_on <= ~blink_on;
                end
                else begin
                    blink_divider <= blink_divider + 16'd1;
                end

                // ---- 创新二：应急期间的状态推进（报警 -> 疏散）----
                //   ALARM(2)      ：基础地图 + 红色危险区 + 事故靶心 + 当前位置 + 主路线
                //   EVACUATION(3) ：危险区蔓延块出现 -> 主线被判失效（暗红叉纹）-> 备用线变绿、
                //                   动态箭头改沿备用线流动（"自动切换备用路线"这一动作全在硬件里）
                // 不做成按下即疏散，是为了对应实施方案 4.3 的报警状态 -> 疏散状态。
                emergency_event_frame <= emergency_r ? emergency_event : 2'd0;
                if (!emergency_r) begin
                    evac_armed          <= 1'b0;
                    evac_arm_cnt        <= 16'd0;
                    emergency_state_r   <= 3'd0;
                    emergency_alarm_cnt <= 16'd0;
                end
                else if (!evac_armed) begin
                    // 火灾报警图还在放：疏散图一个像素都不出（连底板都不出）
                    if (evac_arm_now) begin
                        evac_armed          <= 1'b1;
                        emergency_state_r   <= 3'd2;
                        emergency_alarm_cnt <= 16'd0;
                    end
                    else begin
                        evac_arm_cnt <= evac_arm_cnt + 16'd1;
                    end
                end
                else if (emergency_state_r == 3'd0) begin
                    emergency_state_r   <= 3'd2;
                    emergency_alarm_cnt <= 16'd0;
                end
                else if (emergency_event_frame != emergency_event) begin
                    emergency_state_r <= 3'd2;
                    emergency_alarm_cnt <= 16'd0;
                end
                else if (emergency_alarm_cnt >= ALARM_TO_EVAC_LIM) begin
                    emergency_state_r <= 3'd3;
                end
                else begin
                    emergency_alarm_cnt <= emergency_alarm_cnt + 16'd1;
                end

                // ★ 页 1（卡上的静态疏散图）连续显示了多少帧 —— 动态疏散图就等它。
                //   只在 emergency 期间计数；退出应急清零（下次进来重新等）。
                if (!emergency_r) begin
                    evac_seen_page1 <= 1'b0;
                    page1_hold_cnt  <= 8'd0;
                end
                else if (page_sync1 == 3'd1) begin
                    evac_seen_page1 <= 1'b1;
                    if (page1_hold_cnt != EVAC_PAGE1_HOLD_LIM)
                        page1_hold_cnt <= page1_hold_cnt + 8'd1;
                end else begin
                    page1_hold_cnt <= 8'd0;
                    evac_seen_page1 <= 1'b0;
                end

                // 疏散图淡入（每帧一档，到 255 停住）。单独写在状态机之外：
                // 状态推进到 3 之后状态机最后那条 else 就不会再走了，
                // 淡入若挂在里面会永远卡在半透明。
                if (!emergency_r) begin
                    evac_fade <= 8'd0;
                end
                else if (evac_arm_now) begin
                    evac_fade <= EVAC_FADE_STEP;
                end
                else if (evac_armed && (evac_fade != 8'd255)) begin
                    evac_fade <= (evac_fade >= (8'd255 - EVAC_FADE_STEP)) ? 8'd255
                                                                        : (evac_fade + EVAC_FADE_STEP);
                end

                page_last <= page_sync1;

                // ---- 淡入淡出（扩展2）----
                // 时序（全部在 video_clk 域、每帧动一次，不需要任何跨域握手）：
                //   载图**快读完**（nearly_sync1）→ fade_alpha 每帧 +22，12 帧到 255
                //   剩下的载图时间 → 保持全黑（alpha 已钳在 255）
                //   提交新图 → load_sync1=0 且显示缓冲区已切换 → fade_alpha 每帧 -9
                // 关键点有两条：
                //   1) 切图那一拍画面已经是纯黑，所以缓冲区切换本身看不见；
                //   2) 淡出的**起点由载图进度给、不由时长预测给**，所以"全黑多久"
                //      在任何分辨率下都约等于 FADE_OUT_FRAMES —— 见上面
                //      fade_out_start 那段的来龙去脉。
                // 这就是"淡出→淡入"，不需要同时读两块帧缓存，SDRAM 带宽零增量。
                if (load_sync1)
                    load_frames <= (load_frames >= LOAD_HOLD_MAX) ?
                                   load_frames : (load_frames + 16'd1);
                else
                    load_frames <= 16'd0;

                // 记下这一次载图的真实帧数，给下一次预测提交时刻用。
                // 只在"正常完成"时更新：超时那几种（退化扫描）时长没有代表性，
                // 拿它去预测会让下一次淡出起点偏后，切图时会变成亮着硬切。
                //
                // ⚠️ 必须用**严格小于**：load_frames 在超时时会被钳在 LOAD_HOLD_MAX
                // （见上面那句），写成 <= 的话超时那一次照样会被记进来，预测就变成
                // 90 帧 —— 而正常载图只有 24 帧，画面根本来不及变暗，退化成满亮硬切。
                // 这个坑是给图案转场写测试时才发现的。
                if (load_sync1_d && !load_sync1 && (load_frames != 16'd0) &&
                    (load_frames < LOAD_HOLD_MAX))
                    last_load_frames <= load_frames;

                if (TRANSITION_MODE == 0) begin
                    // ★ 2026-09-27 上板反馈的"按应急键先黑屏约一秒"就修在这里。
                    //
                    // 旧判据是：load_sync1 高 -> 只淡出/保持；load_sync1 低 -> 才淡入。
                    // 于是"提交之后紧接着发起下一次载图"就出事 —— 那条路下
                    // load_in_flight 只在 **1 个 sd_card_clk** 里是低，75 MHz 的帧边界
                    // 根本采不到，淡入永远不进，黑幕一直挂到下一张图载完（≈1 s）。
                    //
                    // 新判据把"淡入"改成**默认分支**：只有在真正的淡出窗口
                    // （载图在飞 **且** 已经报"快读完了"/到了兜底点）里才压黑，
                    // 其余任何时刻画面是暗的就往回淡。这样载图重叠、提交脉冲被
                    // 采不到、甚至 load_in_flight 一整段都是高，都不再可能把画面
                    // 按死在黑幕上 —— 是"把这一类问题关掉"，不是"再补一个超时"。
                    // 代价：0 个触发器（还省掉了原先那个 16 位黑幕兜底计数器）。
                    if (startup_skip_fade || mode_switch_fast || (!emergency_r && !ordinary_fx_active))
                        fade_alpha <= 8'd0;
                    else if (load_frames >= LOAD_HOLD_MAX)
                        // 超时：放弃这次淡出，把画面放回来（见 LOAD_HOLD_MAX 注释）
                        fade_alpha <= 8'd0;
                    else if (load_sync1 && (nearly_sync1 || (load_frames >= FADE_OUT_BACKSTOP))) begin
                        // 淡出窗口：起点由**载图进度**给（bmp_read 报"离读完
                        // 还差约 12 帧的字节数"），所以走完的下一刻 ≈ 提交时刻，
                        // **与图有多大无关** —— 这正是本次要修的东西。
                        // 括号里那条是兜底：进度信号没来就强启，至少不硬切。
                        if (fade_alpha >= (8'd255 - FADE_OUT_STEP))
                            fade_alpha <= 8'd255;
                        else
                            fade_alpha <= fade_alpha + FADE_OUT_STEP;
                    end
                    else if (fade_alpha != 8'd0) begin
                        if (fade_alpha <= (particle_active ? 8'd6 : FADE_IN_STEP))
                            fade_alpha <= 8'd0;
                        else
                            fade_alpha <= fade_alpha - (particle_active ? 8'd6 : FADE_IN_STEP);
                    end
                end
                else begin
                    fade_alpha <= 8'd0;   // 擦除模式不使用，保持在透传
                end

                if (mode_switch_fast)
                    transition_active <= 1'b0;
                else if ((TRANSITION_MODE == 1) && feature_mask[1] && (page_sync1 != page_last)) begin
                    transition_active <= 1'b1;
                    transition_x <= 12'd0;
                end
                else if (transition_active) begin
                    if (transition_x >= SCREEN_W)
                        transition_active <= 1'b0;
                    else
                        transition_x <= transition_x + 12'd32;
                end
            end

            if (!i_vs && vs_d) begin
                x <= 12'd0;
                y <= 12'd0;
            end
            else if (i_de) begin
                if (!de_d)
                    x <= 12'd1;
                else
                    x <= x + 12'd1;

                if ((!de_d) && (y != 0))
                    y <= y;
            end
            else if (de_d) begin
                y <= y + 12'd1;
                x <= 12'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            s1_hs <= 1'b0; s1_vs <= 1'b0; s1_de <= 1'b0;
            s2_hs <= 1'b0; s2_vs <= 1'b0; s2_de <= 1'b0;
            s3_hs <= 1'b0; s3_vs <= 1'b0; s3_de <= 1'b0;
            s4_hs <= 1'b0; s4_vs <= 1'b0; s4_de <= 1'b0;
            s5_hs <= 1'b0; s5_vs <= 1'b0; s5_de <= 1'b0;
            s6_hs <= 1'b0; s6_vs <= 1'b0; s6_de <= 1'b0;
            s1_x <= 12'd0; s1_y <= 12'd0;
            s2_x <= 12'd0; s2_y <= 12'd0;
            s3_x <= 12'd0; s3_y <= 12'd0;
            s4_x <= 12'd0; s4_y <= 12'd0;
            s5_x <= 12'd0; s5_y <= 12'd0;
            s6_x <= 12'd0; s6_y <= 12'd0;
            s2_rgb <= 24'd0; s3_rgb <= 24'd0;
            s4_rgb <= 24'd0; s5_rgb <= 24'd0; s6_rgb <= 24'd0;
            s4_text_rgb <= 24'd0; s4_text_alpha <= 8'd0;
            s4_bars_rgb <= 24'd0; s4_bars_alpha <= 8'd0;
            s4_wave_rgb <= 24'd0; s4_wave_alpha <= 8'd0;
            s5_bars_rgb <= 24'd0; s5_bars_alpha <= 8'd0;
            s5_wave_rgb <= 24'd0; s5_wave_alpha <= 8'd0;
            s6_wave_rgb <= 24'd0; s6_wave_alpha <= 8'd0;
            s1_trans_black <= 1'b0;
            s1_trans_edge  <= 1'b0;
            s1_fx_alpha    <= 8'd0;
            o_hs <= 1'b0; o_vs <= 1'b0; o_de <= 1'b0;
            o_x <= 12'd0; o_y <= 12'd0; o_rgb <= 24'd0;
        end
        else begin
            s1_hs <= i_hs;
            s1_vs <= i_vs;
            s1_de <= i_de;
            s1_x  <= x;
            s1_y  <= y;
            s1_trans_black <= trans_black_c;
            s1_trans_edge  <= trans_edge_c;
            // 本像素的转场 alpha，和 s1_rgb 同拍。放在这一级（而不是混合级）是为了
            // 让 alpha_blend 的 alpha 输入仍然是一个寄存器 —— 那级乘法器余量本来就不多。
            s1_fx_alpha <= (startup_skip_fade || !feature_mask[1]) ? 8'd0 :
                (particle_active ? fx_local : emergency_r ? fade_alpha : (ordinary_fx_active ? fx_local : 8'd0));

            s2_hs <= s1_hs;
            s2_vs <= s1_vs;
            s2_de <= s1_de;
            s2_x  <= s1_x;
            s2_y  <= s1_y;
            s2_rgb <= transition_mixed;

            s3_hs <= s2_hs;
            s3_vs <= s2_vs;
            s3_de <= s2_de;
            s3_x  <= s2_x;
            s3_y  <= s2_y;
            s3_rgb <= transition_mixed;

            s4_hs <= s3_hs;
            s4_vs <= s3_vs;
            s4_de <= s3_de;
            s4_x  <= s3_x;
            s4_y  <= s3_y;
            s4_rgb <= s3_rgb;
            s4_text_rgb <= text_rgb;
            s4_text_alpha <= text_alpha;
            s4_bars_rgb <= aux_rgb;
            s4_bars_alpha <= aux_alpha;
            s4_wave_rgb <= waveform_rgb;
            s4_wave_alpha <= active_wave_alpha;

            s5_hs <= t_hs;
            s5_vs <= t_vs;
            s5_de <= t_de;
            s5_x  <= t_x;
            s5_y  <= t_y;
            s5_rgb <= text_mixed;
            s5_bars_rgb <= t_bars_rgb;
            s5_bars_alpha <= t_bars_alpha;
            s5_wave_rgb <= t_wave_rgb;
            s5_wave_alpha <= t_wave_alpha;

            s6_hs <= s5_hs;
            s6_vs <= s5_vs;
            s6_de <= s5_de;
            s6_x  <= s5_x;
            s6_y  <= s5_y;
            s6_rgb <= bars_mixed;
            s6_wave_rgb <= s5_wave_rgb;
            s6_wave_alpha <= s5_wave_alpha;

            o_hs <= s6_hs;
            o_vs <= s6_vs;
            o_de <= s6_de;
            o_x  <= s6_x;
            o_y  <= s6_y;
            o_rgb <= wave_mixed;
        end
    end

endmodule

// Equivalent integer /255 blend, with the multiplication registered before
// the two carry chains. This removes the palette BRAM -> DSP -> correction
// critical path without changing the compositor's external pipeline depth.
module alpha_blend_products(
 input clk,rst,input [23:0] base_rgb,layer_rgb,input [7:0] alpha,
 output [23:0] out_rgb);
 reg [15:0] base_r,base_g,base_b,layer_r,layer_g,layer_b;
 always @(posedge clk)begin
  if(rst)begin base_r<=0;base_g<=0;base_b<=0;layer_r<=0;layer_g<=0;layer_b<=0;end
  else begin
   base_r<=base_rgb[23:16]*(8'd255-alpha);layer_r<=layer_rgb[23:16]*alpha;
   base_g<=base_rgb[15:8]*(8'd255-alpha);layer_g<=layer_rgb[15:8]*alpha;
   base_b<=base_rgb[7:0]*(8'd255-alpha);layer_b<=layer_rgb[7:0]*alpha;
  end
 end
 function [7:0] finish;
 input [15:0] base_product,layer_product;reg [16:0] mixed,corrected;
 begin
  mixed={1'b0,base_product}+{1'b0,layer_product};
  corrected=mixed+(mixed>>8)+17'd1;finish=corrected[15:8];
 end endfunction
 assign out_rgb={finish(base_r,layer_r),finish(base_g,layer_g),finish(base_b,layer_b)};
endmodule
