`timescale 1ns/1ps

// Local route search removes the solver, reverse-node store and walking
// datapath from B. A already owns projection, so no scene round trip is needed.
// The marker distinguishes controls from the legacy type-3 complete scene.
module a_map_scene_compute #(parameter CLK_HZ=25000000,FRAME_CYCLES=416667,
 TIMEOUT_CYCLES=CLK_HZ/2,DEBOUNCE_MS=20,ENABLE_TEMPERATURE=0)(
 input clk,rst,online,input [2:0] actual_state,
 input packet_valid,input [223:0] packet,
 output controls_live,scene_valid,output [223:0] scene,
 output temperature_live,output reg [23:0] temperature_status);
 localparam AW=$clog2(TIMEOUT_CYCLES+1)>0?$clog2(TIMEOUT_CYCLES+1):1;
 reg have_controls;reg [AW-1:0] age;reg [15:0] control_sequence;
 reg [2:0] echoed_state;reg [1:0] zoom,barriers;
 wire [15:0] delta=packet[33:18]-control_sequence;
 wire legacy_control=packet[187:34]==0;
 wire temperature_extension=packet[187:74]==0 && packet[73:58]==16'h5401 && packet[57] &&
  (!packet[56] || (packet[52:50]==0 && $signed(packet[49:34])>=-16'sd880 && $signed(packet[49:34])<=16'sd2000));
 reg have_temperature;
 assign temperature_live=ENABLE_TEMPERATURE && online && have_controls && have_temperature && age<TIMEOUT_CYCLES;
 wire valid_control=packet_valid && packet[7:0]==3 && packet[223:188]==36'h4d4150431 &&
  (legacy_control || temperature_extension) && packet[15:14]==0 && packet[13:12]!=3 && !packet[8];
 wire new_control=!have_controls || (delta!=0 && !delta[15]);
 assign controls_live=online && have_controls && age<TIMEOUT_CYCLES && echoed_state==actual_state;
 always @(posedge clk or posedge rst)
  if(rst)begin have_controls<=0;age<=TIMEOUT_CYCLES;control_sequence<=0;echoed_state<=0;zoom<=0;barriers<=0;have_temperature<=0;temperature_status<=0;end
  else if(!online)begin have_controls<=0;age<=TIMEOUT_CYCLES;have_temperature<=0;end
  else begin
   if(age<TIMEOUT_CYCLES)age<=age+1'b1;
   if(valid_control && (new_control || delta==0))begin
    // Extended telemetry duplicates must not keep an old temperature fresh.
    if(new_control || legacy_control)age<=0;
    if(new_control)begin
     have_controls<=1;control_sequence<=packet[33:18];zoom<=packet[13:12];barriers<=packet[17:16];
     echoed_state<={packet[11:10],packet[9]};
     have_temperature<=ENABLE_TEMPERATURE && temperature_extension;
     if(ENABLE_TEMPERATURE)temperature_status<=temperature_extension?packet[57:34]:24'd0;
    end
   end
  end
 a_distributed_map_worker #(.CLK_HZ(CLK_HZ),.FRAME_CYCLES(FRAME_CYCLES),.DEBOUNCE_MS(DEBOUNCE_MS),.COMPUTE_VIEW(1)) u_local_route(
  .clk(clk),.rst(rst),.online(controls_live),.actual_state(actual_state),.switches(zoom),.barrier_mode(barriers),
  .stream_ready(1'b1),.stream_valid(scene_valid),.stream_data(scene));
endmodule

module smart_terminal_hw_top #(
    parameter ENABLE_MEDIA = 1,
    parameter ENABLE_SUBTITLE = 1,
    parameter ENABLE_SCAN_DIAGNOSTIC = 0,
    parameter FAST_DEMO = 1,
    parameter ENABLE_MESH3D = 0,
    parameter ENABLE_RASTER = 1,
    parameter ENABLE_REMOTE_TF = 1,
    parameter [4:0] FEATURE_MASK = 5'h0F,
    // 应急红色警戒框的闪烁半周期（帧数）。30 帧 @60Hz ≈ 0.5 s 亮 / 0.5 s 灭。
    parameter integer BLINK_HALF_FRAMES = 30,
    // 底部滚动字幕的字模放大倍数（8 * BANNER_SCALE 像素见方）
    parameter integer BANNER_SCALE = 4,
    // 转场方式：0 = 淡入淡出（默认），1 = 水平滑动擦除。
    // 留成 parameter 是为了将来由拨码开关 / 构建变体切换现场演示，不用改 RTL。
    parameter integer TRANSITION_MODE = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_next,
    input  wire        key_auto,
    input  wire        key_emergency,
    input wire eth_rx_clk,eth_rx_ctl,
    input wire [3:0] eth_rxd,
    output wire eth_tx_clk,eth_tx_ctl,
    output wire [3:0] eth_txd,
    output wire eth_mdc,
    inout wire eth_mdio,
    // 板载 4 个拨码开关（引脚 C8/C7/C6/C5）。拨上 = 0，拨下 = 1。
    // sw[2:0] 选转场图案（见 transition_fx.v 的图案表），sw[3] = 关掉转场做硬切对照。
    // 全部拨上 = 均匀淡入淡出 + 特效开 —— 和没有这组开关时行为一致。
    input  wire [3:0]  sw,

    output wire [5:0]  seg_sel,
    output wire [7:0]  seg_data,
    output wire [3:0]  led,

    output wire        HDMI_CLK_P,
    output wire        HDMI_D2_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D0_P,

    output wire        HDMI_DDC_SCL,
    inout  wire        HDMI_DDC_SDA,

    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);

    wire map_mode,map_staging_slot,map_display_slot,map_have;
    wire emergency_map_ready,normal_animation,normal_animation_ready;reg [1:0] emergency_map_ready_video,normal_animation_video,normal_animation_ready_video;
    wire photo_geometry_active,photo_geometry_flip,photo_geometry_back,photo_geometry_hold;
    wire [3:0] photo_geometry_old,photo_geometry_new,photo_geometry_idle;
    wire [3:0] geometry_current_source,geometry_idle_source;
    wire dynamic_scanout;
    wire freeze_dynamic_frame;
    reg geometry_active_d;
 wire map_commit_animation,map_display_animation;
    wire net_clk,net_tx90,net_lock;
    wire map_write_req,map_write_ack,map_write_en,map_write_cancel,map_commit,map_commit_ready;
    wire [31:0] map_write_data;wire [1:0] map_commit_event;
    reg map_finish_toggle_mem;
    wire media_writer_full,media_write_cancel;
    parameter MEM_DATA_BITS = 32;
    parameter ADDR_BITS     = 21;
    parameter BUSRT_BITS    = 10;
    parameter FRAME_PIXELS  = 24'd307200;
    parameter BUF0_ADDR     = 24'd0;
    parameter BUF1_ADDR     = 24'd307200;
    parameter BUF2_ADDR     = 24'd614400; // completed alarm cache, independent of buffers 0/1

    wire Sdr_init_done;
    wire Sdr_init_ref_vld;
    wire Sdr_busy;

    wire sd_card_clk;
    // Cached-page UI is a slow control plane. Its clock is the existing
    // 25MHz network clock; the physical TF SPI remains on sd_card_clk.
    wire media_control_clk=ENABLE_MEDIA?net_clk:sd_card_clk;
    wire ext_mem_clk;
    wire ext_mem_clk_sft;
    wire video_clk;
    wire hdmi_5x_clk;

    wire hs;
    wire vs;
    wire de;

    wire [23:0] vout_data_raw;
    wire        display_valid;

    wire [3:0]  state_code;
    wire [34:0] media_debug;wire debug_valid;wire [34:0] debug_clk;
    wire [3:0] media_revision;reg [3:0] revision_meta,revision_sync;wire [6:0] revision_segments;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin revision_meta<=0;revision_sync<=0;end
      else begin revision_meta<=media_revision;revision_sync<=revision_meta;end
    seg_decoder u_revision_decoder(.bin_data(revision_sync),.seg_data(revision_segments));
    wire [3:0]  load_fault;            // 载图看门狗故障码（见 sd_card_bmp.v）
    wire        load_fault_recurring;  // 故障不止一次
    wire [6:0]  seg_data_0;
    wire [6:0]  seg_data_fault;
    wire [6:0]  seg_data_sw;
    // ---- 创新二：动态校园疏散地图 ----
    // 事件类型数码管读数（0 火灾 / 1 地震 / 2 实验室事故 / 3 演练）
    wire [6:0]  seg_data_event;

    wire        video_read_req;
    wire        video_read_req_ack;
    wire        video_read_en;
    wire [31:0] video_read_data;
    wire        video_read_empty;      // 读 FIFO 空标志：扫描器据此决定能不能弹

    wire        sd_card_write_en;
    wire [31:0] sd_card_write_data;
    wire        sd_card_write_req;
    wire        frame_write_req_ack;
    wire        frame_write_finish;
    reg         frame_write_toggle_mem;

    wire        scaling_write_en;
    wire [31:0] scaling_write_data;
    wire        scaling_write_req;
    wire        scaling_frame_done;
    wire        frame_write_en;
    wire [31:0] frame_write_data;
    wire        frame_write_req;
    wire [1:0]  active_write_buf_idx;
    wire [1:0]  active_disp_buf_idx;

    wire [1:0]  write_buf_idx;
    wire [1:0]  disp_buf_idx;
    // Registered transition intent from the SD scheduler. Ordinary prefetch
    // stays visible until a complete next frame enters the timed fade window.
    // The overlay synchronizes this single-bit level into video_clk.
    wire        load_in_flight;
    wire        auto_play_en;
    wire [2:0]  page_index;      // 最多 5 张图，需要 3 bit
    wire        brightness_step_toggle;
    wire        contrast_step_toggle;

    // 当前显示那张图的源分辨率（sd_card_clk 域） + 数据有效握手位
    wire [15:0] disp_src_w;
    wire [15:0] disp_src_h;
    wire        disp_src_toggle;
    wire        disp_audio_emergency;
    // 同步到 video_clk 之后的分辨率（喂给 OSD）
    reg  [2:0]  res_tgl_sync;
    reg  [15:0] res_w_v;
    reg  [15:0] res_h_v;

    wire        App_rd_en;
    wire [ADDR_BITS-1:0] App_rd_addr;
    wire        Sdr_rd_en;
    wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
    wire        App_wr_en;
    wire [ADDR_BITS-1:0] App_wr_addr;
    wire [MEM_DATA_BITS-1:0] App_wr_din;
    wire [3:0]  App_wr_dm;

    wire        audio_pll_lock;
    wire        audio_mclk;
    wire        audio_i2s_bclk;
    wire        audio_i2s_lrck;
    wire        audio_i2s_dout;
    wire        audio_valid;
    wire [23:0] audio_left_data;
    wire [23:0] audio_right_data;
    wire        acr_valid;
    wire [19:0] acr_cts;
    wire [19:0] acr_n;
    wire [15:0] audio_magnitude;

    wire        axis_s_user;
    wire        axis_s_valid;
    wire        axis_s_last;
    wire [23:0] axis_s_data;
    wire        axis_s_ready;

    wire        overlay_hs;
    wire        overlay_vs;
    wire        overlay_de;
    wire [23:0] overlay_rgb;

    wire        edid_trig;
    wire        edid_valid;
    wire [7:0]  edid_data;

    wire [9:0]  tmds_ch0_data;
    wire [9:0]  tmds_ch1_data;
    wire [9:0]  tmds_ch2_data;
    wire [9:0]  tmds_clk_data;

    wire        rst_all;
    always @(posedge video_clk or posedge rst_all)
     if(rst_all)begin normal_animation_video<=0;normal_animation_ready_video<=0;end
     else begin normal_animation_video<={normal_animation_video[0],normal_animation};normal_animation_ready_video<={normal_animation_ready_video[0],normal_animation_ready};end

    always @(posedge video_clk or posedge rst_all)
     if(rst_all)emergency_map_ready_video<=0;else emergency_map_ready_video<={emergency_map_ready_video[0],emergency_map_ready};

    wire        rst_mem_startup;
    wire        sys_pll_lock;
    wire        video_pll_lock;
    wire        emergency_trigger;
    wire        emergency_mode;
    // ---- 创新二：动态校园疏散地图 ----
    // S3（key_auto）短按：应急期间切换事件类型。非应急时恒为 0（火灾）。
    wire        emergency_event_step;
    wire [1:0]  emergency_event;
    wire [2:0]  brightness_level;
    wire [1:0] palette_bank;
    wire palette_write_enable;
    wire [9:0] palette_write_address;
    wire [7:0] palette_write_value;
    wire [2:0]  contrast_level;
    reg         display_valid_video_1;
    reg         display_valid_video_2;
    // 转场窗口跨界：sd_card_clk -> video_clk。普通预取等待完整帧与统一截止时间；
    //   手动/应急仍使用 bmp_read 的 NEARLY_DONE_SECTORS。慢变电平，
    //   两拍同步即可，不需要握手 —— 与 display_valid 同一种处理。
    wire        load_nearly_done;         // sd_card_clk 域，来自 sd_card_bmp
    reg         load_nearly_done_v1;
    reg         load_nearly_done_v2;
    reg         frame_write_toggle_video_1;
    reg         frame_write_toggle_video_2;
    wire        display_enable_video;
    wire        sd_hard_recover;
    // One input pipeline stage for the overlay. The old cone ran
    // display_valid_video -> i_rgb mux -> video_enhance multiplier ->
    // transition blend in a single 75 MHz cycle. Registering the complete
    // input tuple keeps the OSD/transition behavior unchanged while giving
    // PnR a legal boundary.
    reg  [23:0] overlay_i_rgb_q;
    reg         overlay_i_hs_q;
    reg         overlay_i_vs_q;
    reg         overlay_i_de_q;

    // ------------------------------------------------------------------
    // 上电复位：等真正的时钟源都锁定再放行
    //
    // 原来是 `assign rst_all = ~rst_n | ~audio_pll_lock;` —— 只监视音频 PLL。
    // 而音频 PLL 只给 hdmi_audio_tone_i2s_64fs 供时钟，它锁定得早，
    // 于是 rst_all 在 sys_pll（sd_card_clk / ext_mem_clk）和
    // video_pll_720p（video_clk / hdmi_5x_clk）还没锁定时就释放了：
    // 上电后 SD 初始化跑在尚未稳定的时钟上，TF 卡进不了 SPI 模式，
    // sd_init_done 永远拉不起来（数码管 state_code 恒为 0，就是板上现象）。
    // 换成这两个 PLL 后，上电必然先复位、且只在时钟稳定后才放行。
    //
    // This remains the immediate asynchronous reset for the video/SD logic.
    // SDRAM uses synchronous Rst internally: it needs reset to remain high
    // on valid ext_mem_clk edges after PLL lock, rather than relying on a
    // pre-lock reset pulse that may arrive while that clock is stopped.
    // ------------------------------------------------------------------
    // FPGA configuration may finish after PLL locks are already high. Do not
    // depend on an external key or a pre-clock lock edge to initialize state.
    wire power_on_reset;
    board_startup_reset u_board_startup_reset(.ref_clk(clk),.rst_n(rst_n),
        .clock_locks({sys_pll_lock,video_pll_lock,net_lock}),.reset_hold(power_on_reset));
    wire immediate_reset = ~rst_n | ~sys_pll_lock | ~video_pll_lock;
    // The diagnostic mailbox destinations run on the reference clock.
    // Release their reset locally, rather than from a video-clock register.
    wire rst_reference;
    startup_release_sync u_startup_release_reference(.clk(clk),
        .async_fault(immediate_reset),.startup_hold(power_on_reset),.rst(rst_reference));
    startup_release_sync u_startup_release_video(.clk(video_clk),
        .async_fault(immediate_reset),.startup_hold(power_on_reset),.rst(rst_all));
    startup_release_sync #(.STAGES(16)) u_memory_startup_reset (
        .clk(ext_mem_clk), .async_fault(immediate_reset),
        .startup_hold(power_on_reset), .rst(rst_mem_startup)
    );

    reg writer_owned,writer_map;reg [2:0] any_finish_sync;
    reg any_finish_toggle_mem;
    wire selected_cancel=writer_owned && (writer_map?map_write_cancel:media_write_cancel);
    wire media_writer_ack=frame_write_req_ack && writer_owned && !writer_map;
    assign map_write_ack=frame_write_req_ack && writer_owned && writer_map;
    always @(posedge ext_mem_clk or posedge rst_mem_startup)
     if(rst_mem_startup)any_finish_toggle_mem<=0;else if(frame_write_finish)any_finish_toggle_mem<=~any_finish_toggle_mem;
    always @(posedge net_clk or posedge rst_all)
     if(rst_all)begin writer_owned<=0;writer_map<=0;any_finish_sync<=0;end
     else begin
      any_finish_sync<={any_finish_sync[1:0],any_finish_toggle_mem};
      if(writer_owned)begin if(selected_cancel || any_finish_sync[2]!=any_finish_sync[1])writer_owned<=0;end
      else if(sd_card_write_req)begin writer_owned<=1;writer_map<=0;end
      else if(map_write_req)begin writer_owned<=1;writer_map<=1;end
     end
    assign frame_write_req=FEATURE_MASK[4]?scaling_write_req:ENABLE_MEDIA?(writer_owned && (writer_map?map_write_req:sd_card_write_req)):sd_card_write_req;
    assign frame_write_en=FEATURE_MASK[4]?scaling_write_en:ENABLE_MEDIA?(writer_owned && (writer_map?map_write_en:sd_card_write_en)):sd_card_write_en;
    assign frame_write_data=FEATURE_MASK[4]?scaling_write_data:writer_map?map_write_data:sd_card_write_data;
    assign active_write_buf_idx = FEATURE_MASK[4] ? 2'd0 : write_buf_idx;
    assign active_disp_buf_idx  = FEATURE_MASK[4] ? 2'd0 : disp_buf_idx;
    assign display_enable_video = FEATURE_MASK[4] ?
                                  frame_write_toggle_video_2 :
                                  (display_valid_video_2 || map_mode);

    sys_pll sys_pll_m0 (
        .refclk   (clk),
        .clk0_out (sd_card_clk),
        .clk1_out (ext_mem_clk),
        .clk2_out (ext_mem_clk_sft),
        .extlock  (sys_pll_lock),
        .reset    (1'b0)
    );

    video_pll_720p video_pll_m0 (
        .refclk   (clk),
        .clk0_out (video_clk),
        .clk1_out (hdmi_5x_clk),
        .extlock  (video_pll_lock),
        .reset    (1'b0)
    );

    PLL_HDMI_AUDIO u_audio_pll (
        .refclk   (clk),
        .reset    (1'b0),
        .extlock  (audio_pll_lock),
        .clk0_out (),
        .clk1_out (),
        .clk2_out (audio_mclk)
    );

    always @(posedge ext_mem_clk or posedge rst_mem_startup) begin
        if (rst_mem_startup)begin frame_write_toggle_mem<=0;map_finish_toggle_mem<=0;end
        else if (frame_write_finish)begin
            if(writer_map && ENABLE_RASTER)map_finish_toggle_mem<=~map_finish_toggle_mem;
            else frame_write_toggle_mem<=~frame_write_toggle_mem;
        end
    end

    always @(posedge video_clk or posedge rst_all) begin
        if (rst_all) begin
            display_valid_video_1 <= 1'b0;
            display_valid_video_2 <= 1'b0;
            frame_write_toggle_video_1 <= 1'b0;
            frame_write_toggle_video_2 <= 1'b0;
            load_nearly_done_v1 <= 1'b0;
            load_nearly_done_v2 <= 1'b0;
        end
        else begin
            display_valid_video_1 <= display_valid;
            display_valid_video_2 <= display_valid_video_1;
            frame_write_toggle_video_1 <= frame_write_toggle_mem;
            frame_write_toggle_video_2 <= frame_write_toggle_video_1;
            load_nearly_done_v1 <= load_nearly_done;
            load_nearly_done_v2 <= load_nearly_done_v1;
        end
    end

    // ------------------------------------------------------------------
    // 源分辨率跨界：sd_card_clk -> video_clk
    //
    // 16 位总线**不能**逐位两级同步（各位到达时刻不同，会采到从未存在过的组合）。
    // 用标准的「数据 + 单比特 toggle」握手：
    //   sd_card_clk 域在**同一拍**更新 disp_src_w/h 并翻转 disp_src_toggle；
    //   video_clk 域三级同步这个 toggle，检测到边沿时数据已经稳定 ≥3 拍，可以安全采。
    // 这个值每张图才变一次（秒级），握手开销完全可以忽略。
    // ------------------------------------------------------------------
    always @(posedge video_clk or posedge rst_all) begin
        if (rst_all) begin
            res_tgl_sync <= 3'b000;
            res_w_v      <= 16'd0;
            res_h_v      <= 16'd0;
        end
        else begin
            res_tgl_sync <= {res_tgl_sync[1:0], disp_src_toggle};
            if (res_tgl_sync[2] ^ res_tgl_sync[1]) begin
                res_w_v <= disp_src_w;
                res_h_v <= disp_src_h;
            end
        end
    end

    display_parameter_control u_display_parameters(
        .clk(video_clk),.rst(rst_all),.emergency(emergency_mode),
        .vsync(overlay_i_vs_q),.brightness_step_toggle(brightness_step_toggle),
        .contrast_step_toggle(contrast_step_toggle),
        .brightness(brightness_level),.contrast(contrast_level),
        .palette_bank(palette_bank),.palette_write_enable(palette_write_enable),
        .palette_write_address(palette_write_address),.palette_write_value(palette_write_value)
    );

    key_remove_shakes u_key_emergency (
        .I_clk          (video_clk),
        .I_rst_n        (~rst_all),
        .I_key_in       (key_emergency),
        .O_key_trig_out (emergency_trigger)
    );

    // Local and remote arbitration is implemented below after the key decoder.
    
    // ------------------------------------------------------------------
    // 创新二：事件类型选择（S3 = key_auto 短按）
    //
    // 为什么不占用 S4：S4（key_emergency）现在是「短按进出应急」的单键 toggle，
    //   那条路已经上板验证过。给它加「长按换事件」会把 toggle 的触发沿从按下
    //   挪到松开（key_short_long 必须先分清长短按，才敢在松开时决定发哪个脉冲），
    //   为了一个新功能去动一条已验证的通路，不值得。
    //
    // 为什么借 S3 是安全的：应急期间 sd_card_bmp 会强制开启轮播
    //   （见 sd_card_bmp.v 的 emergency 分支），S3 那个「自动轮播开关」在这时
    //   本来就没有可见效果；而且这里只在 emergency_mode 期间计数，非应急时
    //   事件类型恒为 0（火灾）—— 演示每次从同一起点开始，可重复。
    //
    // 复用 key_short_long：它就定义在 vendor/user_source/hdl_source/SD/sd_card_bmp.v
    //   里，而本文件已经例化了同一文件中的 sd_card_bmp，模块早就编进来了；它内部
    //   自带两级同步和去抖，于是和 sd_card_bmp 内部那个实例各去各的抖、互不干扰。
    //   顶层端口和 constraints/pin.adc 一个字都不用改。
    //   时钟域 video_clk（75 MHz）；HOLD_MS 取 700 与 S2/S3 在 sd_card_bmp 里的
    //   门槛一致（长按仍是连发，不是切换，故 REPEAT_MS 取 250）。
    // ------------------------------------------------------------------
    key_short_long #(
        .CLK_FREQ_HZ (75_000_000),
        .DEBOUNCE_MS (20),
        .HOLD_MS     (700),
        .REPEAT_MS   (250)
    ) u_key_auto_event (
        .clk         (video_clk),
        .rst         (rst_all),
        .button_in   (key_auto),
        .short_pulse (emergency_event_step),
        // 长按这里不用：S3 长按在 sd_card_bmp 里保持它原来的语义
        .long_step   ()
    );
    

    wire net_rst=~rst_n || ~net_lock;
    wire peer_packet;wire [20:0] peer_message;
    wire net_online,net_phy_configured,net_phy_link,net_tx_active;
    wire [4:0] net_diag_flags;wire [19:0] net_diag_counts;
    wire [24:0] net_diag_ref;
    wire [7:0] peer_extension;wire [4:0] carousel_feedback;wire [6:0] net_feedback;
    // A byte count is not proof that a picture can be displayed. Keep the
    // loading bar at zero until full-frame scanout and HDMI have qualified.
    wire startup_display_ready;
    wire [8:0] startup_progress=startup_display_ready?9'd511:9'd0;
    wire hdmi_output_reset,hdmi_video_ready;
    wire [8:0] remote_phase;wire [1:0] interval_selection,period_video_data;reg [1:0] period_video;
    wire [10:0] remote_video;wire remote_video_valid;
    wire [2:0] local_net_state;
    wire remote_ready,status_ready;
    wire [223:0] net_stream_out,net_stream_in;
    wire subtitle_ack_valid;wire [223:0] subtitle_ack;

    wire net_stream_valid,net_stream_ready;
    wire pcm_stream_valid;wire [223:0] pcm_stream_data;
    wire mesh_stream_valid;wire [223:0] mesh_stream_data;wire [1:0] mesh_view_mode_sd,mesh_view_mode_net;
    wire tf_stream_valid,tf_stream_ready;wire [223:0] tf_stream_data;
    wire media_ack_valid,media_ack_ready;wire [127:0] media_ack_net;
    wire raster_ack_valid,raster_ack_ready;wire [223:0] raster_ack;



    wire map_cdc_valid,map_cdc_ready;

    wire raw_vs,raw_hs,raw_de,raw_frame_start;wire [11:0] raw_x,raw_y;
    wire map_frame_req,map_frame_en,map_hs,map_vs,map_de;wire [23:0] map_frame_rgb;
    wire normal_frame_req,normal_frame_en,normal_hs,normal_vs,normal_de,normal_pixel_ready;wire [23:0] normal_rgb;

    wire temperature_live_net;wire [23:0] temperature_status_net;
    wire [24:0] temperature_video;
    ethernet_mailbox #(.WIDTH(25)) u_temperature_mailbox(
     .src_clk(net_clk),.src_rst(net_rst||rst_all),.src_valid(1'b1),
     .src_data({temperature_live_net,temperature_status_net}),.src_ready(),
     .dst_clk(video_clk),.dst_rst(net_rst||rst_all),.dst_valid(),.dst_data(temperature_video));
    generate if(ENABLE_MEDIA && ENABLE_RASTER)begin: scene25_compute
     wire controls_live,scene_valid;wire [223:0] local_scene;
     a_map_scene_compute #(.ENABLE_TEMPERATURE(1)) u_scene_compute(.clk(net_clk),.rst(net_rst||rst_all),.online(net_online),
      .actual_state(local_net_state),.packet_valid(peer_packet),.packet(net_stream_in),
      .controls_live(controls_live),.scene_valid(scene_valid),.scene(local_scene),
      .temperature_live(temperature_live_net),.temperature_status(temperature_status_net));
     reg pending;reg [223:0] held;
     always @(posedge net_clk or posedge rst_all)
      if(rst_all)begin pending<=0;held<=0;end
      else if(net_rst || !net_online)pending<=0;
      else begin
       if(mesh_stream_valid && net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid&&!tf_stream_valid&&!subtitle_ack_valid)pending<=0;
       if(scene_valid)begin pending<=1;held<=local_scene;end
      end
     assign mesh_stream_valid=pending && controls_live;assign mesh_stream_data={12'd0,held[187:8],16'd0,8'd1,8'd14};
     assign mesh_view_mode_net=0;
    end else begin: no_scene25
     assign temperature_live_net=0;assign temperature_status_net=0;
     assign mesh_stream_valid=0;assign mesh_stream_data=0;assign mesh_view_mode_net=0;
    end endgenerate
    wire particle_ack_valid,particle_ready;wire [223:0] particle_ack;wire [56:0] particle_motion;
    wire [12:0] particle_address;wire [7:0] particle_code;
    particle_atlas_receiver #(.MOTION(1)) u_particle_receiver(.net_clk(net_clk),.rst(rst_all),.online(net_online&&!net_rst),
     .packet_valid(peer_packet),.packet(net_stream_in),.ack_valid(particle_ack_valid),.ack_packet(particle_ack),
     .ack_ready(net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid&&!tf_stream_valid&&!subtitle_ack_valid&&!mesh_stream_valid),
     .motion(particle_motion),.video_clk(video_clk),.read_address(particle_address),.read_code(particle_code),.ready(particle_ready));
    wire [11:0] subtitle_x,subtitle_y;wire subtitle_active,subtitle_pixel,subtitle_bar,subtitle_show;
    generate if(ENABLE_SUBTITLE)begin: subtitle_service
     subtitle_display u_subtitle(.net_clk(net_clk),.net_rst(net_rst||rst_all),.packet_valid(peer_packet),.packet(net_stream_in),
      .ack_valid(subtitle_ack_valid),.ack_packet(subtitle_ack),.ack_ready(net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid&&!tf_stream_valid),
      .video_clk(video_clk),.video_rst(net_rst||rst_all),.video_vs(overlay_i_vs_q),.emergency(emergency_mode),
      .x_pre(subtitle_x),.y_pre(subtitle_y),.custom_active(subtitle_active),.custom_pixel(subtitle_pixel),.custom_bar(subtitle_bar));
    end else begin
     assign subtitle_ack_valid=0;assign subtitle_ack=0;assign subtitle_active=0;assign subtitle_pixel=0;assign subtitle_bar=0;
    end endgenerate
    assign net_stream_valid=pcm_stream_valid || raster_ack_valid || media_ack_valid || tf_stream_valid || subtitle_ack_valid || mesh_stream_valid || particle_ack_valid;
    assign net_stream_out=pcm_stream_valid?pcm_stream_data:raster_ack_valid?raster_ack:media_ack_valid?{96'd0,media_ack_net}:tf_stream_valid?tf_stream_data:subtitle_ack_valid?subtitle_ack:mesh_stream_valid?mesh_stream_data:particle_ack;
    assign raster_ack_ready=net_stream_ready&&!pcm_stream_valid;
    assign tf_stream_ready=net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid;
    assign media_ack_ready=net_stream_ready && !pcm_stream_valid && !raster_ack_valid;
    wire pcm_net_valid,pcm_mail_ready;wire [24:0] pcm_net_data;
    reg pcm_restart_pending;
    wire pcm_source_valid=audio_valid && FEATURE_MASK[3];
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)pcm_restart_pending<=1;
      else if(pcm_source_valid)pcm_restart_pending<=!pcm_mail_ready;
    ethernet_mailbox #(.WIDTH(25)) u_pcm_mailbox(
      .src_clk(video_clk),.src_rst(net_rst || rst_all),.src_valid(pcm_source_valid),
      .src_data({pcm_restart_pending,audio_left_data}),.src_ready(pcm_mail_ready),
      .dst_clk(net_clk),.dst_rst(net_rst || rst_all),.dst_valid(pcm_net_valid),.dst_data(pcm_net_data));
    distributed_pcm_sender u_pcm_sender(.clk(net_clk),.rst(net_rst || rst_all),.online(net_online),
      .sample_valid(pcm_net_valid),.sample(pcm_net_data[23:0]),.sample_restart(pcm_net_data[24]),
      .stream_ready(net_stream_ready),.stream_valid(pcm_stream_valid),.stream_data(pcm_stream_data));
    wire external_band_valid,external_spectrum_live;
    wire map_frame_tick,map_live;wire [187:0] map_scene;
    generate if(ENABLE_RASTER && ENABLE_MEDIA)begin: raster_service
     assign map_live=0;assign map_scene=0;
     raster_map_window_receiver #(.PIXELS(307200),.ALLOW_ANIMATION(1),.ANIMATION_PIXELS(307200),.NATIVE_VGA(1),.DECODE_ACK(1),.WINDOW_LOG2(4)) u_receiver(.clk(net_clk),.rst(net_rst||rst_all),.online(net_online),.packet_valid(peer_packet),.packet(net_stream_in),
      .ack_valid(raster_ack_valid),.ack_packet(raster_ack),.ack_ready(raster_ack_ready),.write_cancel(map_write_cancel),
      .write_req(map_write_req),.write_ack(map_write_ack),.write_full(media_writer_full),.write_done_toggle(map_finish_toggle_mem),
      .write_en(map_write_en),.write_data(map_write_data),.commit_valid(map_commit),.commit_ready(map_commit_ready),.commit_event(map_commit_event),.commit_animation(map_commit_animation));
     media_commit_cdc u_commit(.src_clk(net_clk),.dst_clk(video_clk),.rst(net_rst||rst_all),
      .src_valid(map_commit),.src_ready(map_commit_ready),.dst_valid(map_cdc_valid),.dst_ready(map_cdc_ready));
     map_received_frame_control #(.NORMAL_ANIMATION(1),.HOLD_COMPLETE_FRAME(1)) u_cache(.hold_frame(freeze_dynamic_frame),.clk(video_clk),.rst(rst_all),.vsync(raw_vs),.emergency(emergency_mode && emergency_map_ready_video[1]),.event_type(emergency_event),
      .complete(map_cdc_valid),.incoming_event(map_commit_event),.incoming_animation(map_commit_animation),.animation_requested(normal_animation_ready_video[1] && !emergency_mode),.commit_ready(map_cdc_ready),
      .staging_slot(map_staging_slot),.display_slot(map_display_slot),.map_mode(map_mode),.have_map(map_have),.display_animation(map_display_animation));
     map_rgb444_scanout u_scanout(.animation(map_display_animation),.clk(video_clk),.rst(rst_all),.enabled(dynamic_scanout),.frame_start(raw_frame_start || (geometry_active_d && !photo_geometry_active)),
      .hs_raw(raw_hs),.vs_raw(raw_vs),.de_raw(raw_de),.x_raw(raw_x),.y_raw(raw_y),
      .read_req(map_frame_req),.read_ack(video_read_req_ack && dynamic_scanout),.read_empty(video_read_empty),.read_data(video_read_data),.read_en(map_frame_en),
      .hs(map_hs),.vs(map_vs),.de(map_de),.rgb(map_frame_rgb));
    end else begin: parameter_map_reference
     assign raster_ack_valid=0;assign raster_ack=0;assign map_write_req=0;assign map_write_en=0;assign map_write_data=0;assign map_write_cancel=0;
     assign map_mode=0;assign map_display_animation=0;assign map_staging_slot=0;assign map_display_slot=0;assign map_have=0;assign map_frame_req=0;assign map_frame_en=0;
    distributed_map_client u_map_client(.net_clk(net_clk),.video_clk(video_clk),.rst(net_rst || rst_all),
      .online(net_online),.packet_valid(peer_packet),.packet(net_stream_in),.frame_tick(map_frame_tick),
      .event_type(emergency_event),.live(map_live),.scene(map_scene));
    end endgenerate
    wire [19:0] external_band_data,net_band_data;
    wire net_band_valid,net_band_ready,net_spectrum_live;
    reg [1:0] spectrum_live_sync;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)spectrum_live_sync<=0;
      else spectrum_live_sync<={spectrum_live_sync[0],net_spectrum_live};
    assign external_spectrum_live=spectrum_live_sync[1];
    distributed_spectrum_client u_spectrum_client(
      .clk(net_clk),.rst(net_rst || rst_all),.online(net_online),.packet_valid(peer_packet),.packet(net_stream_in),
      .band_ready(net_band_ready),.band_valid(net_band_valid),.band_data(net_band_data),.live(net_spectrum_live));
    ethernet_mailbox #(.WIDTH(20)) u_spectrum_band_mailbox(
      .src_clk(net_clk),.src_rst(net_rst || rst_all),.src_valid(net_band_valid),.src_data(net_band_data),.src_ready(net_band_ready),
      .dst_clk(video_clk),.dst_rst(net_rst || rst_all),.dst_valid(external_band_valid),.dst_data(external_band_data));
    ethernet_pll u_ethernet_pll(.refclk(clk),.reset(1'b0),.clk0_out(net_clk),.clk1_out(net_tx90),.clk2_out(),.extlock(net_lock));
    ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(ENABLE_MEDIA),.RASTER(ENABLE_RASTER&&ENABLE_MEDIA),.RAW_TF(ENABLE_REMOTE_TF&&ENABLE_MEDIA),.RAW_TF_VERSION(12),.BURST_RASTER(1),.SUBTITLE(ENABLE_SUBTITLE)) u_ethernet_link(
     .clk(net_clk),.tx_clk90(net_tx90),.rst(net_rst),
     .local_state(local_net_state),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension({1'd0,net_feedback}),
     .eth_rx_clk(eth_rx_clk),.eth_rx_ctl(eth_rx_ctl),.eth_rxd(eth_rxd),
     .eth_tx_clk(eth_tx_clk),.eth_tx_ctl(eth_tx_ctl),.eth_txd(eth_txd),.eth_mdc(eth_mdc),.eth_mdio(eth_mdio),
     .peer_valid(peer_packet),.peer_message(peer_message),.peer_extension(peer_extension),.peer_online(net_online),.phy_configured(net_phy_configured),.phy_link(net_phy_link),.tx_active(net_tx_active),
     .stream_valid(net_stream_valid),.stream_data(net_stream_out),.stream_ready(net_stream_ready),.peer_stream(net_stream_in));
    ethernet_mailbox #(.WIDTH(11)) u_remote_mailbox(
     .src_clk(net_clk),.src_rst(net_rst || rst_all),.src_valid(peer_packet && peer_message[20]),.src_data(peer_message[10:0]),.src_ready(remote_ready),
     .dst_clk(video_clk),.dst_rst(net_rst || rst_all),.dst_valid(remote_video_valid),.dst_data(remote_video));
    ethernet_mailbox #(.WIDTH(3)) u_status_mailbox(
     .src_clk(video_clk),.src_rst(net_rst || rst_all),.src_valid(1'b1),.src_data({emergency_event,emergency_mode}),.src_ready(status_ready),
     .dst_clk(net_clk),.dst_rst(net_rst || rst_all),.dst_valid(),.dst_data(local_net_state));
    ethernet_mailbox #(.WIDTH(7)) u_carousel_feedback(
     .src_clk(media_control_clk),.src_rst(net_rst || rst_all),.src_valid(1'b1),.src_data({normal_animation,ENABLE_MEDIA && ENABLE_RASTER && emergency_map_ready,carousel_feedback}),.src_ready(),
     .dst_clk(net_clk),.dst_rst(net_rst || rst_all),.dst_valid(),.dst_data(net_feedback));
    ethernet_mailbox #(.WIDTH(9)) u_carousel_phase(
     .src_clk(net_clk),.src_rst(net_rst || rst_all),.src_valid(1'b1),.src_data({net_online,peer_extension}),.src_ready(),
     .dst_clk(media_control_clk),.dst_rst(net_rst || rst_all),.dst_valid(),.dst_data(remote_phase));
    ethernet_mailbox #(.WIDTH(2)) u_carousel_period_ui(
     .src_clk(media_control_clk),.src_rst(rst_all),.src_valid(1'b1),.src_data(interval_selection),.src_ready(),
     .dst_clk(video_clk),.dst_rst(rst_all),.dst_valid(),.dst_data(period_video_data));
    always @(posedge video_clk or posedge rst_all)
     if(rst_all)period_video<=0;else if(overlay_i_vs_q)period_video<=period_video_data;
    dual_board_emergency_control u_emergency_control(
     .clk(video_clk),.rst(rst_all),.local_toggle(emergency_trigger),.local_event_step(emergency_event_step),
     .remote_valid(remote_video_valid),.remote_command(remote_video),
     .emergency_mode(emergency_mode),.emergency_event(emergency_event));

    wire [2:0] staging_slot,display_slot;

    function [20:0] media_frame_base;input [2:0] slot;
     begin case(slot)0:media_frame_base=0;1:media_frame_base=230400;2:media_frame_base=460800;
      3:media_frame_base=691200;4:media_frame_base=921600;5:media_frame_base=1152000;6:media_frame_base=1382400;default:media_frame_base=1612800;endcase end
    endfunction
    generate if(ENABLE_MEDIA)begin: media_service
     wire [223:0] ack_net;wire commit_valid,commit_ready,commit_valid_sd,commit_ready_sd;
     wire [2:0] commit_role;wire [15:0] commit_w,commit_h;
     assign media_ack_net=ack_net[127:0];
     assign staging_slot=commit_role;
     media_image_receiver #(.IMAGE_ROLES(8),.PACK_RGB888(1),.IMMUTABLE_CACHE(1)) u_receiver(.cache_reset(rst_all||FEATURE_MASK[4]),.clk(net_clk),.rst(net_rst||rst_all||FEATURE_MASK[4]),.online(net_online),
      .packet_valid(peer_packet),.packet(net_stream_in),.ack_valid(media_ack_valid),.ack_packet(ack_net),.ack_ready(media_ack_ready),
      .write_cancel(media_write_cancel),.write_req(sd_card_write_req),.write_ack(media_writer_ack),.write_full(media_writer_full),
      .write_done_toggle(frame_write_toggle_mem),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
      .frame_commit_valid(commit_valid),.frame_commit_ready(commit_ready),.commit_role(commit_role),
      .commit_width(commit_w),.commit_height(commit_h),.transfer_active(),.receive_progress(),
      .remote_fault(load_fault),.remote_fault_recurring(load_fault_recurring),.remote_revision(media_revision),.remote_debug(media_debug));
     media_commit_cdc u_commit_bridge(.src_clk(net_clk),.dst_clk(media_control_clk),.rst(net_rst||rst_all),
      .src_valid(commit_valid),.src_ready(commit_ready),.dst_valid(commit_valid_sd),.dst_ready(commit_ready_sd));
     a_media_cached_control #(.CLK_FREQ_HZ(25_000_000),.NORMAL_PERIOD_MS(3000),.IMAGE_ROLES(8),.FIXED_SLOTS(1),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) u_cached_control(.clk(media_control_clk),.rst(rst_all||FEATURE_MASK[4]),
      .animation_visible(map_mode),
      .key_next(key_next),.key_auto(key_auto),.emergency(emergency_mode),.vsync(vs),.remote_phase(remote_phase),
      .incoming_complete(commit_valid_sd),.incoming_role(commit_role),.incoming_w(commit_w),.incoming_h(commit_h),
      .incoming_commit_ready(commit_ready_sd),.staging_slot(),.display_slot(display_slot),.display_valid(display_valid),
      .page_index(page_index),.disp_src_w(disp_src_w),.disp_src_h(disp_src_h),.disp_src_toggle(disp_src_toggle),
      .disp_audio_emergency(disp_audio_emergency),.load_nearly_done(load_nearly_done),.load_visual_active(load_in_flight),
      .auto_play_en_out(auto_play_en),.carousel_feedback(carousel_feedback),.interval_selection(interval_selection),
      .map_view_mode(mesh_view_mode_sd),.brightness_step_toggle(brightness_step_toggle),.contrast_step_toggle(contrast_step_toggle),.cached_roles(),.state_code(state_code),.emergency_map_ready(emergency_map_ready),.normal_animation(normal_animation),.normal_animation_ready(normal_animation_ready));
     assign sd_hard_recover=0;assign write_buf_idx=0;assign disp_buf_idx=0;
     if(ENABLE_REMOTE_TF)begin: tf_sector_service
      // 100MHz / ((6+2)*2) = 6.25MHz. Keep the physical card interface
      // conservative; B's buffered normalization still uses its fast path.
      a_tf_sector_service_timed #(.SPI_HIGH_SPEED_DIV(6)) u_service(.net_clk(net_clk),.sd_clk(sd_card_clk),.rst(net_rst||immediate_reset),.online(net_online),
       .packet_valid(peer_packet),.packet(net_stream_in),.stream_valid(tf_stream_valid),.stream_data(tf_stream_data),.stream_ready(tf_stream_ready),
       .sd_miso(sd_miso),.sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi));
     end else begin
      assign sd_ncs=1;assign sd_dclk=0;assign sd_mosi=1;assign tf_stream_valid=0;assign tf_stream_data=0;
     end
    end else begin: legacy_tf_reference
     assign mesh_view_mode_sd=0;
     assign media_revision=0;assign media_debug=0;
     assign emergency_map_ready=1;assign normal_animation=0;assign normal_animation_ready=0;
     assign media_write_cancel=0;assign media_ack_valid=0;assign media_ack_net=0;assign staging_slot=0;assign display_slot=0;
    sd_card_bmp #(
        .CLK_FREQ_HZ       (100_000_000),
        .REMOTE_SCHEDULE   (1),
        .SCAN_START_SECTOR (32'd0),
        .SCAN_MAX_SECTOR   (32'd131071),
        .SCAN_TARGET_COUNT (3'd5)
    ) sd_card_bmp_m0 (
        .clk                (sd_card_clk),
        .rst                (rst_all || FEATURE_MASK[4]),
        .key_next           (key_next),
        .key_auto           (key_auto),
        // 警报模式（video_clk 域）传进 sd_card_clk 域：
        // 只在最后两张之间轮播，且强制开启轮播。模块内部自带同步器。
        .emergency          (emergency_mode),
        .remote_phase       (remote_phase),
        .carousel_feedback  (carousel_feedback),
        .interval_selection (interval_selection),
        .brightness_step_toggle(brightness_step_toggle),
        .contrast_step_toggle  (contrast_step_toggle),
        .page_index_out     (page_index),
        .state_code         (state_code),
        // 诊断：载图看门狗故障码 -> 数码管（见下面的 seg_decoder）
        .load_fault         (load_fault),
        .load_fault_recurring(load_fault_recurring),
        .hard_recover       (sd_hard_recover),
        .bmp_width          (16'd640),
        .bmp_height         (16'd480),
        .display_valid      (display_valid),
        // C2-a：把"当前显示那张图的源分辨率"接出来，显示在 OSD 信息栏
        .disp_src_w         (disp_src_w),
        .disp_src_h         (disp_src_h),
        .disp_src_toggle    (disp_src_toggle),
        .disp_audio_emergency(disp_audio_emergency),
        .load_nearly_done   (load_nearly_done),
        .load_visual_active (load_in_flight),
        .write_finish_toggle(frame_write_toggle_mem),
        .auto_play_en_out   (auto_play_en),
        .write_buf_idx      (write_buf_idx),
        .disp_buf_idx       (disp_buf_idx),
        .write_req          (sd_card_write_req),
        .write_req_ack      (frame_write_req_ack),
        .write_en           (sd_card_write_en),
        .write_data         (sd_card_write_data),
        .SD_nCS             (sd_ncs),
        .SD_DCLK            (sd_dclk),
        .SD_MOSI            (sd_mosi),
        .SD_MISO            (sd_miso)
    );
    end endgenerate

    seg_decoder seg_decoder_m0 (
        .bin_data (state_code),
        .seg_data (seg_data_0)
    );

    // 载图看门狗故障码单独占一位（这一位原来是常灭的）。
    //   0 = 从未超时；1/2/3 = 超时卡在哪一层（含义见 sd_card_bmp.v 的 load_fault）
    //   **小数点 = 故障复发过**（>=2 次）
    // 有了它，下一次上板"卡不卡、卡在哪一层"直接读一位数就知道，
    // 不用再靠"这次现象像上次"去猜 —— 本工程缺的正是这个读数。
    seg_decoder seg_decoder_fault (
        .bin_data (load_fault),
        .seg_data (seg_data_fault)
    );

    // ------------------------------------------------------------------
    // 拨码开关读数（这一位原来常灭）
    //
    // 为什么必须显示它：转场有**两级**闸门，而其中一级直接就是 sw[3] ——
    //     s1_fx_alpha = (feature_mask[1] && !fxo_sync1) ? fx_local : 0
    //   四个拨码引脚**全部带 PULLUP**，引脚约束写的是「拨上 = 0，拨下 = 1」。
    //   于是 sw[3] 拨下 = **转场整个关掉（硬切）**；而 sw[2:0] 全拨上 = 图案 0
    //   （最不显眼的均匀淡入淡出）。"四个全拨下去看图案"恰好把总闸关了
    //   —— 板上表现为"按动拨码没有了转场效果"。
    //
    //   而 HANDOVER 记着：拨码的**物理编号 SW1..SW4 与引脚的对应关系是推的、
    //   没实物核对过**。所以现场根本没法知道哪个物理开关是 sw[3]。
    //
    //   这一位显示 sw[3:0] 的十六进制值，一次点亮：
    //     **0 = 均匀淡入淡出（特效开）**
    //     **1..7 = 图案 1..7（特效开）**
    //     **8..F = 特效关**（≥8 就说明 sw[3] 是 1，转场被那个开关关掉了）
    //   拨动任何一个开关，这一位都应立刻跟着变；**不变的那个开关就是没接上**。
    // ------------------------------------------------------------------
    seg_decoder seg_decoder_sw (
        .bin_data (sw[3:0]),
        .seg_data (seg_data_sw)
    );
    
    // ---- 创新二：事件类型读数（这一位原来就是空位）----
    //   0 = 火灾  1 = 地震  2 = 实验室事故  3 = 演练
    //   应急期间按 S3 短按改的就是它：上板时不用猜图上画的是哪个事件。
    seg_decoder seg_decoder_event (
        .bin_data ({1'b0, emergency_event}),
        .seg_data (seg_data_event)
    );

    ethernet_link_diagnostics u_net_diagnostics(.clk(net_clk),.rst(net_rst||rst_all),
      .configured(net_phy_configured),.link_100(net_phy_link),.online(net_online),
      .tx_active(net_tx_active),.rx_ctl(eth_rx_ctl),.packet_valid(peer_packet),.flags(net_diag_flags),.counts(net_diag_counts));
    ethernet_mailbox #(.WIDTH(25)) u_net_diag_cdc(.src_clk(net_clk),.src_rst(net_rst||rst_all),
      .src_valid(1'b1),.src_data({net_diag_flags,net_diag_counts}),.src_ready(),
      .dst_clk(clk),.dst_rst(rst_reference),.dst_valid(),.dst_data(net_diag_ref));
    wire net_diag_needed=!net_diag_ref[22] || revision_sync==0;
    ethernet_mailbox #(.WIDTH(35)) u_debug_cdc(.src_clk(net_clk),.src_rst(net_rst||rst_all),.src_valid(1'b1),.src_data(media_debug),.src_ready(),
      .dst_clk(clk),.dst_rst(rst_reference),.dst_valid(debug_valid),.dst_data(debug_clk));
    // Fault pages: normal status -> b + five hex file-byte digits ->
    // d + file number + 0 + three hex completed-row digits. One second each.
    reg [25:0] debug_tick;reg [1:0] debug_page;reg [3:0] fault_meta,fault_sync;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin debug_tick<=0;debug_page<=0;fault_meta<=0;fault_sync<=0;end
      else begin
        fault_meta<=load_fault;fault_sync<=fault_meta;
        if(!net_diag_needed && (fault_sync==0 || revision_sync<5))begin debug_tick<=0;debug_page<=0;end
        else if(debug_tick==49999999)begin debug_tick<=0;debug_page<=debug_page==2?0:debug_page+1'b1;end
        else debug_tick<=debug_tick+1'b1;
      end
    wire [3:0] debug_file=debug_clk[34:32]==0?5:debug_clk[34:32]==1?6:
      debug_clk[34:32]==2?1:debug_clk[34:32]==3?2:debug_clk[34:32]==4?3:4;
    wire debug_predata=revision_sync>=6 && debug_clk[19:0]==0 && debug_clk[31:25]==7'h7f;
    // Offline/unknown-version pages: normal -> A C L O T R -> F TT RR V.
    // C/L/O are live configured/100M-full/peer-online; T/R are activity seen.
    // TT and RR saturate at FF, V (accepted frames) at F. All are hex.
    wire [23:0] net_diag_nibbles=debug_page==1?
      {4'ha,3'd0,net_diag_ref[24],3'd0,net_diag_ref[23],3'd0,net_diag_ref[22],3'd0,net_diag_ref[21],3'd0,net_diag_ref[20]}:
      {4'hf,net_diag_ref[19:0]};
    wire [23:0] debug_nibbles=net_diag_needed?net_diag_nibbles:debug_page==1?{4'hb,debug_clk[19:0]}:
      debug_predata?{4'he,debug_file,8'd0,3'd0,debug_clk[24:20]}:{4'hd,debug_file,4'd0,debug_clk[31:20]};
    wire [41:0] debug_segments;
    genvar dbg;
    generate for(dbg=0;dbg<6;dbg=dbg+1)begin: fault_hex
      seg_decoder u_hex(.bin_data(debug_nibbles[(5-dbg)*4 +:4]),.seg_data(debug_segments[dbg*7 +:7]));
    end endgenerate
    seg_scan seg_scan_m0 (
        .clk(clk),.rst_n(rst_n),.seg_sel(seg_sel),.seg_data(seg_data),
        .seg_data_0({1'b1,debug_page==0?seg_data_event:debug_segments[0 +:7]}),
        .seg_data_1({1'b1,debug_page==0?revision_segments:debug_segments[7 +:7]}),
        .seg_data_2({1'b1,debug_page==0?7'b100_0110:debug_segments[14 +:7]}),
        .seg_data_3({1'b1,debug_page==0?seg_data_sw:debug_segments[21 +:7]}),
        .seg_data_4({debug_page==0 && load_fault_recurring?1'b0:1'b1,debug_page==0?seg_data_fault:debug_segments[28 +:7]}),
        .seg_data_5({1'b1,debug_page==0?seg_data_0:debug_segments[35 +:7]})
    );

    // Flip/zoom across photos and complete RGB444 particle frames. Dynamic
    // commits are held while either endpoint is used by the transition.
    // Static metadata is held by the SD-domain source. Reuse its existing
    // three-stage commit synchronizer before sampling the multibit slot;
    // dynamic slots already belong to this video clock domain.
    reg [2:0] geometry_committed_photo;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)geometry_committed_photo<=3'd2;
      else if(res_tgl_sync[2] ^ res_tgl_sync[1])geometry_committed_photo<=display_slot;
    assign geometry_current_source=map_mode?{3'b100,map_display_slot}:{1'b0,geometry_committed_photo};
    assign geometry_idle_source=photo_geometry_hold && !(photo_geometry_idle[3] && geometry_current_source[3])?photo_geometry_idle:geometry_current_source;
    assign dynamic_scanout=geometry_idle_source[3] && !photo_geometry_active;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)geometry_active_d<=0;else geometry_active_d<=photo_geometry_active;
    reg [2:0] geometry_switch_meta,geometry_switch;
    reg geometry_off_meta,geometry_off;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)begin geometry_switch_meta<=0;geometry_switch<=0;geometry_off_meta<=1;geometry_off<=1;end
      else begin geometry_switch_meta<=sw[2:0];geometry_switch<=geometry_switch_meta;
        geometry_off_meta<=sw[3];geometry_off<=geometry_off_meta;end
    wire [5:0] photo_geometry_phase;
    wire [11:0] photo_geometry_width,photo_geometry_left;
    wire [9:0] photo_geometry_height,photo_geometry_top;
    wire [16:0] photo_geometry_inv_x,photo_geometry_inv_y;
    wire [20:0] photo_geometry_read_base;
    wire photo_geometry_read_rgb444;
    reg [3:0] geometry_source_d;reg geometry_source_toggle;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)begin geometry_source_d<=4'd2;geometry_source_toggle<=0;end
      else if(geometry_current_source!=geometry_source_d)begin
        geometry_source_d<=geometry_current_source;geometry_source_toggle<=~geometry_source_toggle;
      end
    assign freeze_dynamic_frame=!emergency_mode && !geometry_off && (geometry_switch==1 || geometry_switch==2) &&
      (photo_geometry_active || (map_mode && !normal_animation_ready_video[1]) ||
       (photo_geometry_hold && photo_geometry_idle[3] && !geometry_current_source[3]));
    function [20:0] geometry_frame_base;input [3:0] source;
      begin geometry_frame_base=source[3]?(source[0]?21'd1958400:21'd1843200):media_frame_base(source[2:0]);end
    endfunction
    photo_geometry_control #(.PHASE_STEP(FAST_DEMO?2:1),.SLOT_BITS(4),.DYNAMIC_SLOTS(1)) u_photo_geometry_control(.clk(video_clk),.rst(rst_all),.frame_start(raw_frame_start),
      .eligible(ENABLE_MEDIA && FEATURE_MASK[1] && !FEATURE_MASK[4] && display_valid_video_2 && startup_display_ready &&
        !emergency_mode && !geometry_off),
      .selector(geometry_switch),.slot_in(geometry_current_source),.commit_toggle(geometry_source_toggle),
      .active(photo_geometry_active),.flip(photo_geometry_flip),.phase(photo_geometry_phase),
      .old_slot(photo_geometry_old),.new_slot(photo_geometry_new),
      .width(photo_geometry_width),.height(photo_geometry_height),.left(photo_geometry_left),.top(photo_geometry_top),
      .inv_x(photo_geometry_inv_x),.inv_y(photo_geometry_inv_y),.back_half(photo_geometry_back),
      .idle_slot(photo_geometry_idle),.hold_slot(photo_geometry_hold));
    // Preserve the original first-image loading policy. After the original
    // scan/HDMI qualifier has succeeded once, keep the existing memory-local
    // busy/refresh burst-entry guard enabled for steady scanout and writes.
    // HDMI reconnects must not disable memory safety. No media timer is gated.
    reg qualified_memory_guard;
    always @(posedge video_clk or posedge rst_all)
      if(rst_all)qualified_memory_guard<=1'b0;
      else if(startup_display_ready)qualified_memory_guard<=1'b1;
    wire [31:0] normal_pixel_data;wire normal_pixel_empty,packed_frame_en;
    generate if(ENABLE_MEDIA)begin: packed_image_read
     rgb888_frame_unpack #(.FAST_WORD_READ(1),.RGB444_SUPPORT(1)) u_unpack(.rgb444(photo_geometry_active && photo_geometry_read_rgb444),.fast_mode(photo_geometry_active),.clk(video_clk),.rst(rst_all | sd_hard_recover),
      .restart(normal_frame_req || dynamic_scanout || FEATURE_MASK[4]),.word_empty(video_read_empty),.word_data(video_read_data),.word_read(packed_frame_en),
      .pixel_read(normal_frame_en),.pixel_empty(normal_pixel_empty),.pixel_data(normal_pixel_data));
    end else begin
     assign normal_pixel_data=video_read_data;assign normal_pixel_empty=video_read_empty;assign packed_frame_en=normal_frame_en;
    end endgenerate
    video_scanout_720p #(.ENABLE_GEOMETRY(ENABLE_MEDIA),.GEOMETRY_RGB444(ENABLE_MEDIA)) u_video_scanout_720p (
        .geometry_active(photo_geometry_active),.geometry_flip(photo_geometry_flip),
        .geometry_width(photo_geometry_width),.geometry_left(photo_geometry_left),
        .geometry_height(photo_geometry_height),.geometry_top(photo_geometry_top),
        .geometry_inv_x(photo_geometry_inv_x),.geometry_inv_y(photo_geometry_inv_y),
        .geometry_old_base(geometry_frame_base(photo_geometry_old)),.geometry_new_base(geometry_frame_base(photo_geometry_new)),
        .geometry_old_rgb444(photo_geometry_old[3]),.geometry_new_rgb444(photo_geometry_new[3]),.geometry_read_rgb444(photo_geometry_read_rgb444),
        .geometry_back_half(photo_geometry_back),.geometry_read_base(photo_geometry_read_base),
        .clk           (video_clk),
        .rst           (rst_all | sd_hard_recover),
        .read_req      (normal_frame_req),
        .read_req_ack  (video_read_req_ack && !dynamic_scanout),
        .read_en       (normal_frame_en),
        .read_data     (normal_pixel_data),
        .read_empty    (normal_pixel_empty),
        .hs(normal_hs),.vs(normal_vs),.de(normal_de),.rgb(normal_rgb),.pixel_ready(normal_pixel_ready),
        .raw_hs(raw_hs),.raw_vs(raw_vs),.raw_de(raw_de),.raw_x(raw_x),.raw_y(raw_y),.raw_frame_start(raw_frame_start)
    );

    startup_display_qualifier u_startup_display_qualifier(
        .clk(video_clk),.rst(rst_all),.image_complete(display_valid_video_2),
        .normal_active(!map_mode),.frame_sync(normal_vs),
        .pixel_de(normal_de),.pixel_ready(normal_pixel_ready),
        .hdmi_ready(hdmi_video_ready),.display_ready(startup_display_ready));

    assign video_read_req=dynamic_scanout?map_frame_req:(normal_frame_req && !raw_vs);
    assign video_read_en=dynamic_scanout?map_frame_en:(ENABLE_MEDIA && !FEATURE_MASK[4]?packed_frame_en:normal_frame_en);
    assign hs=dynamic_scanout?map_hs:normal_hs;assign vs=dynamic_scanout?map_vs:normal_vs;assign de=dynamic_scanout?map_de:normal_de;
    assign vout_data_raw=dynamic_scanout?map_frame_rgb:normal_rgb;
    frame_read_write #(
        .ENABLE_WRITE_CANCEL (ENABLE_MEDIA),
        .ENABLE_GEOMETRY_GUARD (ENABLE_MEDIA),
        .WRITE_V_FLIP (ENABLE_MEDIA?0:1),
        .FRAME_WIDTH  (640),
        .FRAME_HEIGHT (480)
    ) frame_read_write_m0 (
        .geometry_mode(photo_geometry_active || qualified_memory_guard),
        .mem_clk          (ext_mem_clk),
        .rst              (rst_mem_startup | sd_hard_recover),
        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),
        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout),
        .read_clk         (video_clk),
        .read_req         (video_read_req),
        .read_req_ack     (video_read_req_ack),
        .read_finish      (),
        .read_addr_0      (dynamic_scanout?geometry_frame_base(geometry_idle_source):(ENABLE_MEDIA && !FEATURE_MASK[4]?(photo_geometry_active?photo_geometry_read_base:geometry_frame_base(geometry_idle_source)):BUF0_ADDR)),
        .read_addr_1      (BUF1_ADDR),
        .read_addr_2      (BUF2_ADDR),
        .read_addr_3      (24'd0),
        .read_addr_index  (active_disp_buf_idx),
        .read_len         (dynamic_scanout?21'd115200:(ENABLE_MEDIA && !FEATURE_MASK[4]?(photo_geometry_active?(photo_geometry_read_rgb444?21'd256:21'd512):21'd230400):FRAME_PIXELS)),
        .read_en          (video_read_en),
        .read_data        (video_read_data),
        .read_empty       (video_read_empty),
        .App_wr_en        (App_wr_en),
        .App_wr_addr      (App_wr_addr),
        .App_wr_din       (App_wr_din),
        .App_wr_dm        (App_wr_dm),
        .write_clk        (ENABLE_MEDIA && !FEATURE_MASK[4]?net_clk:sd_card_clk),
        .write_req        (frame_write_req),
        .write_req_ack    (frame_write_req_ack),
        .write_finish     (frame_write_finish),
        .write_addr_0     (writer_map?(map_staging_slot?21'd1958400:21'd1843200):(ENABLE_MEDIA && !FEATURE_MASK[4]?media_frame_base(staging_slot):BUF0_ADDR)),
        .write_addr_1     (BUF1_ADDR),
        .write_addr_2     (BUF2_ADDR),
        .write_addr_3     (24'd0),
        .write_addr_index (active_write_buf_idx),
        .write_len        (writer_map?21'd115200:(ENABLE_MEDIA && !FEATURE_MASK[4]?21'd230400:FRAME_PIXELS)),
        .write_en         (frame_write_en),
        .write_data       (frame_write_data),
        .write_full       (media_writer_full),
        .write_cancel     (ENABLE_MEDIA?selected_cancel:1'b0)
    );

    scaling_pattern_writer #(
        .H_ACTIVE (640),
        .V_ACTIVE (480),
        .SRC_W    (320),
        .SRC_H    (240)
    ) u_scaling_pattern_writer (
        .clk           (sd_card_clk),
        .rst           (rst_all),
        .start         (FEATURE_MASK[4]),
        .Sdr_init_done (Sdr_init_done),
        .write_req     (scaling_write_req),
        .write_req_ack (frame_write_req_ack),
        .write_en      (scaling_write_en),
        .write_data    (scaling_write_data),
        .frame_done    (scaling_frame_done)
    );

    sdram U3 (
        .Clk              (ext_mem_clk),
        .Clk_sft          (ext_mem_clk_sft),
        .Rst              (rst_mem_startup),
        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),
        .App_wr_en        (App_wr_en),
        .App_wr_addr      (App_wr_addr),
        .App_wr_dm        (App_wr_dm),
        .App_wr_din       (App_wr_din),
        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout)
    );

    wire [2:0] audio_committed_page;
    wire audio_page_pending;
    wire audio_page_emergency;
    wire audio_sample_tick;
    image_audio_commit_cdc u_image_audio_commit_cdc (
        .src_clk(media_control_clk), .dst_clk(audio_mclk), .rst(immediate_reset),
        .src_commit_toggle(disp_src_toggle), .src_page(page_index),
        .src_valid(display_valid && !FEATURE_MASK[4]),
        .src_emergency(disp_audio_emergency),
        .dst_sample_tick(audio_sample_tick),
        .dst_page(audio_committed_page), .dst_pending(audio_page_pending),
        .dst_emergency(audio_page_emergency)
    );

    hdmi_audio_tone_i2s_64fs #(
        .EXACT_48K_ENABLE (1),        .PAGE_LINK_ENABLE (!FEATURE_MASK[4]),
        .PHASE_INC (32'd39370534),
        .AMP       (24'sd2000000)
    ) u_hdmi_audio_tone_i2s_64fs (
        .I_mclk     (audio_mclk),
        .I_rst      (immediate_reset),
        .I_emergency(emergency_mode),
        .O_i2s_BCLK (audio_i2s_bclk),
        .O_i2s_LRCK (audio_i2s_lrck),
        .O_i2s_DOUT (audio_i2s_dout),
        .I_page_index(audio_committed_page),
        .I_page_update(audio_page_pending),
        .I_page_emergency(audio_page_emergency),
        .O_sample_tick(audio_sample_tick)
    );

    I2S_receiver u_I2S_receiver (
        .I_clk              (video_clk),
        .I_rst              (rst_all),
        .I_i2s_BCLK         (audio_i2s_bclk),
        .I_i2s_LRCK         (audio_i2s_lrck),
        .I_i2s_DOUT         (audio_i2s_dout),
        .O_audio_valid      (audio_valid),
        .O_audio_left_data  (audio_left_data),
        .O_audio_right_data (audio_right_data)
    );

    audio_envelope u_audio_envelope (
        .clk          (video_clk),
        .rst          (rst_all),
        .sample_valid (audio_valid),
        .sample_left  (audio_left_data),
        .magnitude    (audio_magnitude)
    );

    audio_arc_calculate #(
        .ACR_N (6144)
    ) u_audio_arc_calculate (
        .I_clk         (video_clk),
        .I_rst         (rst_all),
        .I_audio_valid (audio_valid),
        .O_acr_valid   (acr_valid),
        .O_acr_cts     (acr_cts),
        .O_acr_n       (acr_n)
    );

    smart_terminal_overlay_pipelined #(
        .ENABLE_PARTICLES (1),.ENABLE_PARTICLE_MOTION(1),.ENABLE_SUBTITLE(ENABLE_SUBTITLE),.ENABLE_TEMPERATURE_OSD(1),
        .ENABLE_STARTUP_UI (ENABLE_MEDIA),
        .USE_COLOUR_PALETTE (1),
        .ENABLE_PERIOD_OSD (1),.DEMO_FAST_PERIODS(FAST_DEMO),
        .ENABLE_PLAYBACK_OSD (1),
        .EXTERNAL_SPECTRUM (1),
        .ENHANCED_AUDIO_VIS(1),.WAVE_W(384),.WAVE_H(160),.POINT_PX(2),.SAMPLE_STEP(3),
        .EXTERNAL_MAP_PIXELS (ENABLE_RASTER&&ENABLE_MEDIA),
        .NUMBERED_SIX (ENABLE_MEDIA),
        .REMOTE_MAP (1),
        .SCREEN_W          (1280),
        .SCREEN_H          (720),
        .BANNER_SCALE      (BANNER_SCALE),
        .BLINK_HALF_FRAMES (BLINK_HALF_FRAMES),
        .TRANSITION_MODE   (TRANSITION_MODE)
    ) u_smart_terminal_overlay (
        .temperature_status(temperature_video),
        .subtitle_active(subtitle_active),.subtitle_pixel(subtitle_pixel),.subtitle_bar(subtitle_bar),
        .subtitle_x(subtitle_x),.subtitle_y(subtitle_y),.subtitle_show(subtitle_show),
        .clk       (video_clk),
        .rst       (rst_all),
        .i_hs      (overlay_i_hs_q),
        .i_vs      (overlay_i_vs_q),
        .i_de      (overlay_i_de_q),
        .i_rgb     (overlay_i_rgb_q),
        .emergency (emergency_mode),
        .startup_loading(ENABLE_MEDIA && !startup_display_ready),.startup_progress(startup_progress),
        // ---- 创新二：动态校园疏散地图 ----
        // 事件类型（0 火灾 / 1 地震 / 2 实验室事故 / 3 演练），S3 短按在应急期间切换。
        // 慢变寄存器（只在按键那一下变），叠加层直接当组合输入用，不需要握手。
        .emergency_event (emergency_event),
        .load_in_flight (load_in_flight),
        // 载图进度跨界同步后的版本（sd_card_clk -> video_clk 打了两拍）。
        // 叠加层用它决定**何时开始淡出**，取代"用上一张的载图时长预测这一张"。
        .load_nearly_done (load_nearly_done_v2),
        // 拨码开关在叠加层里做两拍同步；慢变信号，不需要额外握手
        .fx_sel    (sw[2:0]),
        .particle_motion(particle_motion),.particle_ready(particle_ready),.particle_code(particle_code),.particle_address(particle_address),
        .interval_selection(period_video),
        .playback_running(auto_play_en),
        .fx_off    (sw[3]),
        .audio_mag (audio_magnitude),
        .audio_sample_valid (audio_valid),
        .audio_sample       (audio_left_data),
        .external_band_valid(external_band_valid),.external_band_data(external_band_data),
        .external_spectrum_live(external_spectrum_live),
        .map_pixels_valid(map_mode),.map_pixels_stale(!net_online),
        .map_live(map_live),.map_scene(map_scene),.map_frame_tick(map_frame_tick),
        .page_index(FEATURE_MASK[4] ? 3'd0 : page_index),
        .brightness(brightness_level),
        .contrast  (contrast_level),
        .palette_bank(palette_bank),.palette_write_enable(palette_write_enable),
        .palette_write_address(palette_write_address),.palette_write_value(palette_write_value),
        .feature_mask(FEATURE_MASK[3:0]),
        // 已同步到 video_clk 的源分辨率（OSD 右上角显示）
        .src_w     (map_mode?16'd640:res_w_v),
        .src_h     (map_mode?16'd480:res_h_v),
        .o_hs      (overlay_hs),
        .o_vs      (overlay_vs),
        .o_de      (overlay_de),
        .o_rgb     (overlay_rgb)
    );

    always @(posedge video_clk or posedge rst_all) begin
        if (rst_all) begin
            overlay_i_hs_q  <= 1'b0;
            overlay_i_vs_q  <= 1'b0;
            overlay_i_de_q  <= 1'b0;
            overlay_i_rgb_q <= 24'd0;
        end
        else begin
            overlay_i_hs_q  <= hs;
            overlay_i_vs_q  <= vs;
            overlay_i_de_q  <= de;
            overlay_i_rgb_q <= display_enable_video ? vout_data_raw : (ENABLE_MEDIA ? 24'h0b1e30 : 24'd0);
        end
    end

    // Diagnostic selector is synchronized and latched only in vertical blank.
    // F: solid #104080. E: deterministic one-pixel frame/line-edge pattern.
    // 0..D: exact original output, including FX-off on 8..D. No new pins.
    wire scan_diag_active,scan_diag_hs,scan_diag_vs,scan_diag_de;
    wire [1:0] scan_diag_mode;
    wire [23:0] scan_diag_rgb;
    scan_diagnostic_mux #(.ENABLE(ENABLE_SCAN_DIAGNOSTIC)) u_scan_diagnostic(
      .clk(video_clk),.rst(rst_all),.switches(sw),
      .i_hs(overlay_hs),.i_vs(overlay_vs),.i_de(overlay_de),.i_rgb(overlay_rgb),
      .active(scan_diag_active),.mode(scan_diag_mode),
      .o_hs(scan_diag_hs),.o_vs(scan_diag_vs),.o_de(scan_diag_de),.o_rgb(scan_diag_rgb));

    // Keep SDRAM, TF and Ethernet alive while only the HDMI output settles
    // or recovers a missing lock. Release on VS, never in an active line.
    hdmi_startup_guard u_hdmi_startup_guard(
        .clk(video_clk),.async_reset(rst_all || !audio_pll_lock),
        .memory_ready(scan_diag_active || Sdr_init_done),.frame_sync(scan_diag_vs),
        .video_locked(led[3]),.image_complete(display_valid_video_2),
        .axis_valid(axis_s_valid),.axis_ready(axis_s_ready),
        .output_reset(hdmi_output_reset),.video_ready(hdmi_video_ready));

    video_rgb_to_axis_720p u_video_rgb_to_axis_720p (
        .I_clk         (video_clk),
        .I_rst         (hdmi_output_reset),
        .I_vs          (scan_diag_vs),
        .I_de          (scan_diag_de),
        .I_rgb         (scan_diag_rgb),
        .O_video_user  (axis_s_user),
        .O_video_valid (axis_s_valid),
        .O_video_last  (axis_s_last),
        .O_video_data  (axis_s_data)
    );

    startup_pulse #(
        .CNT_MAX (20'd100000)
    ) u_startup_pulse (
        .I_clk   (video_clk),
        .I_rst   (hdmi_output_reset),
        .O_pulse (edid_trig)
    );

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("EG"),
        .HTOTAL            (1650),
        .HSA               (40),
        .HFP               (110),
        .HBP               (220),
        .HACTIVE           (1280),
        .VTOTAL            (756),
        .VSA               (5),
        .VFP               (5),
        .VBP               (26),
        .VACTIVE           (720),
        .VIDEO_VIC         (4),
        .VIDEO_TPG         ("Disable"),
        .VIDEO_FORMAT      ("RGB"),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (250)
    ) u_hdmi_1_4b_transmitter_core_wrapper (
        .I_pixel_clk        (video_clk),
        .I_rst              (hdmi_output_reset),
        .I_edid_read_trig   (edid_trig),
        .O_edid_read_valid  (edid_valid),
        .O_edid_read_data   (edid_data),
        .I_axis_s_user      (axis_s_user),
        .I_axis_s_valid     (axis_s_valid),
        .I_axis_s_last      (axis_s_last),
        .I_axis_s_data      (axis_s_data),
        .O_axis_s_ready     (axis_s_ready),
        .I_audio_valid      (audio_valid),
        .I_audio_left_data  (audio_left_data),
        .I_audio_right_data (audio_right_data),
        .I_acr_valid        (acr_valid),
        .I_acr_cts          (acr_cts),
        .I_acr_n            (acr_n),
        .O_video_locked     (led[3]),
        .O_ddc_scl          (HDMI_DDC_SCL),
        .IO_ddc_sda         (HDMI_DDC_SDA),
        .O_ch0_tmds_data    (tmds_ch0_data),
        .O_ch1_tmds_data    (tmds_ch1_data),
        .O_ch2_tmds_data    (tmds_ch2_data),
        .O_clk_tmds_data    (tmds_clk_data)
    );

    hdmi_phy_wrapper #(
        .DEVICE ("EG")
    ) u_hdmi2phy_wrapper (
        .I_pixel_clk        (video_clk),
        .I_serial_clk       (hdmi_5x_clk),
        .I_rst              (hdmi_output_reset),
        .I_tmds_channel_0   (tmds_ch0_data),
        .I_tmds_channel_1   (tmds_ch1_data),
        .I_tmds_channel_2   (tmds_ch2_data),
        .I_tmds_channel_clk (tmds_clk_data),
        .O_tmds_ch0_p       (HDMI_D0_P),
        .O_tmds_ch1_p       (HDMI_D1_P),
        .O_tmds_ch2_p       (HDMI_D2_P),
        .O_tmds_clk_p       (HDMI_CLK_P)
    );

    assign led[0] = emergency_mode;
    assign led[1] = auto_play_en;
    assign led[2] = Sdr_init_done;

endmodule

// SDRAM's synchronous reset must be sampled after its PLL starts delivering
// valid clocks. Assert immediately, release after 16 consecutive clock edges.
// An explicit startup value also covers configuration with locks already high.
module memory_startup_reset (
    input wire clk,
    input wire async_rst,
    output wire rst
);
    reg [15:0] release_pipe = 16'hffff;
    always @(posedge clk or posedge async_rst) begin
        if(async_rst) release_pipe <= 16'hffff;
        else release_pipe <= {release_pipe[14:0], 1'b0};
    end
    assign rst = async_rst | release_pipe[15];
endmodule

// Deterministic configuration-time reset on the free-running 50 MHz reference.
// Hold A media/video and memory startup for 20ms after initial PLL locks. The explicit
// initial state covers rst_n tied high and PLLs already locked at configuration.
// A later Ethernet-only relock keeps immutable display caches, as before.
module board_startup_reset #(parameter integer STABLE_CYCLES=1000000)(
    input ref_clk,rst_n,input [2:0] clock_locks,output reg reset_hold=1'b1);
    localparam CW=$clog2(STABLE_CYCLES)>0?$clog2(STABLE_CYCLES):1;
    reg [CW-1:0] stable_count=0;
    reg [2:0] locks_meta=0,locks_sync=0;
    always @(posedge ref_clk or negedge rst_n)
        if(!rst_n)begin
            reset_hold<=1;stable_count<=0;locks_meta<=0;locks_sync<=0;
        end else begin
            locks_meta<=clock_locks;locks_sync<=locks_meta;
            if(reset_hold)begin
                if(!(&locks_sync))stable_count<=0;
                else if(stable_count==STABLE_CYCLES-1)begin reset_hold<=0;stable_count<=0;end
                else stable_count<=stable_count+1'b1;
            end
        end
endmodule

// The startup request crosses as one held level into the video domain.
// Only the first D input samples it; release reaches media/video logic after
// three local clocks. PLL/key faults still assert immediately. Physical TF
// and original mclk audio keep their independent legacy reset; the SDRAM has
// its own 16-clock release pipe. Never fan a reference-clock reset register
// directly into all unrelated clock domains' reset/recovery pins.
module startup_release_sync #(parameter integer STAGES=3)(input clk,async_fault,startup_hold,output rst);
    reg [STAGES-1:0] release_pipe={STAGES{1'b1}};
    always @(posedge clk or posedge async_fault)
        if(async_fault)release_pipe<={STAGES{1'b1}};
        else release_pipe<={release_pipe[STAGES-2:0],startup_hold};
    assign rst=async_fault | release_pipe[STAGES-1];
endmodule

// Output-only cold-start/relock guard. Never resets memory, TF or Ethernet.
// A core lock alone cannot prove it accepted the fixed-rate input pixels.
// Qualify two complete accepted frames; retry after repeated rejected frames.
// Keep the loading screen and TMDS timing continuous when the first image
// completes. Only an actual output fault can request another output reset.
module hdmi_startup_guard #(
    parameter integer SETTLE_FRAMES=16,UNLOCK_FRAMES=180,
    BAD_FRAMES=8,ACTIVE_PIXELS=1280*720
)(input clk,async_reset,memory_ready,frame_sync,video_locked,image_complete,
  input axis_valid,axis_ready,
  output reg output_reset=1'b1,output wire video_ready);
    localparam MAX_FRAMES=SETTLE_FRAMES>UNLOCK_FRAMES?SETTLE_FRAMES:UNLOCK_FRAMES;
    localparam CW=$clog2(MAX_FRAMES)>0?$clog2(MAX_FRAMES):1;
    localparam BW=$clog2(BAD_FRAMES)>0?$clog2(BAD_FRAMES):1;
    localparam PW=$clog2(ACTIVE_PIXELS+2)>0?$clog2(ACTIVE_PIXELS+2):1;
    reg [CW-1:0] frames;
    reg [BW-1:0] bad_frames;
    reg [1:0] ready_sync,lock_sync,good_frames;
    reg frame_d,transfer_bad;
    reg [PW-1:0] accepted_pixels;
    wire frame_edge=frame_sync&&!frame_d;
    wire clean_frame=accepted_pixels==ACTIVE_PIXELS && !transfer_bad;
    assign video_ready=!output_reset && ready_sync[1] && lock_sync[1] && good_frames==2;
    always @(posedge clk or posedge async_reset)
      if(async_reset)begin
        output_reset<=1;frames<=0;bad_frames<=0;
        ready_sync<=0;lock_sync<=0;frame_d<=0;
      end else begin
        ready_sync<={ready_sync[0],memory_ready};
        lock_sync<={lock_sync[0],video_locked};
        frame_d<=frame_sync;
        if(!ready_sync[1])begin output_reset<=1;frames<=0;bad_frames<=0;end
        else if(frame_edge)begin
          if(output_reset)begin
            if(frames==SETTLE_FRAMES-1)begin output_reset<=0;frames<=0;end
            else frames<=frames+1'b1;
          end else if(lock_sync[1])begin
            frames<=0;
            if(clean_frame)bad_frames<=0;
            else if(bad_frames==BAD_FRAMES-1)begin output_reset<=1;frames<=0;bad_frames<=0;end
            else bad_frames<=bad_frames+1'b1;
          end else begin
            bad_frames<=0;
            if(frames==UNLOCK_FRAMES-1)begin output_reset<=1;frames<=0;end
            else frames<=frames+1'b1;
          end
        end
      end
    always @(posedge clk or posedge async_reset)
      if(async_reset)begin accepted_pixels<=0;transfer_bad<=0;good_frames<=0;end
      else if(output_reset || !ready_sync[1])begin accepted_pixels<=0;transfer_bad<=0;good_frames<=0;end
      else begin
        if(axis_valid)begin
          if(!axis_ready)transfer_bad<=1;
          else if(accepted_pixels<ACTIVE_PIXELS+1)accepted_pixels<=accepted_pixels+1'b1;
        end
        if(frame_edge)begin
          accepted_pixels<=0;transfer_bad<=0;
          if(!lock_sync[1] || !clean_frame)good_frames<=0;
          else if(good_frames!=2)good_frames<=good_frames+1'b1;
        end
        if(!lock_sync[1])good_frames<=0;
      end
endmodule

// Readiness, not a download percentage. The fixed scanout timing supplies a
// complete active area between VS edges. Any missing source row invalidates
// that frame. Arm at VS so a partial first frame cannot count as a good one.
// Two full clean ordinary-image frames qualify the immutable image cache.
// Map mode does not inspect the inactive ordinary-image reader. HDMI relock
// never resets the card/cache; its readiness is independently required.
module startup_display_qualifier(
    input wire clk,rst,image_complete,normal_active,frame_sync,
    input wire pixel_de,pixel_ready,hdmi_ready,
    output reg display_ready
);
    reg frame_d,frame_armed,frame_seen,frame_bad,good_seen,image_healthy;
    wire frame_edge=frame_sync&&!frame_d;
    always @(posedge clk or posedge rst) begin
        if(rst)begin
            frame_d<=0;frame_armed<=0;frame_seen<=0;frame_bad<=0;
            good_seen<=0;image_healthy<=0;display_ready<=0;
        end else begin
            frame_d<=frame_sync;
            if(!hdmi_ready)display_ready<=0;
            if(!image_complete)begin
                frame_armed<=0;frame_seen<=0;frame_bad<=0;
                good_seen<=0;image_healthy<=0;display_ready<=0;
            end else if(!normal_active)begin
                frame_armed<=0;frame_seen<=0;frame_bad<=0;good_seen<=0;
                if(frame_edge)display_ready<=hdmi_ready&&image_healthy;
            end else begin
                if(pixel_de)begin
                    frame_seen<=1;
                    if(!pixel_ready)frame_bad<=1;
                end
                if(frame_edge)begin
                    frame_armed<=1;frame_seen<=0;frame_bad<=0;
                    if(frame_armed)begin
                        if(frame_seen&&!frame_bad)begin
                            good_seen<=1;
                            if(good_seen)image_healthy<=1;
                            display_ready<=hdmi_ready&&(good_seen||image_healthy);
                        end else begin
                            good_seen<=0;image_healthy<=0;display_ready<=0;
                        end
                    end else display_ready<=hdmi_ready&&image_healthy;
                end
            end
        end
    end
endmodule

// Read-only final RGB substitution. HS/VS/DE and the original HDMI/AXIS
// clock, reset/lock policy and serializer remain the same physical path.
// Normal mode is combinationally bit-identical to the input tuple.
module scan_diagnostic_mux #(parameter ENABLE=0)(
 input clk,rst,input [3:0] switches,
 input i_hs,i_vs,i_de,input [23:0] i_rgb,
 output active,output reg [1:0] mode,
 output o_hs,o_vs,o_de,output [23:0] o_rgb);
 reg [3:0] switch_meta,switch_sync;
 reg vs_d,de_d;reg [10:0] next_x;reg [9:0] y;
 wire frame_start=vs_d && !i_vs;
 wire [10:0] x=i_de && !de_d?11'd0:next_x;
 wire [23:0] edge_rgb=x==0?24'hD00000:x==1279?24'h00D000:
   y==0?24'h0000D0:y==719?24'hD0D000:24'h104080;
 assign active=ENABLE && mode!=0;
 assign o_hs=i_hs;assign o_vs=i_vs;assign o_de=i_de;
 assign o_rgb=!active?i_rgb:!i_de?24'd0:mode==1?24'h104080:edge_rgb;
 always @(posedge clk or posedge rst)
  if(rst)begin switch_meta<=0;switch_sync<=0;mode<=0;vs_d<=0;de_d<=0;next_x<=0;y<=0;end
  else begin
   switch_meta<=switches;switch_sync<=switch_meta;vs_d<=i_vs;de_d<=i_de;
   if(frame_start)begin
    mode<=!ENABLE ? 2'd0 : switch_sync==4'hf ? 2'd1 : switch_sync==4'he ? 2'd2 : 2'd0;
    next_x<=0;y<=0;
   end else begin
    if(i_de)next_x<=x+1'b1;else next_x<=0;
    if(!i_de && de_d)y<=y+1'b1;
   end
  end
endmodule
