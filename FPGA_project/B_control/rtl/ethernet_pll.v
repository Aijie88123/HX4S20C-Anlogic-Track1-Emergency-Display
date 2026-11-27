// 50 MHz reference, 25 MHz MAC, 25 MHz TXC delayed 90 degrees.
module ethernet_pll (
  refclk,
  reset,
  clk0_out,
  clk1_out,
  clk2_out,
  extlock
);

  input refclk;
  input reset;
  output clk0_out;
  output clk1_out;
  output clk2_out;
  output extlock;      // PLL 锁定指示，供顶层上电复位使用

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
    .GMC_GAIN(4),
    .ICP_CURRENT(29),
    .KVCO(4),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(2),
    .REFCLK_DIV(2),
    .FBCLK_DIV(1),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(40),
    .CLKC0_CPHASE(39),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(40),
    .CLKC1_CPHASE(9),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("DISABLE"),
    .CLKC2_DIV(8),
    .CLKC2_CPHASE(3),
    .CLKC2_FPHASE(0) 
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
    .clkc({open, open, clk2_out, clk1_out, clk0_buf}) 
  );

endmodule

