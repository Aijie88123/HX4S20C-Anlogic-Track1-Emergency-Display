`timescale 1ns/1ps

module text_overlay_8x8 #(
    parameter integer SCREEN_W = 640,
    parameter integer SCREEN_H = 480,
    // 底部滚动字幕的字模放大倍数。8x8 字模在 1280x720 上太小，
    // 默认放大 4 倍 -> 每个字符 32x32 像素。必须是 2 的幂。
    parameter integer BANNER_SCALE = 4,
    parameter integer USE_BANNER_ROM = 0,
    parameter integer ENABLE_SUBTITLE = 0,
    parameter integer ENABLE_TEMPERATURE_OSD = 0,
    parameter integer PIPELINED_STATUS_CHAR = 0,
    parameter integer ENABLE_PERIOD_OSD = 0,
    parameter integer DEMO_FAST_PERIODS = 0,
    parameter integer ENABLE_PLAYBACK_OSD = 0,
    parameter integer ENABLE_STARTUP_UI = 0,
    // 应急警戒框线宽（像素）
    parameter integer BORDER_W = 12,
    // Deprecated interface parameter; retained only for old reference users.
    // No date/time counter or display is generated in this module.
    parameter integer CLK_FREQ_HZ = 75_000_000
) (
    input wire [24:0] temperature_status,
    input  wire        clk,
    input  wire        rst,
    input  wire        emergency,
    input wire custom_active,custom_pixel,custom_bar,
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
    // One stage before x_pre/y_pre, for character selection only.
    input wire [11:0] x_early,y_early,
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
    localparam [11:0] TEMP_X = 12'd24;
    localparam [11:0] TEMP_Y = 12'd18;

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
                "K": case(row) 0:font_row=8'h42;1:font_row=8'h44;2:font_row=8'h48;3:font_row=8'h70;4:font_row=8'h48;5:font_row=8'h44;6:font_row=8'h42;default:font_row=0;endcase
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
                "-": case(row) 3:font_row=8'h7e;default:font_row=8'h00;endcase
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

    // One frame snapshot. Integer BCD uses the unused upper font ROM before the first
    // temperature pixel at y18; digits and status then remain immutable.
    localparam integer TEMP_CHARS=16;
    reg [11:0] temperature_integer;
    reg temperature_integer_pending,temperature_integer_hundreds;
    wire [7:0] temperature_integer_byte;
    localparam USE_NATIVE_FONT=(ENABLE_SUBTITLE || ENABLE_TEMPERATURE_OSD) && SCREEN_W>=640;
    function [11:0] temperature_integer_direct;
      input [6:0] value;
      begin temperature_integer_direct=((value/100)<<8)|(((value%100)/10)<<4)|(value%10);end
    endfunction
    reg [3:0] temperature_fraction_bits;
    reg temperature_negative,temperature_connected,temperature_valid,temperature_warning,temperature_alarm;
    reg [2:0] temperature_fault;
    reg [3:0] temperature_state_id;
    wire [10:0] temperature_magnitude=temperature_status[15]?~temperature_status[10:0]+11'd1:temperature_status[10:0];
    function [7:0] temperature_fraction_bcd;
      input [3:0] fraction;
      begin case(fraction)
       0:temperature_fraction_bcd=8'h00;1:temperature_fraction_bcd=8'h06;
       2:temperature_fraction_bcd=8'h13;3:temperature_fraction_bcd=8'h19;
       4:temperature_fraction_bcd=8'h25;5:temperature_fraction_bcd=8'h31;
       6:temperature_fraction_bcd=8'h38;7:temperature_fraction_bcd=8'h44;
       8:temperature_fraction_bcd=8'h50;9:temperature_fraction_bcd=8'h56;
       10:temperature_fraction_bcd=8'h63;11:temperature_fraction_bcd=8'h69;
       12:temperature_fraction_bcd=8'h75;13:temperature_fraction_bcd=8'h81;
       14:temperature_fraction_bcd=8'h88;default:temperature_fraction_bcd=8'h94;
      endcase end
    endfunction
    wire [7:0] temperature_fraction=temperature_fraction_bcd(temperature_fraction_bits);
    function [3:0] decode_temperature_state;
      input [24:0] value;
      begin
       if(!value[24])decode_temperature_state=0;
       else if(value[20])decode_temperature_state=value[23]&&value[22]?1:2;
       else if(!(value[23]&&value[22]))case(value[18:16])
        1:decode_temperature_state=5;2:decode_temperature_state=6;3:decode_temperature_state=7;
        4:decode_temperature_state=8;5:decode_temperature_state=9;6:decode_temperature_state=10;
        default:decode_temperature_state=11;
       endcase
       else decode_temperature_state=value[21]?3:4;
      end
    endfunction
    generate if(ENABLE_TEMPERATURE_OSD)begin: temperature_frame_formatter
      always @(posedge clk or posedge rst)
       if(rst)begin
        temperature_integer<=0;temperature_integer_pending<=0;temperature_integer_hundreds<=0;
        temperature_fraction_bits<=0;temperature_negative<=0;temperature_connected<=0;temperature_valid<=0;
        temperature_warning<=0;temperature_alarm<=0;temperature_fault<=7;temperature_state_id<=0;
       end else if(x_pre==0 && y_pre==0)begin
        temperature_integer_pending<=USE_NATIVE_FONT;
        temperature_integer_hundreds<=temperature_magnitude[10:4]>=7'd100;
        if(!USE_NATIVE_FONT)temperature_integer<=temperature_integer_direct(temperature_magnitude[10:4]);
        temperature_fraction_bits<=temperature_magnitude[3:0];
        temperature_negative<=temperature_status[15];temperature_connected<=temperature_status[24];
        temperature_valid<=temperature_status[24]&&temperature_status[23]&&temperature_status[22];
        temperature_warning<=temperature_status[21];temperature_alarm<=temperature_status[20];
        temperature_fault<=temperature_status[18:16];temperature_state_id<=decode_temperature_state(temperature_status);
       end else if(temperature_integer_pending)begin
        temperature_integer<={3'd0,temperature_integer_hundreds,temperature_integer_byte};
        temperature_integer_pending<=0;
       end
    end endgenerate
    function [7:0] temperature_char;
      input [3:0] idx;
      begin case(idx)
       0:temperature_char="T";1:temperature_char="E";2:temperature_char="M";3:temperature_char="P";
       5:temperature_char=!temperature_valid || temperature_negative?"-":" ";
       6:temperature_char=!temperature_valid?"-":temperature_integer[11:8]==0?" ":digit_char(temperature_integer[11:8]);
       7:temperature_char=!temperature_valid?"-":temperature_integer[11:4]==0?" ":digit_char(temperature_integer[7:4]);
       8:temperature_char=!temperature_valid?"-":digit_char(temperature_integer[3:0]);
       9:temperature_char=".";
       10:temperature_char=!temperature_valid?"-":digit_char(temperature_fraction[7:4]);
       11:temperature_char=!temperature_valid?"-":digit_char(temperature_fraction[3:0]);
       12:temperature_char="C";
       14:temperature_char=temperature_state_char(0);
       15:temperature_char=temperature_state_char(1);
       default:temperature_char=" ";
      endcase end
    endfunction
    // A sparse (state,index) character ROM avoids a wide string multiplexer.
    function [7:0] temperature_state_char;
      input [3:0] idx;
      begin
       if(idx==0)case(temperature_state_id)
        0:temperature_state_char="-";1,2:temperature_state_char="A";
        3:temperature_state_char="H";4:temperature_state_char="O";
        default:temperature_state_char="E";
       endcase
       else if(idx==1)case(temperature_state_id)
        0:temperature_state_char="-";1:temperature_state_char="L";
        2:temperature_state_char=digit_char({1'b0,temperature_fault});
        3:temperature_state_char="I";4:temperature_state_char="K";
        5:temperature_state_char="1";6:temperature_state_char="2";7:temperature_state_char="3";
        8:temperature_state_char="4";9:temperature_state_char="5";10:temperature_state_char="6";
        default:temperature_state_char="7";
       endcase
       else temperature_state_char=" ";
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
       1: period_char=DEMO_FAST_PERIODS ? "0" : (interval_selection==2'd2 ? "1" : "0");
       2: period_char=DEMO_FAST_PERIODS ? (interval_selection==0 ? "3" : interval_selection==1 ? "5" : "8") :
                       (interval_selection==2'd2 ? "0" : (interval_selection==2'd1 ? "5" : "3"));
       3: period_char="S";
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
    // Split coordinate -> character -> BRAM address across the existing
    // s1/s2/s3 video stages. Bounds and row/column still use x_pre/y_pre;
    // registering the earlier character adds no output pixel latency.
    wire [11:0] status_decode_x=PIPELINED_STATUS_CHAR?x_early:x_pre;
    wire [11:0] status_decode_y=PIPELINED_STATUS_CHAR?y_early:y_pre;
    wire [11:0] status_decode_rx=status_decode_x-STATUS_X;
    wire status_decode_period=ENABLE_PERIOD_OSD && status_decode_y>=PERIOD_Y;
    wire [7:0] status_character=status_decode_period ? period_char(status_decode_rx[8:4]) : status_char(status_decode_rx[8:4]);
    wire [7:0] status_ch_pre;
    generate if(PIPELINED_STATUS_CHAR)begin: status_character_pipeline
      // Keep the row predicate out of the wide character mux. Both
      // candidates and the predicate cross the same existing s1->s2 edge.
      wire [7:0] status_candidate=status_decode_period?8'd0:status_char(status_decode_rx[8:4]);
      wire [7:0] period_candidate=status_decode_period?period_char(status_decode_rx[8:4]):8'd0;
      reg [7:0] status_character_r,period_character_r;
      reg period_r;
      always @(posedge clk)begin
        status_character_r<=status_candidate;
        period_character_r<=period_candidate;
        period_r<=status_decode_period;
      end
      assign status_ch_pre=period_r?period_character_r:status_character_r;
    end else begin: status_character_compatibility
      assign status_ch_pre=status_character;
    end endgenerate
    // Port A serves the existing status bar; port B serves temperature.
    // The former date/time counter, formatter, decoder and background are gone.

    // Temperature alone uses 2x nearest-neighbour glyph expansion (16x16).
    wire [11:0] temperature_rx_pre=x_pre-TEMP_X;
    wire temperature_line_pre=ENABLE_TEMPERATURE_OSD && y_pre>=TEMP_Y && y_pre<TEMP_Y+16;
    wire [11:0] temperature_ry_pre=y_pre-TEMP_Y;
    wire [7:0] temperature_ch_pre=temperature_char(temperature_rx_pre[7:4]);
    wire [11:0] emergency_rx_pre=x_pre-EMER_X,emergency_ry_pre=y_pre-EMER_Y;
    wire [7:0] emergency_ch_pre=emergency_char(emergency_rx_pre[8:5]);
    // The temperature strip and central emergency title never overlap.
    // Share port B so the emergency glyph no longer traverses a combinational
    // character/row/column LUT tree in the s3->s4 compositor path.
    wire [13:0] temperature_font_address=temperature_line_pre ?
      {temperature_ch_pre,temperature_ry_pre[3:1],temperature_rx_pre[3:1]} :
      {emergency_ch_pre,emergency_ry_pre[4:2],emergency_rx_pre[4:2]};
    wire [13:0] selected_font_address={status_ch_pre,status_ry_pre[3:1],status_rx_pre[3:1]};
    wire status_font_bit_r,temperature_font_bit_r;
    generate if(USE_NATIVE_FONT)begin: shared_native_font
      subtitle_shared_font_rom #(.ENABLE_SECOND(1),.ENABLE_INTEGER_LOOKUP(ENABLE_TEMPERATURE_OSD)) font(.clk(clk),.address(selected_font_address),.pixel(status_font_bit_r),
         .temperature_address(temperature_font_address),.temperature_pixel(temperature_font_bit_r),
        .integer_lookup(ENABLE_TEMPERATURE_OSD && x_pre==0 && y_pre==0),
        .integer_address(temperature_magnitude[10:4]),.integer_byte(temperature_integer_byte));
    end else begin: original_font
      reg font_bit;always @(posedge clk)font_bit<=status_font_memory[selected_font_address];
      assign status_font_bit_r=font_bit;assign temperature_font_bit_r=1'b0;assign temperature_integer_byte=8'd0;
    end endgenerate

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
    wire startup_on=ENABLE_STARTUP_UI && startup_loading;
    reg [1:0] temperature_hit_r;
    always @(posedge clk or posedge rst)
     if(rst)temperature_hit_r<=0;
     else begin
      temperature_hit_r[0]<=ENABLE_TEMPERATURE_OSD && x_pre>=TEMP_X && x_pre<TEMP_X+TEMP_CHARS*16 &&
                              temperature_line_pre;
      temperature_hit_r[1]<=ENABLE_TEMPERATURE_OSD && x_pre>=TEMP_X-4 && x_pre<TEMP_X+TEMP_CHARS*16+4 &&
                              y_pre>=TEMP_Y-2 && y_pre<TEMP_Y+20;
     end
    wire temperature_pixel=!startup_on && temperature_hit_r[0] && temperature_font_bit_r;
    wire temperature_bar_visible=!startup_on && temperature_hit_r[1];
    wire [23:0] temperature_colour=temperature_connected&&temperature_alarm?24'hff5656:!temperature_valid?24'hffe0a0:
                                   temperature_warning?24'hffca48:24'h70ffd0;
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
    wire legacy_banner_pixel;
    wire banner_pixel=ENABLE_SUBTITLE&&custom_active?custom_pixel:legacy_banner_pixel;
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
      assign legacy_banner_pixel=feature_mask[0]&&!emergency&&hit_r&&pixel_r;
    end else begin: banner_compatibility
      assign legacy_banner_pixel=feature_mask[0]&&!emergency&&in_banner_text&&banner_glyph[7-banner_col];
    end endgenerate
    wire in_banner_bar = (y >= (BANNER_Y - 6)) && (y < (BANNER_Y + BCELL + 6));
    wire banner_bar_visible = ENABLE_SUBTITLE&&custom_active?custom_bar:feature_mask[0] && !emergency && in_banner_bar;
    wire status_bar_visible = feature_mask[2] && !emergency && status_hit_r[1];
    // Reuse the existing text-compositor stage: no new font ROM, DSP or
    // picture buffer. Progress is actual received data, not elapsed time.
    localparam integer LOAD_X=(SCREEN_W-400)/2;
    localparam integer LOAD_Y=SCREEN_H/2+24;
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
    wire glyph_pixel = emergency && in_text && (USE_NATIVE_FONT?temperature_font_bit_r:glyph[7-font_col]);

    // Parallel priority masks keep the font output out of a serial RGB mux
    // chain. Masks are exclusive, preserving all overlap priorities exactly.
    wire comp_white=glyph_pixel || status_pixel || banner_pixel;
    wire comp_ink=temperature_pixel || comp_white;
    wire comp_bar=(emergency && in_bar) || status_bar_visible ||
                  banner_bar_visible || temperature_bar_visible;
    wire comp_lower=!emergency_border && !startup_bar_r;
    wire comp_load=!emergency_border && startup_bar_r;
    wire comp_temp=comp_lower && temperature_pixel;
    wire comp_white_layer=comp_lower && !temperature_pixel && comp_white;
    wire comp_background=comp_lower && !comp_ink && comp_bar;
    wire comp_startup=comp_lower && !comp_ink && !comp_bar && startup_on;
    wire comp_opaque=emergency_border || comp_load || comp_temp || comp_white_layer || comp_startup;
    always @* begin
      text_rgb=({24{emergency_border}} & 24'hff2020) |
        ({24{comp_load}} & (startup_fill_r?24'h31d8cb:24'h203a52)) |
        ({24{comp_temp}} & temperature_colour) | {24{comp_white_layer}} |
        ({24{comp_background}} & (emergency?24'hb00000:24'h12385a)) |
        ({24{comp_startup}} & 24'h08182c);
      text_alpha={8{comp_opaque}} |
        ({8{comp_background}} & (emergency?8'd220:8'd180));
    end

endmodule

// Explicit native shared timestamp/status font; generated, not erased by eram_init=off.
module subtitle_shared_font_rom #(parameter ENABLE_SECOND=0,ENABLE_INTEGER_LOOKUP=0)(input clk,input [13:0] address,output pixel,
 input [13:0] temperature_address,output temperature_pixel,
 input integer_lookup,input [6:0] integer_address,output [7:0] integer_byte);
 wire lookup_active=ENABLE_INTEGER_LOOKUP && integer_lookup;
 wire [10:0] temperature_word_address=lookup_active?{1'b1,3'd0,integer_address}:{1'b0,temperature_address[13:4]};
 wire temperature_byte_select=lookup_active?1'b0:temperature_address[3];
 wire [15:0] q,temperature_q;
 assign integer_byte=temperature_q[7:0];reg [2:0] bit_index;reg [2:0] temperature_bit_index;
 generate if(ENABLE_SECOND)begin: second_port_index
  always @(posedge clk)temperature_bit_index<=temperature_address[2:0];
 end endgenerate
 assign temperature_pixel=ENABLE_SECOND?temperature_q[temperature_bit_index]:1'b0;
 always @(posedge clk)bit_index<=address[2:0];
 assign pixel=q[bit_index];
 // Native 8-bit port B selects the byte with byteb at the read clock.
 // This preserves the 16-bit INIT layout and avoids a 16:1 output mux.
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("8"),.DATA_WIDTH_B("8"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
.INIT_00(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_01(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_02(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_03(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_04(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_05(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_06(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_07(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_08(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_09(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_0A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_0B(256'h00000000000000000018180000000000000000007e0000000000000000000000),
.INIT_0C(256'h003c42403840423c007e020c3040423c007e181818181c18003c464a5262423c),
.INIT_0D(256'h000404081020407e003c42423e020438003c42403e02027e0020207e22242830),
.INIT_0E(256'h00000000000000000000180000180000001c20407c42423c003c42423c42423c),
.INIT_0F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_10(256'h003c42020202423c003e42423e42423e004242427e4224180000000000000000),
.INIT_11(256'h003c42427202423c000202023e02027e007e02023e02027e001e22424242221e),
.INIT_12(256'h004222120e1222420000000000000000007e18181818187e004242427e424242),
.INIT_13(256'h003c42424242423c00424262524a464200424242425a6642007e020202020202),
.INIT_14(256'h003c42403c02027c004222123e42423e0000000000000000000202023e42423e),
.INIT_15(256'h0042665a424242420000000000000000003c424242424242001818181818187e),
.INIT_16(256'h0000000000000000000000000000000000181818182442420042422418182442),
.INIT_17(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_18(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_19(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_1F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_20(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_21(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_22(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_23(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_24(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_25(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_26(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_27(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_28(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_29(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_2F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_30(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_31(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_32(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_33(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_34(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_35(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_36(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_37(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_38(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_39(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_3F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_40(256'h0015001400130012001100100009000800070006000500040003000200010000),
.INIT_41(256'h0031003000290028002700260025002400230022002100200019001800170016),
.INIT_42(256'h0047004600450044004300420041004000390038003700360035003400330032),
.INIT_43(256'h0063006200610060005900580057005600550054005300520051005000490048),
.INIT_44(256'h0079007800770076007500740073007200710070006900680067006600650064),
.INIT_45(256'h0095009400930092009100900089008800870086008500840083008200810080),
.INIT_46(256'h0011001000090008000700060005000400030002000100000099009800970096),
.INIT_47(256'h0027002600250024002300220021002000190018001700160015001400130012),
.INIT_48(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_49(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_4F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_50(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_51(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_52(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_53(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_54(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_55(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_56(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_57(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_58(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_59(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_5F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_60(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_61(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_62(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_63(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_64(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_65(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_66(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_67(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_68(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_69(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_6F(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_70(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_71(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_72(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_73(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_74(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_75(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_76(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_77(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_78(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_79(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7A(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7B(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7C(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7D(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7E(256'h0000000000000000000000000000000000000000000000000000000000000000),
.INIT_7F(256'h0000000000000000000000000000000000000000000000000000000000000000),.SRMODE("SYNC")) rom(
 .doa(q),.dia(16'd0),.addra({1'b0,address[13:4]}),.bytea(address[3]),.bytewea(1'b0),.csa(1'b1),.wea(1'b0),.clka(clk),.rsta(1'b0),.ocea(1'b1),
 .dob(temperature_q),.dib(16'd0),.addrb(temperature_word_address),.byteb(temperature_byte_select),.byteweb(1'b0),.csb(ENABLE_SECOND?1'b1:1'b0),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
endmodule
