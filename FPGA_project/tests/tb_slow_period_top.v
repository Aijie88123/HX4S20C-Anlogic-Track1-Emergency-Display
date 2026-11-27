`timescale 1ns/1ps
module tb_slow_period_top;
 reg clk=0,rst_n=1,next_key=1,auto_key=1,emergency_key=1;reg [3:0] switches=0;
 always #10 clk=~clk;
 wire mdio;
 dual_board_control_top #(.ENABLE_MEDIA(0),.ENABLE_RASTER(0),.ENABLE_REMOTE_TF(0),.ENABLE_SUBTITLE(0)) dut(.clk(clk),.rst_n(rst_n),.key_next(next_key),.key_auto(auto_key),
  .key_emergency(emergency_key),.sw(switches),.uart_rx(1'b1),.uart_tx(),.eth_rx_clk(1'b0),.eth_rx_ctl(1'b0),.eth_rxd(4'd0),
  .eth_tx_clk(),.eth_tx_ctl(),.eth_txd(),.eth_mdc(),.eth_mdio(mdio),.led(),.seg_sel(),.seg_data());
 // Scale elapsed time only; keep the real two-flop synchronizer, debounce,
 // press/release classifier and top-level command/period gates.
 defparam dut.s2.CLK_HZ=1000;
 defparam dut.u_carousel_clock.CLK_FREQ_HZ=1000;
 task clocks(input integer n);repeat(n)@(negedge dut.net_clk);endtask
 task check(input bit ok,input string message);if(!ok)$fatal(1,"%s",message);endtask
 task short_s2;begin next_key=0;clocks(20);next_key=1;clocks(20);end endtask
 task long_s2;begin next_key=0;clocks(730);next_key=1;clocks(20);end endtask
 task key_s4;begin emergency_key=0;#5200000;emergency_key=1;#5200000;end endtask
 task key_s3;begin auto_key=0;#5200000;auto_key=1;#5200000;end endtask
 initial begin
  #3;rst_n=0;#100;rst_n=1;
  dut.u_ethernet_pll.run_clock=1;dut.u_ethernet_pll.locked_value=1;
  dut.u_ethernet_link.online_value=1;dut.u_ethernet_link.configured_value=1;
  dut.u_ethernet_link.feedback_value=8'h0e;clocks(35);
  check(dut.FAST_DEMO==1 && dut.u_carousel_clock.PERIOD0_MS==3000 && dut.u_carousel_clock.PERIOD1_MS==5000 && dut.u_carousel_clock.PERIOD2_MS==8000 && dut.u_carousel_clock.STARTUP_PERIOD_MS==3000,"production top slow periods/startup parameters not applied");
  short_s2;check(dut.carousel_phase[4:3]==1,"normal S2 did not select 5s");
  check(!dut.command_armed && dut.command_sequence==0 && dut.event_type==0,"normal period generated emergency command");
  repeat(4)begin next_key=0;clocks(1);next_key=1;clocks(1);end
  clocks(30);check(dut.carousel_phase[4:3]==1,"contact bounce selected period");
  long_s2;check(dut.carousel_phase[4:3]==1 && dut.barrier_mode==0,"normal long press must have no action");
  short_s2;short_s2;check(dut.carousel_phase[4:3]==0,"normal wrap");
  // A local emergency precedes any B command: S2 must not change period.
  dut.u_ethernet_link.peer_value=21'd1;clocks(3);short_s2;
  check(dut.u_carousel_clock.requested==0 && dut.command_sequence==0,"local A emergency changed normal selection");
  long_s2;check(dut.barrier_mode==1,"existing emergency barrier control lost");
  dut.u_ethernet_link.peer_value=0;key_s4;
  check(dut.emergency && dut.command_sequence==1,"remote emergency toggle lost");
  // Also block period changes while the emergency command is still in flight.
  short_s2;check(dut.event_type==1 && dut.command_sequence==2 && dut.u_carousel_clock.requested==0,"pending remote emergency S2 semantics");
  dut.u_ethernet_link.peer_value=21'd3;clocks(3);long_s2;
  check(dut.barrier_mode==1 && dut.event_type==1,"long emergency press changed event/period");
  key_s3;check(!dut.emergency && dut.event_type==0 && dut.barrier_mode==0 && dut.command_sequence==3,"clear path changed");
  short_s2;check(dut.u_carousel_clock.requested==0,"old actual A emergency cleared too early");
  dut.u_ethernet_link.peer_value=0;clocks(3);short_s2;
  check(dut.u_carousel_clock.requested==1 && dut.command_sequence==3,"period selection after acknowledged clear");
  dut.u_ethernet_link.feedback_value=8'h0a;clocks(3);short_s2;
  check(!dut.carousel_phase[5] && dut.u_carousel_clock.requested==2,"pause selection");
  dut.u_ethernet_link.online_value=0;clocks(3);short_s2;
  check(dut.u_carousel_clock.requested==0 && dut.command_sequence==3,"offline period must not issue commands");
  dut.u_ethernet_link.online_value=1;dut.u_ethernet_link.feedback_value=8'h0e;clocks(3);
  check(dut.carousel_phase[5] && dut.u_carousel_clock.applied==0,"reconnect selected period");
  $display("PASS: real B top and S2 contact debounce/release/long-hold; normal-only period gating, no emergency sequence changes, A-local/remote-pending alarms, event/closure/clear preservation, pause/offline selection");$finish;
 end
 initial begin #60000000;$fatal(1,"period button top timeout");end
endmodule
