`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// audio_fft -- 音频频谱分析（Goertzel 选频 DFT，赛题扩展要求⑤）
//
// 逐样本对 P_BINS 个目标频点做二阶递归，窗满后串行输出各频点功率：
//     coef  = 2*cos(2*pi*k/N)         定点 Q14
//     s     = x + ((coef*s1)>>14) - s2 ;  s2 <= s1 ; s1 <= s
//     power = s1^2 + s2^2 - ((coef*s1)>>14)*s2
//
// 架构说明（很重要）：
//   共享一个 MAC，每来一个音频样本只更新 bin 指向的那一个频点，然后
//   bin 自增轮转。因此每个频点实际只看到 1/P_BINS 的样本，它看到的
//   等效采样率是 fs/P_BINS = 6000 Hz（P_BINS=8），系数表按此速率计算。
//   好处是只需一个乘法器；代价是可检测上限被限制在
//   (fs/P_BINS)/2 = 3000 Hz，对本工程足够：正常模式音阶 261~523 Hz，
//   应急模式报警音 800 / 1200 Hz，全部落在范围内。
//   Legacy P_BINS=8 uses the original 200..1400-Hz constants.
//   Production P_BINS=12 uses Fs/12=4000-Hz constants for the eight
//   normal notes plus 800/1000/1200/1600 Hz. The 64-sample per-bin
//   window is unchanged; twelve-bin sets span 768 PCM samples (~16 ms).
//   频率分辨率 = 6000/P_WIN = 93.75 Hz（P_WIN=64，见下面 win_coef）。
//
// 相对 hw/rtl/audio_fft.v 的修改：
//   1. 系数改为预计算常量（原来用 initial + $rtoi/$cos，不可综合）；
//   2. 频点表重做。原表按 48 kHz 直接算 k，与本架构 bin 的实际采样率
//      不匹配，且最低频点在 1125 Hz，覆盖不到本工程的音阶。
//
// 流水设计（改的时候别退回去）：
//   累加级 s1[bin] -> 乘法 -> 移位 -> 加法 -> 写回 s1[bin] 串在一拍里
//   实测 19.4 ns，预算只有 13.3 ns（75 MHz），会连锁出两千多个违例端点。
//   所以累加拆成三级（捕获 / 乘法 / 写回），输出级拆成四级。样本间隔
//   在 48 kHz 下约 1562 拍，加流水完全不影响功能。
//   **加窗那个乘法器故意放在寄存器前面**，就是为了不把这条路径再拉长。
//
// 四个坑（改动时注意）：
//   a. 取高位段必须用算术右移 `s1 >>> 12`，不能写位选 `s1[27:12]`：
//      位选会丢掉负数的符号扩展，值完全不对。
//   b. 功率式在非共振频点会算出负值，直接位选会得到接近满量程的假大值
//      （表现为低频段整片饱和），所以负功率要钳到 0。
//   c. 输出必须等 s1_hi_r/s2_hi_r 就位后再取，否则 O_band 报的是当前
//      频点、O_mag 却是上一个频点的功率，峰值会整体偏一个频点。
//   d. **每个窗末尾必须清 s1/s2**（Goertzel 的常规做法）。递推式临界稳定，
//      不清的话状态跨窗跨音一直累积，音阶里 440/523 Hz 的峰值会跑到 281 Hz。
//   e. **s1_hi_r/s2_hi_r 必须是 18 位**，实测 s1 能到 1.68e8，
//      s1>>>12 = 41119 超出 16 位有符号的 32767，会翻成负数。
//      四条都在 tb_audio_bars_scale 里有对应断言。
// ---------------------------------------------------------------------------
module audio_fft #(
// ★ 2026-09-29：16 -> 8 频点。
//   16 频点版占 2100 个 LUT，把器件顶到 4580/4900 mslices（93.5%）：默认布局、
//   换布局策略、打开布线器 multi-try 三条路都因拥塞布线失败（PHY-8155/RUN-8102）。
//   成本大头是状态寄存器（2 × P_BINS × 32 位），减半后省约 1000 LUT，器件回到
//   85% 左右即可布通。代价：频谱柱 16 根 -> 8 根（覆盖 200~1400 Hz，正常音阶
//   264~608 Hz、报警音 803 Hz 仍在范围内），下面 8 点系数表已按新的等效采样率
//   fs/P_BINS = 6000 Hz 重算。
parameter P_BINS = 8,
    // ⚠️ 只能取 64（win_coef 表是 64 项）。改它必须同时改那张表。
    // 为什么是 64 而不是 256，见下面 win_coef 上方的说明。
    parameter P_WIN  = 64
) (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [23:0] I_audio,
    input  wire               I_audio_valid,

    output reg                O_band_valid,
    output reg  [4:0]         O_band,
    output reg  [15:0]        O_mag
);

    // ---- Q14 系数表：round(2*cos(2*pi*f/6000) * 16384) ----
    function signed [16:0] coef_of_bin;
        input [3:0] idx;
        begin
            if(P_BINS == 12)begin
                case(idx)
                    4'd0: coef_of_bin = 17'sd30040;  // 261.63 Hz
                    4'd1: coef_of_bin = 17'sd29343;  // 293.66 Hz
                    4'd2: coef_of_bin = 17'sd28473;  // 329.63 Hz
                    4'd3: coef_of_bin = 17'sd27960;  // 349.23 Hz
                    4'd4: coef_of_bin = 17'sd26750;  // 392.00 Hz
                    4'd5: coef_of_bin = 17'sd25248;  // 440.00 Hz
                    4'd6: coef_of_bin = 17'sd23392;  // 493.88 Hz
                    4'd7: coef_of_bin = 17'sd22309;  // 523.25 Hz
                    4'd8: coef_of_bin = 17'sd10126;  // 800 Hz
                    4'd9: coef_of_bin = 17'sd0;      // 1000 Hz
                    4'd10: coef_of_bin = -17'sd10126;// 1200 Hz
                    default: coef_of_bin = -17'sd26510; // 1600 Hz
                endcase
            end else begin
            case (idx)
        4'd0 : coef_of_bin = 17'sd32052;   //  200.0 Hz
        4'd1 : coef_of_bin = 17'sd31523;   //  264.1 Hz
        4'd2 : coef_of_bin = 17'sd30607;   //  348.7 Hz
        4'd3 : coef_of_bin = 17'sd29031;   //  460.5 Hz
        4'd4 : coef_of_bin = 17'sd26346;   //  608.1 Hz
        4'd5 : coef_of_bin = 17'sd21852;   //  802.9 Hz
        4'd6 : coef_of_bin = 17'sd14563;   // 1060.2 Hz
        default: coef_of_bin = 17'sd3425;  // 1400.0 Hz
            endcase
            end
        end
    endfunction

    // 输入幅度 2^21（tone 的 AMP=2000000）、窗长 64 时，实测 s 的峰值约
    // 1.7e8（tb_audio_bars_scale 的探针给的 max|s1|）。
    reg signed [31:0] s1 [0:P_BINS-1];
    reg signed [31:0] s2 [0:P_BINS-1];

    reg [3:0] bin;
    reg [8:0] win_cnt;
    reg       phase;         // 0 = 累加，1 = 输出
    reg [4:0] obin;
    reg [6:0] out_cnt;       // 每频点 4 拍，8 频点共 32 拍


    // ---------------------------------------------------------------------
    // 加窗（Hamming，窗长 P_WIN）—— 为什么必须加、为什么窗长必须缩短
    //
    // 这两件事是同一个问题：频点是**对数分布**（187~1394 Hz），而 DFT 的
    // 分辨率是线性的（fs_dec/N）。N 越大，分辨率越细，低频那几个频点
    // （彼此只差 35~40 Hz）相对于分辨率就越"远"——矩形窗在**整数个
    // DFT bin** 处响应为零，于是音阶里总有几个音正好落在零点上，
    // 测出来的功率比别的音低 20 dB 以上。屏幕上就是"柱子忽高忽低乱跳"。
    //
    // 实测（tb_audio_bars_scale + doc/spectrum_sweep.py，判据是
    // "同响度的 8 个音，峰值柱功率的 max/min"）：
    //     N=256 无窗（改之前）  24.4 dB   ← 就是上板看到的乱跳
    //     N=256 + Hamming       31.7 dB   ← 加窗救不了，分辨率不匹配
    //     N=64  + Hamming        2.4 dB   ← 本版
    //     N=32  + Hamming        1.0 dB   （峰值只剩 3~4 根柱子，选择性差）
    // N=64 同时兼顾柱高一致性（2.4 dB）与选择性（峰值 6 dB 内约 2 根柱子）。
    //
    // 第 k 个轮转用的窗系数对**所有 bin 都一样** —— 这正是这套 "bin 轮转"
    // 架构能只花一个乘法器就加窗的原因：每个 bin 的第 k 个样本都出现在
    // win_cnt==k 那一拍。
    // ---------------------------------------------------------------------
    function [7:0] win_coef;
        input [5:0] k;
        begin
            case (k)
                6'd0 : win_coef = 8'd 20; 6'd1 : win_coef = 8'd 21; 6'd2 : win_coef = 8'd 23; 6'd3 : win_coef = 8'd 25;
                6'd4 : win_coef = 8'd 29; 6'd5 : win_coef = 8'd 34; 6'd6 : win_coef = 8'd 40; 6'd7 : win_coef = 8'd 47;
                6'd8 : win_coef = 8'd 55; 6'd9 : win_coef = 8'd 63; 6'd10: win_coef = 8'd 73; 6'd11: win_coef = 8'd 82;
                6'd12: win_coef = 8'd 93; 6'd13: win_coef = 8'd104; 6'd14: win_coef = 8'd115; 6'd15: win_coef = 8'd126;
                6'd16: win_coef = 8'd138; 6'd17: win_coef = 8'd149; 6'd18: win_coef = 8'd161; 6'd19: win_coef = 8'd172;
                6'd20: win_coef = 8'd183; 6'd21: win_coef = 8'd193; 6'd22: win_coef = 8'd203; 6'd23: win_coef = 8'd212;
                6'd24: win_coef = 8'd221; 6'd25: win_coef = 8'd228; 6'd26: win_coef = 8'd235; 6'd27: win_coef = 8'd241;
                6'd28: win_coef = 8'd246; 6'd29: win_coef = 8'd250; 6'd30: win_coef = 8'd253; 6'd31: win_coef = 8'd254;
                6'd32: win_coef = 8'd255; 6'd33: win_coef = 8'd254; 6'd34: win_coef = 8'd253; 6'd35: win_coef = 8'd250;
                6'd36: win_coef = 8'd246; 6'd37: win_coef = 8'd241; 6'd38: win_coef = 8'd235; 6'd39: win_coef = 8'd228;
                6'd40: win_coef = 8'd221; 6'd41: win_coef = 8'd212; 6'd42: win_coef = 8'd203; 6'd43: win_coef = 8'd193;
                6'd44: win_coef = 8'd183; 6'd45: win_coef = 8'd172; 6'd46: win_coef = 8'd161; 6'd47: win_coef = 8'd149;
                6'd48: win_coef = 8'd138; 6'd49: win_coef = 8'd126; 6'd50: win_coef = 8'd115; 6'd51: win_coef = 8'd104;
                6'd52: win_coef = 8'd 93; 6'd53: win_coef = 8'd 82; 6'd54: win_coef = 8'd 73; 6'd55: win_coef = 8'd 63;
                6'd56: win_coef = 8'd 55; 6'd57: win_coef = 8'd 47; 6'd58: win_coef = 8'd 40; 6'd59: win_coef = 8'd 34;
                6'd60: win_coef = 8'd 29; 6'd61: win_coef = 8'd 25; 6'd62: win_coef = 8'd 23; 6'd63: win_coef = 8'd 21;
            endcase
        end
    endfunction

    // 加窗乘法单独注册，随后捕获递推状态，避免与 MAC 乘法串联。
    wire signed [32:0] xs_prod = $signed(I_audio) * $signed({1'b0, win_coef(win_cnt[5:0])});
    wire signed [25:0] xs_win  = xs_prod >>> 7;      // 归一化增益 0..1

    reg signed [25:0] xs_wr;
    reg               step_r;

    always @(posedge clk) begin
        if (rst) begin
            xs_wr  <= 26'sd0;
            step_r <= 1'b0;
        end
        else begin
            xs_wr  <= xs_win;
            step_r <= I_audio_valid && !phase;
        end
    end

    // 累加整体比 I_audio_valid 晚一拍（因为样本要先过加窗寄存器）。
    // phase 在流水写回时才翻转；本模块用于稀疏的 48 kHz 输入。
    wire accum_step = step_r && !phase;

    // 捕获旧 s1/s2 后分别完成乘法与写回，保持定点截断和递推顺序。
    wire signed [16:0] coef_now = coef_of_bin(bin);
    wire signed [31:0] s1_now   = s1[bin];

    // Capture, multiply, then retire. Audio samples are separated by over
    // 1500 pixel clocks; keep the bin fixed until the captured sample retires.
    reg [1:0] accum_valid;
    reg signed [16:0] accum_coef;
    reg signed [31:0] accum_s1, accum_s2;
    reg signed [25:0] accum_x;
    reg signed [48:0] accum_prod;
    wire signed [34:0] accum_mac = accum_prod >>> 14;
    wire signed [35:0] accum_x_ext = {{10{accum_x[25]}}, accum_x};
    wire signed [39:0] accum_result = accum_x_ext + accum_mac - accum_s2;
    always @(posedge clk) begin
        if (rst) begin
            accum_valid <= 2'b00;
            accum_coef <= 17'sd0;
            accum_s1 <= 32'sd0;
            accum_s2 <= 32'sd0;
            accum_x <= 26'sd0;
            accum_prod <= 49'sd0;
        end else begin
            accum_valid <= {accum_valid[0], accum_step};
            if (accum_step) begin
                accum_coef <= coef_now;
                accum_s1 <= s1_now;
                accum_s2 <= s2[bin];
                accum_x <= xs_wr;
            end
            if (accum_valid[0])
                accum_prod <= accum_coef * accum_s1;
        end
    end

    wire last_bin = (bin == P_BINS - 1);
    wire last_win = (win_cnt == P_WIN - 1);

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            bin           <= 4'd0;
            win_cnt       <= 9'd0;
            phase   <= 1'b0;
            obin    <= 5'd0;
            out_cnt <= 7'd0;
            for (i = 0; i < P_BINS; i = i + 1) begin
                s1[i] <= 32'sd0;
                s2[i] <= 32'sd0;
            end
        end
        else if (!phase) begin
            if (accum_valid[1]) begin
                s1[bin] <= accum_result[31:0];
                s2[bin] <= accum_s1;
                if (last_bin) begin
                    bin <= 4'd0;
                    if (last_win) begin
                        win_cnt <= 9'd0;
                        phase   <= 1'b1;
                        obin    <= 5'd0;
                        out_cnt <= 7'd0;
                    end
                    else begin
                        win_cnt <= win_cnt + 9'd1;
                    end
                end
                else begin
                    bin <= bin + 4'd1;
                end
            end
        end
        else begin
            // ---------- 输出阶段：4 拍一个频点 ----------
            if (out_cnt == (4 * P_BINS - 1)) begin
                phase   <= 1'b0;
                out_cnt <= 7'd0;
                // ⚠️ 每个窗末尾必须把 s1/s2 清零，这是 Goertzel 的常规做法，
                // 不是可选项。递推式 s = x + coef*s1 - s2 在 |coef| < 2 时
                // 极点**正好落在单位圆上**（临界稳定），自由响应永不衰减 ——
                // 不清的话状态会跨窗、跨音一直累积，等效于对整段历史做
                // 无窗 DFT：幅度无界增长并且一直"记得"上一个音。
                //
                // 实测（tb_audio_bars_scale，全程不复位 = 板上真实情况）：
                //   不清零：A4 440Hz 和 C5 523Hz 的峰值都落在 **bin3(281Hz)**，
                //           峰值柱序列 2→3→3→3→4→3→4→3，来回跳；
                //   清零后：峰值柱 2→3→4→5→6→7→8，单调右移。
                // 清零点选在这里是因为最后一个频点的功率已经在 out_cnt=4k+3
                // 那拍打出去了（cap 发生在 4k），不会丢数据。
                for (i = 0; i < P_BINS; i = i + 1) begin
                    s1[i] <= 32'sd0;
                    s2[i] <= 32'sd0;
                end
            end
            else begin
                out_cnt <= out_cnt + 7'd1;
                if (out_cnt[1:0] == 2'd0)
                    obin <= obin + 5'd1;
            end
        end
    end

    // ---- 输出流水：每频点 4 拍，每拍最多一级乘法 ----
    //
    // ⚠️ s1_hi_r/s2_hi_r 是 **18 位**，不是 16 位。
    // 原版写成 signed [15:0]，而实测 s1 最大到 1.68e8（音阶里 330/440 Hz 那几个
    // 正好压在频点上的音）⇒ s1>>>12 = 41119 > 32767，**翻成负数**，
    // 功率整条算错。tb_audio_bars_scale 的探针会直接报
    // "s1_hi_r 溢出 2 次"。放宽到 18 位后上限 131071，留 3 倍余量。
    reg signed [16:0] coef_r;
    reg signed [17:0] s1_hi_r, s2_hi_r;
    reg [4:0]         obin_h;

    reg signed [32:0] m_hi_r;
    reg signed [35:0] sq1_r, sq2_r;   // s1_hi^2 <= 2^34，16 位老宽度会截断
    reg signed [36:0] cr_r;           // m_hi * s2_hi <= 2^35
    reg signed [36:0] ssum_r;         // sq1 + sq2 <= 2^35

    wire cap_p   = phase && (out_cnt[1:0] == 2'd0);
    wire calc1_p = phase && (out_cnt[1:0] == 2'd1);
    wire calc2_p = phase && (out_cnt[1:0] == 2'd2);
    wire out_p   = phase && (out_cnt[1:0] == 2'd3);

    always @(posedge clk) begin
        if (rst) begin
            coef_r  <= 17'sd0;
            s1_hi_r <= 16'sd0;
            s2_hi_r <= 16'sd0;
            obin_h  <= 5'd0;
            m_hi_r  <= 33'sd0;
            sq1_r   <= 34'sd0;
            sq2_r   <= 34'sd0;
            cr_r    <= 34'sd0;
            ssum_r  <= 35'sd0;
        end
        else begin
            // 拍 0：取本频点最后一个窗之后的 s1/s2 与系数
            if (cap_p) begin
                s1_hi_r <= s1[obin] >>> 12;
                s2_hi_r <= s2[obin] >>> 12;
                coef_r  <= coef_of_bin(obin[3:0]);
                obin_h  <= obin;
            end

            // 拍 1：coef*s1 与两个平方
            if (calc1_p) begin
                m_hi_r <= (coef_r * s1_hi_r) >>> 14;
                sq1_r  <= s1_hi_r * s1_hi_r;
                sq2_r  <= s2_hi_r * s2_hi_r;
            end

            // 拍 2：第三项与平方和
            if (calc2_p) begin
                cr_r   <= m_hi_r * s2_hi_r;
                ssum_r <= sq1_r + sq2_r;
            end
        end
    end

    // 拍 3：三项都来自寄存器，这里只剩一次减法和取位
    wire signed [37:0] pw = ssum_r - cr_r;

    // 原来直接写 pw[27:12]，高位没有处理 —— 值一旦超过 2^28 就**按 2^16 回绕**
    // （41119 那种大值会算出一个看着"正常"的假小值），这正是柱高忽高忽低
    // 忽满格的来源之一。改成显式饱和：超过 2^28 直接给满量程 0xFFFF。
    wire        pw_neg  = pw[37];
    wire        pw_sat  = |pw[36:28];
    wire [15:0] mag_now = pw_neg ? 16'd0 : (pw_sat ? 16'hFFFF : pw[27:12]);

    always @(posedge clk) begin
        if (rst) begin
            O_band_valid <= 1'b0;
            O_band       <= 5'd0;
            O_mag        <= 16'd0;
        end
        else begin
            O_band_valid <= out_p;
            if (out_p) begin
                O_band <= obin_h;
                O_mag  <= mag_now;
            end
        end
    end

endmodule
