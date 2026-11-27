`timescale 1ns/1ps

module text_overlay_8x8 #(
    parameter integer SCREEN_W = 640,
    parameter integer SCREEN_H = 480,
    // 底部滚动字幕的字模放大倍数。8x8 字模在 1280x720 上太小，
    // 默认放大 4 倍 -> 每个字符 32x32 像素。必须是 2 的幂。
    parameter integer BANNER_SCALE = 4,
    parameter integer USE_BANNER_ROM = 0,
    parameter integer ENABLE_PERIOD_OSD = 0,
    parameter integer DEMO_FAST_PERIODS = 0,
    parameter integer ENABLE_PLAYBACK_OSD = 0,
    parameter integer ENABLE_STARTUP_UI = 0,
    // 应急警戒框线宽（像素）
    parameter integer BORDER_W = 12,
    // Actual board video clock. Count clock cycles rather than assumed frames.
    parameter integer CLK_FREQ_HZ = 75_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        emergency,
    input wire startup_loading,input wire [8:0] startup_progress,
    input  wire        blink_on,
    input  wire [11:0] x,
    input  wire [11:0] y,
    // 右上角信息栏（18 字符）专用：**早一拍**的坐标，用它在 s2->s3 打一拍，
    // 把整块状态栏的译码 + 字模查找挪出 s3->s4 那条已经很紧的组合锥。
    //
    // 为什么必须打：信息栏从 8 字符加宽到 18 字符之后，status_char 的
    // 选择器变宽，加上后面 font_row（29 个字母 × 7 行）的组合查找，
    // video_clk 域当场出现 2 条负 slack（-0.039 / -0.010 ns）——
    // bilin8 那一版是 +0.114，也就是说这里吃掉了 0.15 ns。
    // 坐标在 (x_pre,y_pre) 上算出的命中，正好在 s3 那一拍与 s3_x/s3_y 对齐
    // （x 每个像素 +1），所以对像素的位置没有任何影响。
    input  wire [11:0] x_pre,
    input  wire [11:0] y_pre,
    input  wire [2:0]  page_index,       // 最多 5 张图，显示 P1..P5
    input  wire [2:0]  brightness,
    input  wire [2:0]  contrast,
    input wire [1:0] interval_selection,
    input wire playback_running,
    input  wire [6:0]  elapsed_seconds,
    input  wire [11:0] scroll_phase,
    input  wire [11:0] scroll_phase_pre,
    input  wire [3:0]  feature_mask,
    // 当前显示中的那张图的**源分辨率**，已在上层格式化成 9 个 ASCII 字符：
    //   [71:64] 最左字符 ... [7:0] 最右字符
    // 内容是 "W 右对齐 4 位 + 'X' + H 右对齐 4 位"，例：
    //   " 640X480" / "1280X720"
    // 格式化（含十进制拆位）放在 smart_terminal_overlay_pipelined 里**打一拍**，
    // 不在这里做 —— 这里每一拍都要算一次像素，不能挂除法。
    input  wire [71:0] res_str,

    output reg  [23:0] text_rgb,
    output reg  [7:0]  text_alpha
);

    localparam integer EMER_CHARS = 9;
    localparam integer EMER_SCALE = 4;
    localparam [11:0] NORMAL_X = 12'd24;
    localparam [11:0] NORMAL_Y = 12'd24;
    localparam [11:0] EMER_X   = (SCREEN_W - (EMER_CHARS * 8 * EMER_SCALE)) / 2;
    localparam [11:0] EMER_Y   = (SCREEN_H - (8 * EMER_SCALE)) / 2;
    // 右上角参数区按 STATUS_SCALE 放大（底部字幕用的是 BANNER_SCALE）。
    // 字模还是 8x8，只是把坐标先换算到"放大的格子"里再取列/行——
    // 和 banner 的做法一致：cell 内偏移 >> log2(SCALE) 之后才是字模列。
    localparam integer STATUS_SCALE = 2;
    // "P1 B4 C4" (8) + 空格 (1) + 分辨率 9 字符 = 18
    localparam integer STATUS_CHARS = 18;
    localparam integer STATUS_CELL  = 8 * STATUS_SCALE;          // 单个字符 16 px
    localparam integer STATUS_W     = STATUS_CHARS * STATUS_CELL; // 整块 128 px
    localparam integer STATUS_H     = 8 * STATUS_SCALE;           // 16 px
    localparam [11:0] STATUS_X = SCREEN_W - STATUS_W - 16;
    localparam [11:0] STATUS_Y = 12'd20;
    localparam [11:0] TIME_X   = 12'd24;
    localparam [11:0] TIME_Y   = 12'd18;
    localparam integer DATE_CHARS = 14;
    localparam integer TIME_CHARS = 8;
    localparam integer TIME_LINE_PITCH = 12;

    localparam integer NORMAL_CHARS = 11;
    localparam integer BANNER_CHARS = 15;

    // 放大后的字模几何
    localparam integer BCELL  = 8 * BANNER_SCALE;      // 单个字符占用的像素宽度
    localparam integer BTEXT_W = BANNER_CHARS * BCELL; // 整条字幕的像素宽度
    localparam [11:0]  BANNER_Y = SCREEN_H - BCELL - 8;

    function [7:0] font_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            case (ch)
                "A": case (row) 0:font_row=8'h18;1:font_row=8'h24;2:font_row=8'h42;3:font_row=8'h7E;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h42;default:font_row=8'h00; endcase
                // ⚠️ "B" 以前**不在字模表里** —— status_char 一直在画 "P1 B4 C4"，
                //    而 'B' 落到 default 分支画成空白，板上实际显示的是 "P1  4 C4"
                //    （亮度的标签整个不见了）。这是补 tb_text_overlay 的信息栏判据时
                //    当场抓出来的：判据要求第 3 格 'B' 必须被点亮，它报 got=0。
                "B": case (row) 0:font_row=8'h7C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h7C;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h7C;default:font_row=8'h00; endcase
                "C": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h40;3:font_row=8'h40;4:font_row=8'h40;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "D": case (row) 0:font_row=8'h78;1:font_row=8'h44;2:font_row=8'h42;3:font_row=8'h42;4:font_row=8'h42;5:font_row=8'h44;6:font_row=8'h78;default:font_row=8'h00; endcase
                "E": case (row) 0:font_row=8'h7E;1:font_row=8'h40;2:font_row=8'h40;3:font_row=8'h7C;4:font_row=8'h40;5:font_row=8'h40;6:font_row=8'h7E;default:font_row=8'h00; endcase
                "F": case (row) 0:font_row=8'h7E;1:font_row=8'h40;2:font_row=8'h40;3:font_row=8'h7C;4:font_row=8'h40;5:font_row=8'h40;6:font_row=8'h40;default:font_row=8'h00; endcase
                "G": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h40;3:font_row=8'h4E;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "H": case (row) 0:font_row=8'h42;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h7E;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h42;default:font_row=8'h00; endcase
                "I": case (row) 0:font_row=8'h7E;1:font_row=8'h18;2:font_row=8'h18;3:font_row=8'h18;4:font_row=8'h18;5:font_row=8'h18;6:font_row=8'h7E;default:font_row=8'h00; endcase
                "L": case (row) 0:font_row=8'h40;1:font_row=8'h40;2:font_row=8'h40;3:font_row=8'h40;4:font_row=8'h40;5:font_row=8'h40;6:font_row=8'h7E;default:font_row=8'h00; endcase
                "M": case (row) 0:font_row=8'h42;1:font_row=8'h66;2:font_row=8'h5A;3:font_row=8'h42;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h42;default:font_row=8'h00; endcase
                "N": case (row) 0:font_row=8'h42;1:font_row=8'h62;2:font_row=8'h52;3:font_row=8'h4A;4:font_row=8'h46;5:font_row=8'h42;6:font_row=8'h42;default:font_row=8'h00; endcase
                "O": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h42;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "P": case (row) 0:font_row=8'h7C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h7C;4:font_row=8'h40;5:font_row=8'h40;6:font_row=8'h40;default:font_row=8'h00; endcase
                "R": case (row) 0:font_row=8'h7C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h7C;4:font_row=8'h48;5:font_row=8'h44;6:font_row=8'h42;default:font_row=8'h00; endcase
                "S": case (row) 0:font_row=8'h3E;1:font_row=8'h40;2:font_row=8'h40;3:font_row=8'h3C;4:font_row=8'h02;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "T": case (row) 0:font_row=8'h7E;1:font_row=8'h18;2:font_row=8'h18;3:font_row=8'h18;4:font_row=8'h18;5:font_row=8'h18;6:font_row=8'h18;default:font_row=8'h00; endcase
                "U": case (row) 0:font_row=8'h42;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h42;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "W": case (row) 0:font_row=8'h42;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h42;4:font_row=8'h5A;5:font_row=8'h66;6:font_row=8'h42;default:font_row=8'h00; endcase
                "X": case (row) 0:font_row=8'h42;1:font_row=8'h24;2:font_row=8'h18;3:font_row=8'h18;4:font_row=8'h24;5:font_row=8'h42;6:font_row=8'h42;default:font_row=8'h00; endcase
                "Y": case (row) 0:font_row=8'h42;1:font_row=8'h42;2:font_row=8'h24;3:font_row=8'h18;4:font_row=8'h18;5:font_row=8'h18;6:font_row=8'h18;default:font_row=8'h00; endcase
                "0": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h46;3:font_row=8'h4A;4:font_row=8'h52;5:font_row=8'h62;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "1": case (row) 0:font_row=8'h18;1:font_row=8'h38;2:font_row=8'h18;3:font_row=8'h18;4:font_row=8'h18;5:font_row=8'h18;6:font_row=8'h7E;default:font_row=8'h00; endcase
                "2": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h02;3:font_row=8'h0C;4:font_row=8'h30;5:font_row=8'h40;6:font_row=8'h7E;default:font_row=8'h00; endcase
                "3": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h02;3:font_row=8'h1C;4:font_row=8'h02;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "4": case (row) 0:font_row=8'h0C;1:font_row=8'h14;2:font_row=8'h24;3:font_row=8'h44;4:font_row=8'h7E;5:font_row=8'h04;6:font_row=8'h04;default:font_row=8'h00; endcase
                "5": case (row) 0:font_row=8'h7E;1:font_row=8'h40;2:font_row=8'h40;3:font_row=8'h7C;4:font_row=8'h02;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "6": case (row) 0:font_row=8'h1C;1:font_row=8'h20;2:font_row=8'h40;3:font_row=8'h7C;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "7": case (row) 0:font_row=8'h7E;1:font_row=8'h02;2:font_row=8'h04;3:font_row=8'h08;4:font_row=8'h10;5:font_row=8'h20;6:font_row=8'h20;default:font_row=8'h00; endcase
                "8": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h3C;4:font_row=8'h42;5:font_row=8'h42;6:font_row=8'h3C;default:font_row=8'h00; endcase
                "9": case (row) 0:font_row=8'h3C;1:font_row=8'h42;2:font_row=8'h42;3:font_row=8'h3E;4:font_row=8'h02;5:font_row=8'h04;6:font_row=8'h38;default:font_row=8'h00; endcase
                ".": case (row) 5,6:font_row=8'h18;default:font_row=8'h00;endcase
                ":": case (row) 2,5:font_row=8'h18;default:font_row=8'h00;endcase
                default: font_row = 8'h00;
            endcase
        end
    endfunction

    function [7:0] digit_char;
        input [3:0] digit;
        begin
            digit_char = 8'h30 + {4'b0, digit};
        end
    endfunction

    function [7:0] normal_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: normal_char = "C";
                4'd1: normal_char = "A";
                4'd2: normal_char = "M";
                4'd3: normal_char = "P";
                4'd4: normal_char = "U";
                4'd5: normal_char = "S";
                4'd6: normal_char = 8'h20;
                4'd7: normal_char = "I";
                4'd8: normal_char = "N";
                4'd9: normal_char = "F";
                default: normal_char = "O";
            endcase
        end
    endfunction

    function [7:0] emergency_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: emergency_char = "E";
                4'd1: emergency_char = "M";
                4'd2: emergency_char = "E";
                4'd3: emergency_char = "R";
                4'd4: emergency_char = "G";
                4'd5: emergency_char = "E";
                4'd6: emergency_char = "N";
                4'd7: emergency_char = "C";
                default: emergency_char = "Y";
            endcase
        end
    endfunction

    function [7:0] status_char;
        input [4:0] idx;
        reg [3:0] page_plus_one;
        begin
            // page_index ∈ 0..4 -> 显示 P1..P5，3 bit 足够（最大 5）
            page_plus_one = {1'b0,page_index} + 4'd1;
            if(ENABLE_STARTUP_UI && startup_loading)begin
                case(idx)
                    0:status_char="L";1:status_char="O";2:status_char="A";
                    3:status_char="D";4:status_char="I";5:status_char="N";
                    6:status_char="G";7:status_char=" ";8:status_char="I";
                    9:status_char="M";10:status_char="A";11:status_char="G";
                    12:status_char="E";default:status_char=" ";
                endcase
            end else case (idx)
                5'd0: status_char = "P";
                5'd1: status_char = digit_char(page_plus_one);
                5'd2: status_char = 8'h20;
                5'd3: status_char = "B";
                5'd4: status_char = digit_char(brightness);
                5'd5: status_char = 8'h20;
                5'd6: status_char = "C";
                5'd7: status_char = digit_char(contrast);
                5'd8: status_char = 8'h20;
                // 分辨率：9 个字符由上层格式化好，这里只做选择
                5'd9:  status_char = res_str[71:64];
                5'd10: status_char = res_str[63:56];
                5'd11: status_char = res_str[55:48];
                5'd12: status_char = res_str[47:40];
                5'd13: status_char = res_str[39:32];
                5'd14: status_char = res_str[31:24];
                5'd15: status_char = res_str[23:16];
                5'd16: status_char = res_str[15:8];
                default: status_char = res_str[7:0];
            endcase
        end
    endfunction

    // Free-running HH:MM:SS elapsed timer. Seconds/minutes use base 60;
    // two hour digits wrap at 100 hours. Only system reset clears the timer.
    // BCD avoids division on the pixel path and consumes no DSP/BRAM.
    reg [26:0] second_cycle_cnt;
    reg [23:0] elapsed_bcd;
    reg [23:0] displayed_bcd;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            second_cycle_cnt <= 27'd0;
            elapsed_bcd <= 24'd0;
        end else if(second_cycle_cnt == CLK_FREQ_HZ-1) begin
            second_cycle_cnt <= 27'd0;
            if(elapsed_bcd[3:0] != 4'd9)
                elapsed_bcd[3:0] <= elapsed_bcd[3:0] + 4'd1;
            else begin
                elapsed_bcd[3:0] <= 4'd0;
                if(elapsed_bcd[7:4] != 4'd5)
                    elapsed_bcd[7:4] <= elapsed_bcd[7:4] + 4'd1;
                else begin
                    elapsed_bcd[7:4] <= 4'd0;
                    if(elapsed_bcd[11:8] != 4'd9)
                        elapsed_bcd[11:8] <= elapsed_bcd[11:8] + 4'd1;
                    else begin
                        elapsed_bcd[11:8] <= 4'd0;
                        if(elapsed_bcd[15:12] != 4'd5)
                            elapsed_bcd[15:12] <= elapsed_bcd[15:12] + 4'd1;
                        else begin
                            elapsed_bcd[15:12] <= 4'd0;
                            if(elapsed_bcd[19:16] != 4'd9)
                                elapsed_bcd[19:16] <= elapsed_bcd[19:16] + 4'd1;
                            else begin
                                elapsed_bcd[19:16] <= 4'd0;
                                elapsed_bcd[23:20] <= (elapsed_bcd[23:20]==4'd9) ?
                                                      4'd0 : elapsed_bcd[23:20]+4'd1;
                            end
                        end
                    end
                end
            end
        end else second_cycle_cnt <= second_cycle_cnt + 27'd1;
    end
    // Snapshot all digits together before the active frame. Counter carries
    // during active video cannot split old/new HH:MM:SS across one frame.
    always @(posedge clk or posedge rst) begin
        if(rst) displayed_bcd <= 24'd0;
        else if(x_pre==12'd0 && y_pre==12'd0) displayed_bcd <= elapsed_bcd;
    end

    // Date remains the fixed display requested for the upper-left corner.
    function [7:0] date_char;
        input [3:0] idx;
        begin
            case (idx)
                0:date_char="2"; 1:date_char="0"; 2:date_char="2"; 3:date_char="6";
                4:date_char="."; 5:date_char="1"; 6:date_char="1"; 7:date_char=".";
                8:date_char="0"; 9:date_char="4"; 10:date_char=" "; 11:date_char="W";
                12:date_char="E"; 13:date_char="D"; default:date_char=" ";
            endcase
        end
    endfunction

    function [7:0] time_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: time_char = digit_char(displayed_bcd[23:20]);
                3'd1: time_char = digit_char(displayed_bcd[19:16]);
                3'd3: time_char = digit_char(displayed_bcd[15:12]);
                3'd4: time_char = digit_char(displayed_bcd[11:8]);
                3'd6: time_char = digit_char(displayed_bcd[7:4]);
                3'd7: time_char = digit_char(displayed_bcd[3:0]);
                3'd2,3'd5: time_char = ":";
                default: time_char = "0";
            endcase
        end
    endfunction

    function [7:0] banner_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  banner_char = "W";
                4'd1:  banner_char = "E";
                4'd2:  banner_char = "L";
                4'd3:  banner_char = "C";
                4'd4:  banner_char = "O";
                4'd5:  banner_char = "M";
                4'd6:  banner_char = "E";
                4'd7:  banner_char = 8'h20;
                4'd8:  banner_char = "H";
                4'd9:  banner_char = "X";
                4'd10: banner_char = "4";
                4'd11: banner_char = "S";
                4'd12: banner_char = "2";
                4'd13: banner_char = "0";
                default: banner_char = 8'h20;
            endcase
        end
    endfunction

    // Only emergency glyph/bar use this geometry; both are gated below.
    // Keep the mode signal outside the font-address arithmetic path.
    wire [11:0] base_x=EMER_X,base_y=EMER_Y;
    wire [11:0] text_width=EMER_CHARS*8*EMER_SCALE,text_height=8*EMER_SCALE;
    wire [11:0] text_right=base_x+text_width,bar_right=text_right+12'd8;
    wire in_bar=(x>=base_x-12'd8)&&(x<bar_right)&&
                (y>=base_y-12'd8)&&(y<base_y+text_height+12'd8);
    wire in_text=(x>=base_x)&&(x<text_right)&&(y>=base_y)&&(y<base_y+text_height);
    wire [11:0] rel_x=x-base_x,rel_y=y-base_y;
    wire [3:0] char_idx=rel_x[8:5];
    wire [2:0] font_col=rel_x[4:2],font_row_idx=rel_y[4:2];
    // 18 个字符 => 需要 5 bit（原来 8 个字符时是 3 bit [6:4]）
    // ---- 信息栏（18 字符）的译码：整块搬到 (x_pre,y_pre) 上做，打一拍 ----
    // [0] = 文字像素（白字） / [1] = 半透明底色带
    // A synchronous bit ROM replaces the serial character -> row -> column
    // lookup. It uses the existing x_pre/y_pre cycle: output latency is unchanged.
    // Bounds reset separately; the ROM read does not need an asynchronous reset.
    reg status_font_memory [0:16383]; /* fehdl force_ram=1, ram_style="bram" */
    integer status_init_ch, status_init_row, status_init_col;
    reg [7:0] status_init_glyph;
    initial begin
        for(status_init_ch=0;status_init_ch<256;status_init_ch=status_init_ch+1)
            for(status_init_row=0;status_init_row<8;status_init_row=status_init_row+1)begin
                status_init_glyph=font_row(status_init_ch[7:0],status_init_row[2:0]);
                for(status_init_col=0;status_init_col<8;status_init_col=status_init_col+1)
                    status_font_memory[status_init_ch*64+status_init_row*8+status_init_col]=
                        status_init_glyph[7-status_init_col];
            end
    end
    wire [11:0] status_rx_pre=x_pre-STATUS_X;
    // Reuse the existing font BRAM port for a second line, leaving all
    // existing B/C/resolution/timestamp positions and glyphs unchanged.
    localparam [11:0] PERIOD_Y = STATUS_Y + 28;
    wire period_line_pre = ENABLE_PERIOD_OSD && (y_pre >= PERIOD_Y);
    wire [11:0] status_ry_pre=period_line_pre ? y_pre-PERIOD_Y : y_pre-STATUS_Y;
    function [7:0] period_char;
     input [4:0] idx;
     begin
      case(idx)
       0: period_char="T";
       1: period_char=DEMO_FAST_PERIODS ? (interval_selection==0 ? "M" : "0") : (interval_selection==2'd2 ? "1" : "0");
       2: period_char=DEMO_FAST_PERIODS ? (interval_selection==0 ? "A" : interval_selection==1 ? "1" : "2") :
                       (interval_selection==2'd2 ? "0" : (interval_selection==2'd1 ? "5" : "3"));
       3: period_char=DEMO_FAST_PERIODS && interval_selection==0 ? "X" : "S";
       5: period_char=ENABLE_PLAYBACK_OSD ? "P" : " ";
       6: period_char=!ENABLE_PLAYBACK_OSD ? " " : playback_running ? "L" : "A";
       7: period_char=!ENABLE_PLAYBACK_OSD ? " " : playback_running ? "A" : "U";
       8: period_char=!ENABLE_PLAYBACK_OSD ? " " : playback_running ? "Y" : "S";
       9: period_char=ENABLE_PLAYBACK_OSD && !playback_running ? "E" : " ";
       default: period_char=" ";
      endcase
     end
    endfunction
    localparam integer PERIOD_W = ENABLE_PLAYBACK_OSD ? 160 : 64;
    wire [7:0] status_ch_pre=period_line_pre ? period_char(status_rx_pre[8:4]) : status_char(status_rx_pre[8:4]);
    reg status_font_bit_r;
    always @(posedge clk)
        status_font_bit_r<=status_font_memory[
            {status_ch_pre,status_ry_pre[3:1],status_rx_pre[3:1]}];

    reg [1:0] status_hit_r;
    always @(posedge clk or posedge rst)begin
        if(rst)status_hit_r<=2'd0;
        else begin
            status_hit_r[0]<=(x_pre>=STATUS_X)&&(x_pre<STATUS_X+STATUS_W)&&
                             (y_pre>=STATUS_Y)&&(y_pre<STATUS_Y+STATUS_H) ||
                (ENABLE_PERIOD_OSD && x_pre>=STATUS_X && x_pre<STATUS_X+PERIOD_W &&
                 y_pre>=PERIOD_Y && y_pre<PERIOD_Y+STATUS_H);
            status_hit_r[1]<=(x_pre>=STATUS_X-10)&&(x_pre<STATUS_X+STATUS_W+10)&&
                             (y_pre>=STATUS_Y-6)&&(y_pre<STATUS_Y+STATUS_H+6) ||
                (ENABLE_PERIOD_OSD && x_pre>=STATUS_X-10 && x_pre<STATUS_X+PERIOD_W+10 &&
                 y_pre>=PERIOD_Y-4 && y_pre<PERIOD_Y+STATUS_H+4);
        end
    end
    wire status_pixel=feature_mask[2]&&!emergency&&status_hit_r[0]&&status_font_bit_r;
    // Like the status bar, decode the expanded timestamp one pixel stage
    // early. Its glyph selection must not extend the alpha-blend path.
    function [1:0] time_hit;
        input [11:0] xi, yi;
        reg [11:0] rx, ry;
        reg [7:0] ch, gl;
        reg first_line, second_line;
        begin
            rx=xi-TIME_X; ry=yi-TIME_Y;
            first_line=(yi>=TIME_Y)&&(yi<TIME_Y+8);
            second_line=(yi>=TIME_Y+TIME_LINE_PITCH)&&(yi<TIME_Y+TIME_LINE_PITCH+8);
            ch=first_line ? date_char(rx[6:3]) : time_char(rx[5:3]);
            if(second_line)ry=yi-(TIME_Y+TIME_LINE_PITCH);
            gl=font_row(ch,ry[2:0]);
            time_hit[0]=(xi>=TIME_X)&&gl[7-rx[2:0]]&&
                ((first_line&&(xi<TIME_X+DATE_CHARS*8))||
                 (second_line&&(xi<TIME_X+TIME_CHARS*8)));
            time_hit[1]=(xi>=TIME_X-4)&&(xi<TIME_X+DATE_CHARS*8+4)&&
                (yi>=TIME_Y-4)&&(yi<TIME_Y+TIME_LINE_PITCH+8+4);
        end
    endfunction
    reg [1:0] time_hit_r;
    always @(posedge clk or posedge rst)begin
        if(rst)time_hit_r<=2'd0;
        else time_hit_r<=time_hit(x_pre,y_pre);
    end
    wire time_pixel=feature_mask[0]&&!emergency&&time_hit_r[0];
    // 滚动字幕：字模按 BANNER_SCALE 放大，
    // 坐标先换算到"放大的字模格"再取字模行/列。
    wire [11:0] banner_cursor = x + scroll_phase;
    wire in_banner_text = (banner_cursor >= SCREEN_W) &&
                          (banner_cursor < (SCREEN_W + BTEXT_W)) &&
                          (y >= BANNER_Y) && (y < (BANNER_Y + BCELL));
    wire [11:0] banner_rel_x  = banner_cursor - SCREEN_W;
    wire [11:0] banner_cell_x = banner_rel_x / BCELL;
    wire [11:0] banner_off_x  = banner_rel_x % BCELL;
    wire [3:0]  banner_idx    = banner_cell_x[3:0];
    wire [2:0]  banner_col    = banner_off_x / BANNER_SCALE;
    wire [2:0]  banner_row    = (y - BANNER_Y) / BANNER_SCALE;
    wire [7:0]  banner_glyph  = font_row(banner_char(banner_idx), banner_row);
    wire banner_pixel;
    generate if(USE_BANNER_ROM)begin: banner_rom
      // Constant banner index -> glyph row -> column becomes one BRAM read.
      // x_pre/y_pre and the next scroll phase are supplied one stage early.
      reg banner_memory [0:1023]; /* fehdl force_ram=1, ram_style="bram" */
      integer ci,ri,co;reg [7:0] gl;
      initial for(ci=0;ci<16;ci=ci+1)for(ri=0;ri<8;ri=ri+1)begin
        gl=font_row(banner_char(ci[3:0]),ri[2:0]);
        for(co=0;co<8;co=co+1)banner_memory[ci*64+ri*8+co]=gl[7-co];
      end
      wire [11:0] cursor_pre=x_pre+scroll_phase_pre;
      wire [11:0] rel_pre=cursor_pre-SCREEN_W;
      wire [11:0] cell_pre=rel_pre/BCELL;
      wire [11:0] col_pre=(rel_pre%BCELL)/BANNER_SCALE;
      wire [11:0] row_pre=(y_pre-BANNER_Y)/BANNER_SCALE;
      reg pixel_r,hit_r;
      always @(posedge clk)begin
        pixel_r<=banner_memory[{cell_pre[3:0],row_pre[2:0],col_pre[2:0]}];
        hit_r<=(cursor_pre>=SCREEN_W)&&(cursor_pre<SCREEN_W+BTEXT_W)&&
               (y_pre>=BANNER_Y)&&(y_pre<BANNER_Y+BCELL);
      end
      assign banner_pixel=feature_mask[0]&&!emergency&&hit_r&&pixel_r;
    end else begin: banner_compatibility
      assign banner_pixel=feature_mask[0]&&!emergency&&in_banner_text&&banner_glyph[7-banner_col];
    end endgenerate
    wire in_banner_bar = (y >= (BANNER_Y - 6)) && (y < (BANNER_Y + BCELL + 6));
    wire time_bar_visible   = feature_mask[0] && !emergency && time_hit_r[1];
    wire banner_bar_visible = feature_mask[0] && !emergency && in_banner_bar;
    wire status_bar_visible = feature_mask[2] && !emergency && status_hit_r[1];
    // Reuse the existing text-compositor stage: no new font ROM, DSP or
    // picture buffer. Progress is actual received data, not elapsed time.
    localparam integer LOAD_X=(SCREEN_W-400)/2;
    localparam integer LOAD_Y=SCREEN_H/2+24;
    wire startup_on=ENABLE_STARTUP_UI && startup_loading;
    reg startup_bar_r,startup_fill_r;
    wire [11:0] loading_dx=x_pre-LOAD_X;
    always @(posedge clk or posedge rst)
      if(rst)begin startup_bar_r<=0;startup_fill_r<=0;end
      else begin
        startup_bar_r<=startup_on && x_pre>=LOAD_X && x_pre<LOAD_X+400 && y_pre>=LOAD_Y && y_pre<LOAD_Y+12;
        startup_fill_r<=loading_dx<{3'd0,startup_progress};
      end

    // 应急警戒框：由 blink_on 门控，实现红色边框闪烁
    wire emergency_border =
        emergency && blink_on &&
        ((x < BORDER_W) || (x >= (SCREEN_W - BORDER_W)) ||
         (y < BORDER_W) || (y >= (SCREEN_H - BORDER_W)));

    wire [7:0] current_char = emergency_char(char_idx);
    wire [7:0] glyph = font_row(current_char, font_row_idx);
    wire glyph_pixel = emergency && in_text && glyph[7-font_col];

    always @(*) begin
        if (emergency_border) begin
            text_rgb   = 24'hFF2020;
            text_alpha = 8'd255;
        end
        else if(startup_bar_r)begin
            text_rgb=startup_fill_r?24'h31d8cb:24'h203a52;
            text_alpha=8'd255;
        end
        else if (glyph_pixel || status_pixel || time_pixel || banner_pixel) begin
            text_rgb   = 24'hFFFFFF;
            text_alpha = 8'd255;
        end
        else if ((emergency && in_bar) || status_bar_visible ||
                 time_bar_visible || banner_bar_visible) begin
            if (emergency) begin
                text_rgb   = 24'hB00000;
                text_alpha = 8'd220;
            end
            else begin
                text_rgb   = 24'h12385A;
                text_alpha = 8'd180;
            end
        end
        else if(startup_on)begin
            // Opaque loading page: never expose an incomplete image or the
            // photo-transition black mask while the startup checks run.
            text_rgb   = 24'h08182C;
            text_alpha = 8'd255;
        end
        else begin
            text_rgb   = 24'h000000;
            text_alpha = 8'd0;
        end
    end

endmodule
