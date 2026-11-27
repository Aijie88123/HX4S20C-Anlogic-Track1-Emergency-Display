`timescale 1ns/1ps
module ethernet_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,extlock);
 reg divider=0;always @(posedge refclk)divider<=~divider;
 assign clk0_out=divider;assign #10 clk1_out=divider;assign clk2_out=0;assign extlock=1;
endmodule
module tb_uart_link;
 localparam BIT=1000;
 reg refclk=0,rst_n=0,rx=1,connected=1;always #10 refclk=~refclk;
 reg aclk=0,a90=0,vclk=0;always #20 aclk=~aclk;initial begin #10;forever #20 a90=~a90;end
 always #6.667 vclk=~vclk;
 wire rst=~rst_n;wire tx;wire atxclk,atxctl,btxclk,btxctl;wire [3:0] adata,bdata;wire amdc,bmdc;tri1 amdio,bmdio;
 wire arxclk,b_rxclk;assign #2 arxclk=dut.net_clk;assign #2 b_rxclk=aclk;
 wire aready,bready;phy_model #(.ADDR(1)) pa(.mdc(amdc),.mdio(amdio),.link_enable(connected),.ready(aready));
 phy_model #(.ADDR(3)) pb(.mdc(bmdc),.mdio(bmdio),.link_enable(connected),.ready(bready));
 dual_board_control_top #(.ENABLE_MEDIA(0),.ENABLE_RASTER(0),.ENABLE_REMOTE_TF(0),.UART_BAUD(1000000)) dut(
 .clk(refclk),.rst_n(rst_n),.key_next(1'b1),.key_auto(1'b1),.key_emergency(1'b1),.sw(4'd0),.uart_rx(rx),.uart_tx(tx),
 .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.eth_rx_clk(b_rxclk),.eth_rx_ctl(connected?atxctl:1'b0),.eth_rxd(adata),
 .eth_tx_clk(btxclk),.eth_tx_ctl(btxctl),.eth_txd(bdata),.eth_mdc(bmdc),.eth_mdio(bmdio),.led(),.seg_sel(),.seg_data());
 defparam dut.u_ethernet_link.BOOT_CYCLES=8;
 defparam dut.u_ethernet_link.HEARTBEAT_CYCLES=5000;
 defparam dut.u_ethernet_link.TIMEOUT_TICKS=3;
 // Keep the production V12 wire format while omitting bulk media backing RAM.
 defparam dut.u_ethernet_link.RAW_TF=1;
 defparam dut.u_ethernet_link.MEDIA=1;
 defparam dut.u_ethernet_link.RASTER=1;
 wire av,ao,ac,al;wire [20:0] ap;wire [223:0] packet;wire astready;wire [2:0] astate,status_net;
 wire mode;wire [1:0] event_type;wire remote_valid;wire [10:0] remote_command;
 reg local_toggle=0;
 ethernet_mailbox #(.WIDTH(11)) commands(.src_clk(aclk),.src_rst(rst),.src_valid(av&&ap[20]),.src_data(ap[10:0]),.src_ready(),
 .dst_clk(vclk),.dst_rst(rst),.dst_valid(remote_valid),.dst_data(remote_command));
 dual_board_emergency_control ctrl(.clk(vclk),.rst(rst),.local_toggle(local_toggle),.local_event_step(1'b0),
 .remote_valid(remote_valid),.remote_command(remote_command),.emergency_mode(mode),.emergency_event(event_type));
 assign astate={event_type,mode};
 ethernet_mailbox #(.WIDTH(3)) status(.src_clk(vclk),.src_rst(rst),.src_valid(1'b1),.src_data(astate),.src_ready(),
 .dst_clk(aclk),.dst_rst(rst),.dst_valid(),.dst_data(status_net));
 wire live,sv;wire [223:0] scene;reg pending=0;reg [223:0] held;
 a_map_scene_compute scene_compute(.clk(aclk),.rst(rst),.online(ao),.actual_state(status_net),.packet_valid(av),.packet(packet),
 .controls_live(live),.scene_valid(sv),.scene(scene));
 always @(posedge aclk)if(rst||!ao)pending<=0;else begin if(pending&&astready)pending<=0;if(sv)begin pending<=1;held<=scene;end end
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12),.BURST_RASTER(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) a(
 .clk(aclk),.tx_clk90(a90),.rst(rst),.local_state(status_net),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(8'h2e),
 .eth_rx_clk(arxclk),.eth_rx_ctl(connected?btxctl:1'b0),.eth_rxd(bdata),.eth_tx_clk(atxclk),.eth_tx_ctl(atxctl),.eth_txd(adata),
 .eth_mdc(amdc),.eth_mdio(amdio),.peer_valid(av),.peer_message(ap),.peer_extension(),.peer_online(ao),.phy_configured(ac),.phy_link(al),.tx_active(),
 .stream_valid(pending&&live),.stream_data({12'd0,held[187:8],16'd0,8'd1,8'd14}),.stream_ready(astready),.peer_stream(packet));
 string lines[0:127];string current="";integer line_count=0;integer capture,marks;reg [7:0] got;integer b;
 initial begin capture=$fopen("wire.txt","w");marks=$fopen("marks.txt","w");end
 always @(negedge tx)if(!rst)begin
 #(BIT+BIT/2);for(b=0;b<8;b=b+1)begin got[b]=tx;#BIT;end
 if(tx!==1)$fatal(1,"stop bit");$fwrite(capture,"%c",got);
 if(got==10)begin lines[line_count]=current;line_count++;current="";end else if(got!=13)current={current,got};end
 task command(input string s);integer k,j;begin #13;
 for(k=0;k<=s.len();k++)begin rx=0;#BIT;for(j=0;j<8;j++)begin rx=k==s.len()?((10>>j)&1):((s[k]>>j)&1);#BIT;end rx=1;#(BIT+BIT/3);end end endtask
 task request(input string s,input string expected);integer start;begin start=line_count;command(s);wait(line_count>start);if(lines[start]!=expected)$fatal(1,"%s got %s",s,lines[start]);end endtask
 task status_read(input string mark);integer start;begin start=line_count;command("STATUS?");wait(line_count>start);$fdisplay(marks,"%s %0d",mark,start);end endtask
 task settled(input [2:0] state);begin wait(dut.peer[2:0]==state&&dut.acknowledged);if(astate!==state)$fatal(1,"actual A state mismatch");end endtask
 task fresh(input [15:0] closed,input bit no_path);begin wait(dut.u_uart_service.fresh&&dut.u_uart_service.last_closed==closed&&dut.u_uart_service.last_no_path==no_path);end endtask
 task toggle;begin @(negedge vclk);local_toggle=1;@(negedge vclk);local_toggle=0;end endtask
 integer old_seq,rev;reg [23:0] old_origin;
 initial begin #300;rst_n=1;wait(ao&&dut.online&&aready&&bready);
 request("PING","PONG");status_read("NORMAL");
 request("DEMO FIRE","OK REQUEST STATE=1");settled(1);fresh(16'h0080,0);status_read("FIRE");
 old_seq=dut.command_sequence;request("BARRIER SET 2","OK REQUEST BARRIER=2");fresh(16'hc080,0);status_read("BARRIER2");if(dut.command_sequence!=old_seq)$fatal(1,"barrier changed emergency sequence");
 request("BARRIER SET 3","OK REQUEST BARRIER=3");fresh(16'hf080,1);status_read("NO_ROUTE");
 request("DEMO QUAKE","OK REQUEST STATE=3");settled(3);fresh(16'h0001,0);status_read("QUAKE");
 request("DEMO LAB","OK REQUEST STATE=5");settled(5);fresh(16'h0400,0);status_read("LAB");
 request("DEMO DRILL","OK REQUEST STATE=7");settled(7);fresh(16'h0020,0);status_read("DRILL");
 rev=dut.u_uart_service.route_revision;old_origin=scene[55:32];
 #40000000;if(dut.u_uart_service.route_revision!=rev)$fatal(1,"moving camera inflated route revision");
 if(scene[55:32]===old_origin)$fatal(1,"real A camera did not move");
 request("DEMO STOP","OK REQUEST STATE=0");settled(0);status_read("STOP");
 toggle;wait(dut.peer[0]);request("DEMO STOP","OK REQUEST STATE=0");#1000000;
 if(astate!=1||dut.acknowledged)$fatal(1,"UART STOP overrode A local ownership");status_read("LOCAL_RETAINED");toggle;wait(!dut.peer[0]);
 connected=0;wait(!dut.online);request("DEMO FIRE","ERR LINK_OFFLINE");status_read("OFFLINE");connected=1;wait(ao&&dut.online);
 request("DEMO LAB","OK REQUEST STATE=5");settled(5);fresh(16'h0400,0);status_read("RECONNECTED");
 status_read("FINAL");
 $display("PASS: actual B top UART -> native MAC/PHY -> A command CDC/control/route -> native MAC -> B fresh/closures/exit; 4 events,barrier,no-path,stop/local ownership,disconnect/reconnect,moving camera.");$finish;
 end
 integer acount=0,bcount=0,atcount=0,btcount=0;reg awas=0,bwas=0;integer cap;
 initial cap=$fopen("mac.hex","w");
 always @(posedge aclk)begin if(av)acount++;if(atxctl&&!awas)atcount++;awas=atxctl;end
 always @(posedge dut.net_clk)begin if(dut.received)bcount++;if(btxctl&&!bwas)btcount++;bwas=btxctl;end
 always @(posedge arxclk)if(btcount<3||(btcount==3&&bwas))begin if(btxctl)$fwrite(cap,"%x",bdata);else if(bwas)$fwrite(cap,"\n");end
 initial begin #(64'd300000000);$fatal(1,"timeout lines=%0d online=%b A=%d desired=%d closed=%h",line_count,dut.online,astate,dut.desired,dut.u_uart_service.last_closed);end
endmodule


