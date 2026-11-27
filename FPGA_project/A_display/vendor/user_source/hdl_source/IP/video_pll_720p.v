/************************************************************\
 **     Copyright (c) 2012-2025 Anlogic Inc.
 **  All Right Reserved.
\************************************************************/
/************************************************************\
 ** Log	:	Generated from the verified 75 MHz HDMI PLL settings.
 ** File	:	video_pll_720p.v
 ** Device	:	EG4S20BG256
\************************************************************/

///////////////////////////////////////////////////////////////////////////////
//	Input frequency:               50.000000 MHz
//	Clock multiplication factor: 3
//	Clock division factor:       2
//	Clock information:
//		C0        	| 75.000000 MHZ | 0.0000 DEG
//		C1        	| 375.000000MHZ | 0.0000 DEG
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 100 fs

module video_pll_720p (
    refclk,
    reset,
    clk0_out,
    clk1_out,
    extlock
);

    input  refclk;
    input  reset;
    output clk0_out;
    output clk1_out;
    output extlock;     // PLL 锁定指示，供顶层上电复位使用

    wire clk0_buf;

    EG_LOGIC_BUFG bufg_feedback (
        .i(clk0_buf),
        .o(clk0_out)
    );

    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"),
        .DYNCFG("DISABLE"),
        .FIN("50.000000"),
        .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("CLKC0_EXT"),
        .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE"),
        .SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(2),
        .ICP_CURRENT(9),
        .KVCO(2),
        .LPF_CAPACITOR(1),
        .LPF_RESISTOR(8),
        .REFCLK_DIV(2),
        .FBCLK_DIV(3),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC0_DIV(10),
        .CLKC0_CPHASE(9),
        .CLKC0_FPHASE(0),
        .CLKC1_ENABLE("ENABLE"),
        .CLKC1_DIV(2),
        .CLKC1_CPHASE(1),
        .CLKC1_FPHASE(0)
    ) pll_inst (
        .refclk(refclk),
        .reset(reset),
        .stdby(1'b0),
        .extlock(extlock),
        .load_reg(1'b0),
        .psclk(1'b0),
        .psdown(1'b0),
        .psstep(1'b0),
        .psclksel(3'b000),
        .psdone(open),
        .dclk(1'b0),
        .dcs(1'b0),
        .dwe(1'b0),
        .di(8'b00000000),
        .daddr(6'b000000),
        .do({open, open, open, open, open, open, open, open}),
        .fbclk(clk0_out),
        .clkc({open, open, open, clk1_out, clk0_buf})
    );

endmodule
