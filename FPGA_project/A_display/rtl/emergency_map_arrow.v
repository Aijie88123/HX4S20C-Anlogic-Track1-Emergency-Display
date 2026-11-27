`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_arrow -- 沿推荐路线流动的“动态箭头”
//
// 这是整个动态疏散图最抓眼球的元素，做法却是全工程最省的：
//   把路线第一/第二段的“沿轴距离 u”按 32 像素一格取模，格内画一个三角头，
//   每帧让相位 flow 加一 —— 箭头就匀速朝着出口跑。
//     t = (u - flow) 低 5 位 (即 mod 32)      -> 格内位置
//     |v| <= (9 - t) >> 1 且 t <= 9           -> 三角（尖朝前，底在后）
//   三支箭头共用一份相位，只是分别落后 11 / 22 个像素 —— 形成“一串箭头在跑”
//   的拖尾感，但只需要两次减法和一个比较。
//
// ★ 流水：输入是 emergency_map_route **R2 寄存后**的 (u,|v|,ok)。
//     R3：六个三角判据 -> (lead, tail) 并寄存
//     R4：选色（近白领先 / 更绿拖尾）
//     R5：输出寄存器
//   与 route 的输出寄存器同拍抵达 emergency_map_top 的合成级，不多不少。
//   没有 ROM、没有乘法、没有除法：一个 5 bit 减法 + 移位 + 比较就够。
// ---------------------------------------------------------------------------
module emergency_map_arrow (
    input  wire        clk,
    input  wire        rst,
    input  wire [13:0] lv0_u, lv0_av, lv1_u, lv1_av,
    input  wire        lv0_ok, lv1_ok,
    input  wire [4:0]  flow,
    output reg  [23:0] arrow_rgb,
    output reg  [7:0]  arrow_alpha
);

    localparam [23:0] C_ARROW  = 24'hEAFFF2;   // 箭头主体：近白，压在绿线上最醒目
    localparam [23:0] C_ARROW2 = 24'h86FFB0;   // 尾支（更绿，形成层次）

    // ---- R3 组合：格内位置 + 宽度包络 + 六个三角判据（只依赖 R2 寄存器）----
    wire [4:0] t0a = lv0_u[4:0] - flow;
    wire [4:0] t0b = t0a - 5'd11;
    wire [4:0] t0c = t0a - 5'd22;
    wire [4:0] t1a = lv1_u[4:0] - flow;
    wire [4:0] t1b = t1a - 5'd11;
    wire [4:0] t1c = t1a - 5'd22;

    wire [13:0] w0a = (14'd9 - {9'd0, t0a}) >> 1;
    wire [13:0] w0b = (14'd9 - {9'd0, t0b}) >> 1;
    wire [13:0] w0c = (14'd9 - {9'd0, t0c}) >> 1;
    wire [13:0] w1a = (14'd9 - {9'd0, t1a}) >> 1;
    wire [13:0] w1b = (14'd9 - {9'd0, t1b}) >> 1;
    wire [13:0] w1c = (14'd9 - {9'd0, t1c}) >> 1;

    wire a0a = lv0_ok && (t0a <= 5'd9) && (lv0_av <= w0a);
    wire a0b = lv0_ok && (t0b <= 5'd9) && (lv0_av <= w0b);
    wire a0c = lv0_ok && (t0c <= 5'd9) && (lv0_av <= w0c);
    wire a1a = lv1_ok && (t1a <= 5'd9) && (lv1_av <= w1a);
    wire a1b = lv1_ok && (t1b <= 5'd9) && (lv1_av <= w1b);
    wire a1c = lv1_ok && (t1c <= 5'd9) && (lv1_av <= w1c);

    wire lead_n = a0a || a1a;            // 领先那支：近白
    wire tail_n = a0b || a0c || a1b || a1c;

    reg r3_lead, r3_tail;
    always @(posedge clk or posedge rst) begin
        if (rst) begin r3_lead <= 1'b0; r3_tail <= 1'b0; end
        else     begin r3_lead <= lead_n; r3_tail <= tail_n; end
    end

    // ---- R4：选色 ----
    reg [23:0] r4_rgb;
    reg [7:0]  r4_a;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r4_rgb <= 24'd0; r4_a <= 8'd0;
        end
        else begin
            if (r3_lead)      begin r4_rgb <= C_ARROW;  r4_a <= 8'd255; end
            else if (r3_tail) begin r4_rgb <= C_ARROW2; r4_a <= 8'd210; end
            else              begin r4_rgb <= 24'd0;    r4_a <= 8'd0;   end
        end
    end

    // ---- R5：输出寄存器 ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arrow_rgb   <= 24'd0;
            arrow_alpha <= 8'd0;
        end
        else begin
            arrow_rgb   <= r4_rgb;
            arrow_alpha <= r4_a;
        end
    end

endmodule
