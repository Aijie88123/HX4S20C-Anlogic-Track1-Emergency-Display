`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_plan -- 动态校园疏散地图的"动画节拍 + 版面规划表"
//
// 位置：emergency_map_top 的第一个子模块。它把"每帧才变一次"的东西全部集中到
//   一处：动画相位、疏散路线几何、危险区矩形、事故点/当前位置坐标、推荐出口。
//   后面的绘制模块（route/arrow/danger/exit/mark/text）全部只读它的**寄存器**，
//   于是像素级只剩"和常量比大小 + 选色"，视频域的组合链被切得很短。
//
// 为什么要有这一层（而不是让各绘制模块各自查事件表）：
//   1) 路线几何被 route 与 arrow 两个模块共用，放在一处就不会漂移；
//   2) 事件表只在 frame_tick 上翻一次，输入 event_type/state 是慢变量，
//      整张表可以放心地"组合查表 + 寄存"，不会给 video_clk 添路径；
//   3) 上板调试时"地图画错了"第一眼就看这张表，不用翻 5 个模块。
//
// 坐标：全部是**地图窗口局部坐标**（0..WW-1 / 0..WH-1），由 WW/WH 的百分比
//   在 elaboration 期算成常量 —— 换 HDMI 分辨率时窗口跟着变，版面等比缩放，
//   一个像素都不用改。窗口原点 WX0/WY0 由 emergency_map_top 负责加减。
//
// 事件映射（与《创新功能实施方案》5.4 一致）：
//   0 火灾     危险区=实验楼及周边   推荐出口=东门  主线 实验楼->东侧纵向道->主干道A->东门
//   1 地震     危险区=教学楼A区/B区  推荐=中心操场  主线 图书馆->操场    备用 教学楼B区->操场
//   2 实验室事故 危险区=实验楼西侧    推荐出口=西门  主线 实验楼->主干道B->西门
//   3 演练     危险区=食堂/体育馆    推荐=集合点    主线 宿舍区->操场    备用 图书馆->操场
//
// 状态 -> 画面（对应实施方案 4.3"报警状态 -> 疏散状态"）：
//   state 2 (ALARM)      : 危险区出现，主线绿色 + 箭头流动
//   state 3 (EVACUATION) : 主线被判失效（暗红 + 叉），备用线变绿 + 箭头改沿备用线流动
//   这一步就是演示流程里"原路线失效 -> 自动切换备用路线"的硬件实现：
//   切换由状态机推着走，不需要人去点，也不需要软件判断。
// ---------------------------------------------------------------------------
module emergency_map_plan #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    // 地图窗口（屏幕百分比，必须与 emergency_map_top 一致）
    parameter integer MAP_XP0  = 26,
    parameter integer MAP_XP1  = 74,
    parameter integer MAP_YP0  = 43,
    parameter integer MAP_YP1  = 79
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        active,        // = emergency 模式
    input  wire [2:0]  state,         // 0 正常 / 2 报警 / 3 疏散
    input  wire [1:0]  event_type,    // 0 火灾 1 地震 2 实验室事故 3 演练
    input  wire        frame_tick,    // 每视频帧一个脉冲

    // ---- 动画相位 ----
    output reg  [4:0]  flow,          // 箭头流动相位，每帧 +1（走完 32 回卷）
    output reg  [3:0]  pulse,         // 当前位置脉冲环半径，2..15 循环

    // ---- 当前推荐路线：两段轴对齐线段 ----
    output reg         lv0_en, lv1_en,
    output reg  [11:0] lv0_sx, lv0_sy, lv0_len, lv1_sx, lv1_sy, lv1_len,
    output reg         lv0_ax, lv0_dir, lv1_ax, lv1_dir,

    // ---- 已失效的原路线（state 3 时用于画"此路不通"）----
    output reg         dq0_en, dq1_en,
    output reg  [11:0] dq0_sx, dq0_sy, dq0_len, dq1_sx, dq1_sy, dq1_len,
    output reg         dq0_ax, dq0_dir, dq1_ax, dq1_dir,

    // ---- 危险区 / 事故点 / 当前位置 ----
    output reg  [11:0] d0_x0, d0_y0, d0_x1, d0_y1,
    output reg  [11:0] d1_x0, d1_y0, d1_x1, d1_y1,
    output reg         d0_en, d1_en,
    output reg  [11:0] acc_x, acc_y,
    output reg         acc_en,
    output reg  [11:0] per_x, per_y,

    // ---- 推荐出口：0=东门 1=西门 2=南门 3=集合点(操场) ----
    output reg  [1:0]  rec_exit,
    output reg         swapped        // 1 = 已切到备用路线
);

    // ------------------------------------------------------------------
    // 版面锚点（窗口局部坐标，全部 elaboration 期常量）
    // ------------------------------------------------------------------
    // WW/WH 必须与 emergency_map_top 的窗口完全一致（947-332=615 / 568-309=259）。
    // 用"先整除再相减"而不是"(XP1-XP0) 乘宽度再除"，否则会差 1 px。
    localparam [11:0] WW = (SCREEN_W*MAP_XP1/100) - (SCREEN_W*MAP_XP0/100);   // 615
    localparam [11:0] WH = (SCREEN_H*MAP_YP1/100) - (SCREEN_H*MAP_YP0/100);   // 259

    // 四列建筑的横向中心（3% + k*25% 起步，列宽 21%）
    localparam [11:0] CX0 = WW*15/100;   // 92   教学楼A区 / 实验楼
    localparam [11:0] CX1 = WW*38/100;   // 233  图书馆 / 教学楼B区
    localparam [11:0] CX2 = WW*63/100;   // 387  行政楼 / 宿舍区
    localparam [11:0] CX3 = WW*88/100;   // 541  体育馆 / 食堂
    // 纵向道路中心（列间通道）
    localparam [11:0] GX1 = WW*26/100;   // 159
    localparam [11:0] GX2 = WW*51/100;   // 313  <- 北门/南门所在纵道
    localparam [11:0] GX3 = WW*76/100;   // 467
    // 横向主干道中心
    localparam [11:0] RAY = WH*25/100;   // 64   主干道 A（上排建筑与中心广场之间）
    localparam [11:0] RBY = WH*56/100;   // 145  主干道 B（中心广场与下排建筑之间）
    localparam [11:0] RBY2 = WH*80/100;  // 207  次干道 B（下排建筑南侧）
    // 上下排建筑的边缘
    localparam [11:0] TOPY = WH*5/100;   // 12
    localparam [11:0] ROWH = WH*17/100;  // 44
    localparam [11:0] BOTY = WH*59/100;  // 152
    localparam [11:0] BOTB = WH*76/100;  // 196
    // 中心操场（集合点）椭圆
    localparam [11:0] OVX  = WW*50/100;  // 307
    localparam [11:0] OVY  = WH*40/100;  // 103
    localparam [11:0] OVL  = WW*29/100;  // 178
    localparam [11:0] OVR  = WW*71/100;  // 436
    // 大门
    localparam [11:0] EGX  = WW*97/100;  // 596  东门
    localparam [11:0] WGX  = WW*3/100;   // 18   西门
    localparam [11:0] SGY  = WH*98/100;  // 253  南门
    localparam [11:0] NGY  = WH*2/100;   // 5    北门

    // ------------------------------------------------------------------
    // 路线规划表（组合查表）
    //   每条路线最多两段，段用 (起点, 轴向, 方向, 段长) 描述：
    //     axis 0 = 水平（沿 x 走）  1 = 垂直（沿 y 走）
    //     dir  1 = 沿轴向正方向    0 = 负方向
    // ------------------------------------------------------------------
    reg        m0_en, m1_en, b0_en, b1_en;
    reg [11:0] m0_sx, m0_sy, m0_len, m1_sx, m1_sy, m1_len;
    reg [11:0] b0_sx, b0_sy, b0_len, b1_sx, b1_sy, b1_len;
    reg        m0_ax, m0_dir, m1_ax, m1_dir;
    reg        b0_ax, b0_dir, b1_ax, b1_dir;
    reg [1:0]  rec;                               // 主路线（state2）的推荐出口
    reg [1:0]  brec;                              // 备用路线（state3）的推荐出口
    reg [11:0] ax_, ay_;                          // 事故点
    reg [11:0] e0x0, e0y0, e0x1, e0y1;            // 危险区主体
    reg [11:0] e1x0, e1y0, e1x1, e1y1;            // 危险区蔓延块
    reg        e1_on;

    always @(*) begin
        // 默认：全部关掉（非应急时一个像素都不画）
        m0_en = 1'b0; m1_en = 1'b0; b0_en = 1'b0; b1_en = 1'b0;
        m0_sx = CX0; m0_sy = BOTY; m0_len = 12'd1; m0_ax = 1'b1; m0_dir = 1'b0;
        m1_sx = CX0; m1_sy = RAY;  m1_len = 12'd1; m1_ax = 1'b0; m1_dir = 1'b1;
        b0_sx = CX0; b0_sy = RBY;  b0_len = 12'd1; b0_ax = 1'b0; b0_dir = 1'b1;
        b1_sx = GX2; b1_sy = RBY;  b1_len = 12'd1; b1_ax = 1'b1; b1_dir = 1'b1;
        rec   = 2'd0;
        brec  = 2'd2;   // 默认备用线出南门
        ax_ = CX0; ay_ = BOTY;
        e0x0 = CX0 - WW*12/100; e0y0 = BOTY - WH*6/100;
        e0x1 = CX0 + WW*12/100; e0y1 = BOTB + WH*4/100;
        e1x0 = 12'd0; e1y0 = 12'd0; e1x1 = 12'd0; e1y1 = 12'd0;
        e1_on = 1'b0;

        // 主路线起点（= 当前位置）。四条事件里"主/备两条路线的起点都相同"，
        // 于是切换备用路线时人是"原地改道"、不会瞬移 —— 这正是需求里
        // "原路线失效 -> 自动切换备用路线"要看到的动作。
        case (event_type)
            // ---------------- 火灾：实验楼东侧纵向道 -> 干道A -> 东门 ----------------
            2'd0: begin
                m0_en = 1'b1; m0_sx = GX1;      m0_sy = RBY2;
                              m0_ax = 1'b1;     m0_dir = 1'b0; m0_len = RBY2 - RAY;
                m1_en = 1'b1; m1_sx = GX1;      m1_sy = RAY;
                              m1_ax = 1'b0;     m1_dir = 1'b1; m1_len = EGX - GX1;
                // 备用：同一起点沿次干道B向东，再从中纵道南下出南门
                b0_en = 1'b1; b0_sx = GX1;      b0_sy = RBY2;
                              b0_ax = 1'b0;     b0_dir = 1'b1; b0_len = GX2 - GX1;
                b1_en = 1'b1; b1_sx = GX2;      b1_sy = RBY2;
                              b1_ax = 1'b1;     b1_dir = 1'b1; b1_len = SGY - RBY2;
                rec   = 2'd0;   brec = 2'd2;                     // 主线东门 / 备用南门
                ax_ = WW*8/100; ay_ = WH*68/100;
                // 危险区：实验楼整栋 + 周边
                e0x0 = WW*3/100;  e0y0 = WH*54/100;
                e0x1 = WW*27/100; e0y1 = WH*78/100;
                // 蔓延块（state 3 才出现）：压住主线要走的干道A东段
                e1x0 = WW*26/100; e1y0 = WH*21/100;
                e1x1 = WW*55/100; e1y1 = WH*29/100;
                e1_on = 1'b1;
            end
            // ---------------- 地震：教学楼A区 -> 干道A -> 中心操场 ----------------
            2'd1: begin
                m0_en = 1'b1; m0_sx = CX0;      m0_sy = RAY;
                              m0_ax = 1'b0;     m0_dir = 1'b1; m0_len = CX1 - CX0;
                m1_en = 1'b1; m1_sx = CX1;      m1_sy = RAY;
                              m1_ax = 1'b1;     m1_dir = 1'b1; m1_len = OVY - RAY;
                // 备用：同一起点沿干道A继续东行，再从中纵道南下出南门
                b0_en = 1'b1; b0_sx = CX0;      b0_sy = RAY;
                              b0_ax = 1'b0;     b0_dir = 1'b1; b0_len = GX2 - CX0;
                b1_en = 1'b1; b1_sx = GX2;      b1_sy = RAY;
                              b1_ax = 1'b1;     b1_dir = 1'b1; b1_len = SGY - RAY;
                rec   = 2'd3;   brec = 2'd2;                     // 主线操场 / 备用南门
                ax_ = WW*14/100; ay_ = WH*13/100;
                e0x0 = WW*3/100;  e0y0 = TOPY;
                e0x1 = WW*27/100; e0y1 = TOPY + ROWH;
                e1x0 = WW*27/100; e1y0 = BOTY;
                e1x1 = WW*49/100; e1y1 = BOTB;
                e1_on = 1'b1;
            end
            // ---------------- 实验室事故：实验楼南侧 -> 次干道B -> 西门 ----------------
            2'd2: begin
                m0_en = 1'b1; m0_sx = CX0;      m0_sy = RBY2;
                              m0_ax = 1'b0;     m0_dir = 1'b0; m0_len = CX0 - WGX;
                // 备用：同一起点沿次干道B向东，再从中纵道南下出南门
                b0_en = 1'b1; b0_sx = CX0;      b0_sy = RBY2;
                              b0_ax = 1'b0;     b0_dir = 1'b1; b0_len = GX2 - CX0;
                b1_en = 1'b1; b1_sx = GX2;      b1_sy = RBY2;
                              b1_ax = 1'b1;     b1_dir = 1'b1; b1_len = SGY - RBY2;
                rec   = 2'd1;   brec = 2'd2;                     // 主线西门 / 备用南门
                ax_ = WW*8/100; ay_ = WH*68/100;
                e0x0 = WW*3/100;  e0y0 = WH*54/100;
                e0x1 = WW*27/100; e0y1 = WH*78/100;
                // 蔓延块（state 3 才出现）：封住通往西门的次干道B西段
                e1x0 = WW*3/100;  e1y0 = WH*75/100;
                e1x1 = WW*15/100; e1y1 = WH*87/100;
                e1_on = 1'b1;
            end
            // ---------------- 演练：宿舍区 -> 中心操场 ----------------
            default: begin
                m0_en = 1'b1; m0_sx = CX2;      m0_sy = RBY;
                              m0_ax = 1'b1;     m0_dir = 1'b0; m0_len = RBY - OVY;
                // 备用：同一起点沿干道B西行，再到图书馆东侧北上进操场
                b0_en = 1'b1; b0_sx = CX2;      b0_sy = RBY;
                              b0_ax = 1'b0;     b0_dir = 1'b0; b0_len = CX2 - CX1;
                b1_en = 1'b1; b1_sx = CX1;      b1_sy = RBY;
                              b1_ax = 1'b1;     b1_dir = 1'b0; b1_len = RBY - OVY;
                rec   = 2'd3;   brec = 2'd3;                     // 主/备都去集合点
                ax_ = CX3; ay_ = BOTY + ROWH/2;
                e0x0 = WW*78/100; e0y0 = BOTY;
                e0x1 = WW*99/100; e0y1 = BOTB;
                e1x0 = WW*78/100; e1y0 = TOPY;
                e1x1 = WW*99/100; e1y1 = TOPY + ROWH;
                e1_on = 1'b1;
            end
        endcase
    end

    // ------------------------------------------------------------------
    // 状态 -> 主/备用切换
    //   state 2 报警：主路线可用
    //   state 3 疏散：主线失效，备用线接管（演示流程里"自动切换备用路线"）
    // ------------------------------------------------------------------
    wire use_backup = active && (state == 3'd3);
    wire route_on   = active && (state != 3'd0);
    wire danger_on  = active && (state != 3'd0);

    // 组合选出的"本帧几何"，下面每个 frame_tick 寄存一次
    wire        s_lv0_en = use_backup ? b0_en : m0_en;
    wire        s_lv1_en = use_backup ? b1_en : m1_en;
    wire [11:0] s_lv0_sx = use_backup ? b0_sx : m0_sx;
    wire [11:0] s_lv0_sy = use_backup ? b0_sy : m0_sy;
    wire [11:0] s_lv0_len= use_backup ? b0_len : m0_len;
    wire        s_lv0_ax = use_backup ? b0_ax : m0_ax;
    wire        s_lv0_dir= use_backup ? b0_dir : m0_dir;
    wire [11:0] s_lv1_sx = use_backup ? b1_sx : m1_sx;
    wire [11:0] s_lv1_sy = use_backup ? b1_sy : m1_sy;
    wire [11:0] s_lv1_len= use_backup ? b1_len : m1_len;
    wire        s_lv1_ax = use_backup ? b1_ax : m1_ax;
    wire        s_lv1_dir= use_backup ? b1_dir : m1_dir;

    wire        s_dq0_en = use_backup ? m0_en : 1'b0;
    wire        s_dq1_en = use_backup ? m1_en : 1'b0;
    wire [11:0] s_dq0_sx = m0_sx, s_dq0_sy = m0_sy, s_dq0_len = m0_len;
    wire [11:0] s_dq1_sx = m1_sx, s_dq1_sy = m1_sy, s_dq1_len = m1_len;
    wire        s_dq0_ax = m0_ax, s_dq0_dir = m0_dir;
    wire        s_dq1_ax = m1_ax, s_dq1_dir = m1_dir;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            flow <= 5'd0; pulse <= 4'd4;
            lv0_en <= 1'b0; lv1_en <= 1'b0; dq0_en <= 1'b0; dq1_en <= 1'b0;
            lv0_sx <= 12'd0; lv0_sy <= 12'd0; lv0_len <= 12'd0;
            lv1_sx <= 12'd0; lv1_sy <= 12'd0; lv1_len <= 12'd0;
            dq0_sx <= 12'd0; dq0_sy <= 12'd0; dq0_len <= 12'd0;
            dq1_sx <= 12'd0; dq1_sy <= 12'd0; dq1_len <= 12'd0;
            lv0_ax <= 1'b0; lv0_dir <= 1'b1; lv1_ax <= 1'b0; lv1_dir <= 1'b1;
            dq0_ax <= 1'b0; dq0_dir <= 1'b1; dq1_ax <= 1'b0; dq1_dir <= 1'b1;
            d0_x0 <= 12'd0; d0_y0 <= 12'd0; d0_x1 <= 12'd0; d0_y1 <= 12'd0;
            d1_x0 <= 12'd0; d1_y0 <= 12'd0; d1_x1 <= 12'd0; d1_y1 <= 12'd0;
            d0_en <= 1'b0; d1_en <= 1'b0; acc_en <= 1'b0;
            acc_x <= 12'd0; acc_y <= 12'd0;
            per_x <= 12'd0; per_y <= 12'd0;
            rec_exit <= 2'd0; swapped <= 1'b0;
        end
        else if (!active) begin
            // 退出应急：立刻收干净，同时把相位复位，下次进入从同一个起点开始
            flow <= 5'd0; pulse <= 4'd4;
            lv0_en <= 1'b0; lv1_en <= 1'b0; dq0_en <= 1'b0; dq1_en <= 1'b0;
            d0_en <= 1'b0; d1_en <= 1'b0; acc_en <= 1'b0;
            swapped <= 1'b0;
        end
        else if (frame_tick) begin
            flow  <= (flow == 5'd31) ? 5'd0 : (flow + 5'd1);
            pulse <= (pulse >= 4'd15) ? 4'd4 : (pulse + 4'd1);

            lv0_en <= s_lv0_en && route_on; lv1_en <= s_lv1_en && route_on;
            dq0_en <= s_dq0_en && route_on; dq1_en <= s_dq1_en && route_on;
            lv0_sx <= s_lv0_sx; lv0_sy <= s_lv0_sy; lv0_len <= s_lv0_len;
            lv0_ax <= s_lv0_ax; lv0_dir <= s_lv0_dir;
            lv1_sx <= s_lv1_sx; lv1_sy <= s_lv1_sy; lv1_len <= s_lv1_len;
            lv1_ax <= s_lv1_ax; lv1_dir <= s_lv1_dir;
            dq0_sx <= s_dq0_sx; dq0_sy <= s_dq0_sy; dq0_len <= s_dq0_len;
            dq0_ax <= s_dq0_ax; dq0_dir <= s_dq0_dir;
            dq1_sx <= s_dq1_sx; dq1_sy <= s_dq1_sy; dq1_len <= s_dq1_len;
            dq1_ax <= s_dq1_ax; dq1_dir <= s_dq1_dir;

            d0_en <= danger_on; d0_x0 <= e0x0; d0_y0 <= e0y0; d0_x1 <= e0x1; d0_y1 <= e0y1;
            d1_en <= (active && (state == 3'd3)) && e1_on;
            d1_x0 <= e1x0; d1_y0 <= e1y0; d1_x1 <= e1x1; d1_y1 <= e1y1;
            acc_en <= danger_on; acc_x <= ax_; acc_y <= ay_;

            // 当前位置 = 当前推荐路线的起点（第一段起点），语义上"我从这里出发"
            per_x <= m0_sx;
            per_y <= m0_sy;
            rec_exit <= use_backup ? brec : rec;
            swapped <= use_backup;
        end
    end

endmodule