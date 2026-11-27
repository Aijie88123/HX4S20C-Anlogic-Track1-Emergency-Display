`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_route -- 疏散路线“绶带”绘制
//
// 两条路线的几何全部来自 emergency_map_plan 的寄存器（每帧更新一次）。
//
// ★ 流水（统一 4 级内部寄存 R2..R5，输出与宿主 s6_rgb 同像素）：
//     R2：段几何 —— 沿轴距离 u / 横向偏移 |v| / 是否在段内 ok，以及失效段判定，
//         并**寄存**下来；寄存后的 (u,|v|,ok) 直接送 emergency_map_arrow，
//         箭头与路线必然走在同一条带上，箭头模块自己不用再算一遍段几何。
//     R3：带宽档位（高光 / 主体 / 描边）与失效档位 -> 3 bit 类别码
//     R4：按类别选色（RGB + alpha）
//     R5：输出寄存器
//   一级里塞“段几何 + 选中色”时组合深度 17 级（18.6 ns），拆开后最长一段
//   只剩段几何（约 6 级）。
//
// 颜色：绿色核心(5px) + 更亮中心高光(1px) + 深绿描边(1px) = 推荐路线
//       暗红核心 + 交叉叉纹                            = 已失效的原路线
// 全部是坐标加减 + 比较 + 选色，没有乘法/除法。
// ---------------------------------------------------------------------------
module emergency_map_route (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] lx, ly,

    input  wire        lv0_en, lv1_en,
    input  wire [11:0] lv0_sx, lv0_sy, lv0_len, lv1_sx, lv1_sy, lv1_len,
    input  wire        lv0_ax, lv0_dir, lv1_ax, lv1_dir,

    input  wire        dq0_en, dq1_en,
    input  wire [11:0] dq0_sx, dq0_sy, dq0_len, dq1_sx, dq1_sy, dq1_len,
    input  wire        dq0_ax, dq0_dir, dq1_ax, dq1_dir,

    // R2 寄存后的段几何：直接给 arrow 用
    output reg  [13:0] lv0_u, lv0_av, lv1_u, lv1_av,
    output reg         lv0_ok, lv1_ok,

    output reg  [23:0] route_rgb,
    output reg  [7:0]  route_alpha
);

    localparam [23:0] C_RT_OUT  = 24'h0B3A20;   // 路线描边
    localparam [23:0] C_RT      = 24'h4FD08A;   // 路线主体（设计稿 Safe 绿）
    localparam [23:0] C_RT_HI   = 24'hB8FFD0;   // 路线中心高光
    localparam [23:0] C_DEAD    = 24'h6E1A22;   // 失效路线
    localparam [23:0] C_DEADX   = 24'hFF6A6A;   // 失效路线的叉纹

    localparam [11:0] TOL_CORE = 12'd2;         // 主体半宽（5 px 宽的带）
    localparam [11:0] TOL_OUT  = 12'd3;         // 含描边的半宽（7 px）

    // ==================================================================
    // R2 组合：段几何（只依赖 lx/ly 与 plan 的寄存器）
    // ==================================================================
    wire signed [13:0] r0u = lv0_ax ? ($signed({1'b0,ly}) - $signed({1'b0,lv0_sy}))
                                    : ($signed({1'b0,lx}) - $signed({1'b0,lv0_sx}));
    wire signed [13:0] r0v = lv0_ax ? ($signed({1'b0,lx}) - $signed({1'b0,lv0_sx}))
                                    : ($signed({1'b0,ly}) - $signed({1'b0,lv0_sy}));
    wire signed [13:0] r1u = lv1_ax ? ($signed({1'b0,ly}) - $signed({1'b0,lv1_sy}))
                                    : ($signed({1'b0,lx}) - $signed({1'b0,lv1_sx}));
    wire signed [13:0] r1v = lv1_ax ? ($signed({1'b0,lx}) - $signed({1'b0,lv1_sx}))
                                    : ($signed({1'b0,ly}) - $signed({1'b0,lv1_sy}));

    wire signed [13:0] s0u = lv0_dir ? r0u : -r0u;
    wire signed [13:0] s1u = lv1_dir ? r1u : -r1u;
    wire signed [13:0] a0v = r0v[13] ? -r0v : r0v;
    wire signed [13:0] a1v = r1v[13] ? -r1v : r1v;

    wire lv0_ok_n = lv0_en && !s0u[13] && (s0u <= $signed({2'd0, lv0_len}));
    wire lv1_ok_n = lv1_en && !s1u[13] && (s1u <= $signed({2'd0, lv1_len}));

    // ---- 失效路线：同样的带，暗红 + 虚线 + 交叉叉纹 ----
    wire signed [13:0] q0u = dq0_ax ? ($signed({1'b0,ly}) - $signed({1'b0,dq0_sy}))
                                    : ($signed({1'b0,lx}) - $signed({1'b0,dq0_sx}));
    wire signed [13:0] q0v = dq0_ax ? ($signed({1'b0,lx}) - $signed({1'b0,dq0_sx}))
                                    : ($signed({1'b0,ly}) - $signed({1'b0,dq0_sy}));
    wire signed [13:0] q1u = dq1_ax ? ($signed({1'b0,ly}) - $signed({1'b0,dq1_sy}))
                                    : ($signed({1'b0,lx}) - $signed({1'b0,dq1_sx}));
    wire signed [13:0] q1v = dq1_ax ? ($signed({1'b0,lx}) - $signed({1'b0,dq1_sx}))
                                    : ($signed({1'b0,ly}) - $signed({1'b0,dq1_sy}));
    wire signed [13:0] z0u = dq0_dir ? q0u : -q0u;
    wire signed [13:0] z1u = dq1_dir ? q1u : -q1u;
    wire signed [13:0] z0v = q0v[13] ? -q0v : q0v;
    wire signed [13:0] z1v = q1v[13] ? -q1v : q1v;

    wire d0_in_n = dq0_en && !z0u[13] && (z0u <= $signed({2'd0, dq0_len})) &&
                   (z0v <= $signed({2'd0, TOL_CORE}));
    wire d1_in_n = dq1_en && !z1u[13] && (z1u <= $signed({2'd0, dq1_len})) &&
                   (z1v <= $signed({2'd0, TOL_CORE}));

    // 交叉叉纹：两组 45 度线叠加，视觉上就是“此路不通”的规矩叉纹
    wire [11:0] crs = lx + ly;
    wire [11:0] crd = (lx >= ly) ? (lx - ly) : (ly - lx);
    wire dead_x_n = (crs[3:0] == 4'd0) || (crd[3:0] == 4'd0);

    reg        r2_dead, r2_deadx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lv0_u <= 14'd0; lv0_av <= 14'd0; lv1_u <= 14'd0; lv1_av <= 14'd0;
            lv0_ok <= 1'b0; lv1_ok <= 1'b0;
            r2_dead <= 1'b0; r2_deadx <= 1'b0;
        end
        else begin
            lv0_u  <= s0u[13] ? 14'd0 : s0u;
            lv1_u  <= s1u[13] ? 14'd0 : s1u;
            lv0_av <= a0v[13] ? 14'd0 : a0v;
            lv1_av <= a1v[13] ? 14'd0 : a1v;
            lv0_ok <= lv0_ok_n;
            lv1_ok <= lv1_ok_n;
            r2_dead  <= d0_in_n || d1_in_n;
            r2_deadx <= dead_x_n;
        end
    end

    // ==================================================================
    // R3 组合：带宽档位 -> 3 bit 类别码（只依赖 R2 寄存器）
    //   5=失效叉纹 4=失效主体 3=高光 2=主体 1=描边 0=无
    // ==================================================================
    wire hi_n   = (lv0_ok && lv0_av == 14'd0) || (lv1_ok && lv1_av == 14'd0);
    wire body_n = (lv0_ok && lv0_av <= 14'd2) || (lv1_ok && lv1_av <= 14'd2);
    wire out_n  = (lv0_ok && lv0_av <= 14'd3) || (lv1_ok && lv1_av <= 14'd3);

    wire [2:0] cls_n = r2_dead ? (r2_deadx ? 3'd5 : 3'd4) :
                       hi_n    ? 3'd3 :
                       body_n  ? 3'd2 :
                       out_n   ? 3'd1 : 3'd0;

    reg [2:0] r3_cls;
    always @(posedge clk or posedge rst) begin
        if (rst) r3_cls <= 3'd0;
        else     r3_cls <= cls_n;
    end

    // ==================================================================
    // R4：选色
    // ==================================================================
    reg [23:0] r4_rgb;
    reg [7:0]  r4_a;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r4_rgb <= 24'd0; r4_a <= 8'd0;
        end
        else begin
            case (r3_cls)
                3'd5:    begin r4_rgb <= C_DEADX;  r4_a <= 8'd255; end
                3'd4:    begin r4_rgb <= C_DEAD;   r4_a <= 8'd170; end
                3'd3:    begin r4_rgb <= C_RT_HI;  r4_a <= 8'd255; end
                3'd2:    begin r4_rgb <= C_RT;     r4_a <= 8'd235; end
                3'd1:    begin r4_rgb <= C_RT_OUT; r4_a <= 8'd220; end
                default: begin r4_rgb <= 24'd0;    r4_a <= 8'd0;   end
            endcase
        end
    end

    // ==================================================================
    // R5：输出寄存器
    // ==================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            route_rgb   <= 24'd0;
            route_alpha <= 8'd0;
        end
        else begin
            route_rgb   <= r4_rgb;
            route_alpha <= r4_a;
        end
    end

endmodule
