`timescale 1ns/1ps
// Exercise the real B wrapper and real key debouncers. PLL/link models expose
// lock, stopped-clock and peer-telemetry faults; protocol is tested separately
// by tb_endpoints with the actual MAC/RGMII/CRC implementation.
module tb_b_role_display;
 reg clk=0,rst_n=1,key_next=1,key_auto=1,key_emergency=1;
 always #10 clk=~clk;
 wire [5:0] seg_sel;wire [7:0] seg_data;wire [3:0] led;
 wire eth_tx_clk,eth_tx_ctl,eth_mdc,eth_mdio;wire [3:0] eth_txd;
 dual_board_control_top #(.ENABLE_MEDIA(0),.ENABLE_RASTER(0),.ENABLE_REMOTE_TF(0)) dut(.sw(4'b0000),.clk(clk),.rst_n(rst_n),
  .key_next(key_next),.key_auto(key_auto),.key_emergency(key_emergency),
  .eth_rx_clk(1'b0),.eth_rx_ctl(1'b0),.eth_rxd(4'b0),
  .eth_tx_clk(eth_tx_clk),.eth_tx_ctl(eth_tx_ctl),.eth_txd(eth_txd),
  .eth_mdc(eth_mdc),.eth_mdio(eth_mdio),.led(led),.seg_sel(seg_sel),.seg_data(seg_data));
 integer selected_count,j;
 reg [5:0] previous_sel=6'b111111;reg [7:0] previous_data=8'hff;
 // Inspect physical active-low pins, without relying on internal scan counters.
 always @(posedge clk)begin
  #1;
  if(rst_n)begin
   selected_count=0;
   for(j=0;j<6;j=j+1)if(!seg_sel[j])selected_count=selected_count+1;
   if(selected_count>1)$fatal(1,"More than one digit selected");
   if(seg_data!==previous_data && previous_sel!==6'b111111)
    $fatal(1,"Segment data changed before digit blanking");
   if(seg_sel!==6'b111111 && (^seg_data===1'bx))$fatal(1,"Unknown segment data");
  end
  previous_sel=seg_sel;previous_data=seg_data;
 end
 task check_display(input [47:0] expected);
  integer n,k;reg [5:0] seen;
  begin
   #2000000;seen=0;
   for(n=0;n<60000;n=n+1)begin
    @(posedge clk);#2;
    for(k=0;k<6;k=k+1)if(!seg_sel[k])begin
     seen[k]=1;
     if(seg_data!==expected[k*8+:8])
      $fatal(1,"B display digit %0d: actual %02x expected %02x",k,seg_data,expected[k*8+:8]);
    end
   end
   if(seen!==6'b111111)$fatal(1,"Some B digits never scanned");
  end
 endtask
 task pulse_key(input integer which_key);
  begin
   case(which_key)0:key_emergency=0;1:key_next=0;2:key_auto=0;endcase
   #5200000;
   case(which_key)0:key_emergency=1;1:key_next=1;2:key_auto=1;endcase
   #5200000;
  end
 endtask
 initial begin
  #3;rst_n=0;#100;rst_n=1;
  // b C O A E T = b 0 0 0 0 0, with the network clock stopped and no PLL lock.
  check_display(48'hc0c0c0c0c083);
  dut.u_ethernet_pll.run_clock=1;dut.u_ethernet_pll.locked_value=1;
  #1000;dut.u_ethernet_link.configured_value=1;
  dut.u_ethernet_link.online_value=1;
  check_display(48'hc0c0c0f9f983); // b 1 1 0 0 0
  pulse_key(0);
  if(dut.u_ethernet_link.local_state!==3'b001 || dut.u_ethernet_link.local_sequence!==1)
   $fatal(1,"Existing emergency command path changed");
  check_display(48'hc0f9c0f9f983); // b 1 1 0 1 0
  dut.u_ethernet_link.peer_value={1'b0,1'b1,8'd1,8'd0,3'b001};
  check_display(48'hc0f9f9f9f983); // b 1 1 1 1 0
  pulse_key(1);pulse_key(1);
  if(dut.u_ethernet_link.local_state!==3'b101 || dut.u_ethernet_link.local_sequence!==3)
   $fatal(1,"Existing event-step command path changed");
  check_display(48'ha4f9c0f9f983); // b 1 1 0 1 2; old acknowledgement rejected
  dut.u_ethernet_link.online_value=0;
  check_display(48'ha4f9c0c0f983); // b 1 0 0 1 2; link lost, desired state retained
  pulse_key(2);
  if(dut.u_ethernet_link.local_state!==0 || dut.u_ethernet_link.local_sequence!==4)
   $fatal(1,"Existing clear command path changed");
  check_display(48'hc0c0c0c0f983);
  dut.u_ethernet_pll.locked_value=0;dut.u_ethernet_pll.run_clock=0;
  dut.u_ethernet_link.configured_value=0;
  check_display(48'hc0c0c0c0c083); // identity survives clock/lock loss
  rst_n=0;#100;
  if(seg_sel!==6'b111111 || seg_data!==8'hff)$fatal(1,"Reset must blank display");
  rst_n=1;check_display(48'hc0c0c0c0c083);
  $display("PASS: B physical role display, clock/lock loss, blanking, all six digits, real keys, ACK and reset");
  $finish;
 end
 initial begin #200000000;$fatal(1,"B role display timeout");end
endmodule

module ethernet_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,extlock);
 reg divider=0;reg run_clock=0,locked_value=0;
 always @(posedge refclk)divider<=~divider;
 assign clk0_out=run_clock ? divider : 1'b0;
 assign clk1_out=clk0_out;assign clk2_out=1'b0;assign extlock=locked_value;
endmodule

module ethernet_command_link #(parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0)(
 input clk,tx_clk90,rst,input [2:0] local_state,input [7:0] local_sequence,input local_command_active,input [7:0] local_extension,
 input eth_rx_clk,eth_rx_ctl,input [3:0] eth_rxd,
 output eth_tx_clk,eth_tx_ctl,output [3:0] eth_txd,output eth_mdc,inout eth_mdio,
 output peer_valid,output [20:0] peer_message,output [7:0] peer_extension,output peer_online,phy_configured,phy_link,tx_active,
 input stream_valid,input [223:0] stream_data,output stream_ready,output [223:0] peer_stream);
 reg online_value=0,configured_value=0;reg [20:0] peer_value=0;
 assign stream_ready=1;assign peer_stream=0;
 assign peer_extension=0;assign peer_message=peer_value;assign peer_online=online_value;
 assign phy_configured=configured_value;assign peer_valid=0;assign phy_link=online_value;
 assign tx_active=0;assign eth_tx_clk=tx_clk90;assign eth_tx_ctl=0;assign eth_txd=0;
 assign eth_mdc=0;assign eth_mdio=1'bz;
endmodule
