`timescale 1ns/1ps
module tb_ethernet_diagnostics;
 reg clk=0,rst=1,cfg=0,link=0,online=0,tx=0,rx=0,good=0;always #20 clk=~clk;
 reg refclk=0;always #10 refclk=~refclk;
 wire [4:0] flags;wire [19:0] counts;wire [24:0] view;
 ethernet_link_diagnostics dut(.clk(clk),.rst(rst),.configured(cfg),.link_100(link),.online(online),.tx_active(tx),.rx_ctl(rx),.packet_valid(good),.flags(flags),.counts(counts));
 ethernet_mailbox #(.WIDTH(25)) bridge(.src_clk(clk),.src_rst(rst),.src_valid(1'b1),.src_data({flags,counts}),.src_ready(),
  .dst_clk(refclk),.dst_rst(rst),.dst_valid(),.dst_data(view));
 task settle;begin repeat(20)@(negedge clk);end endtask
 task check(input [4:0] f,input [19:0] c);begin
  settle;if(flags!==f || counts!==c || view!=={f,c})$fatal(1,"diag wrong flags=%b counts=%h CDC=%h expected=%h",flags,counts,view,{f,c});
 end endtask
 task transmit;begin @(negedge clk);tx=1;repeat(8)@(negedge clk);tx=0;repeat(2)@(negedge clk);end endtask
 task receive_activity;begin @(negedge clk);rx=1;repeat(8)@(negedge clk);rx=0;repeat(8)@(negedge clk);end endtask
 task accepted;begin @(negedge clk);good=1;@(negedge clk);good=0;end endtask
 integer i;
 initial begin
  repeat(5)@(negedge clk);rst=0;check(0,0);
  cfg=1;check(5'b10000,0);link=1;check(5'b11000,0);
  transmit;transmit;transmit;check(5'b11010,{8'd3,8'd0,4'd0});
  receive_activity;check(5'b11011,{8'd3,8'd1,4'd0});
  // Raw RX activity must not masquerade as valid MAC reception.
  if(online || counts[3:0]!=0)$fatal(1,"noise considered accepted packet");
  accepted;accepted;online=1;check(5'b11111,{8'd3,8'd1,4'd2});
  link=0;online=0;check(5'b10011,{8'd3,8'd1,4'd2});
  for(i=0;i<260;i=i+1)begin transmit;receive_activity;accepted;end
  check(5'b10011,20'hfffff);
  rst=1;settle;rst=0;check(5'b10000,0);
  $display("PASS: distinguish unconfigured, PHY-only, TX/no-RX, RX/no-valid-packet, accepted-peer, disconnect; counters saturate, persist until reset, bundled CDC never mislabels RX activity as valid frames");$finish;
 end
 initial begin #1000000;$fatal(1,"diag test timeout");end
endmodule
