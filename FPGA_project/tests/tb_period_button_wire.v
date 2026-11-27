`timescale 1ns/1ps
module tb_period_button_wire #(parameter RX_DELAY=2);
 reg a_clk=0,b_clk=0,video_clk=0,a90=0,b90=0;
 always #20 a_clk=~a_clk;
 initial begin #3;forever #20 b_clk=~b_clk;end
 initial begin #10;forever #20 a90=~a90;end
 initial begin #13;forever #20 b90=~b90;end
 always #6.667 video_clk=~video_clk;
 reg rst=1,connected=1,local_toggle=0,local_step=0;
 reg b_armed=0;reg [2:0] b_state=0;reg [7:0] b_seq=0;
 wire a_txclk,b_txclk,a_txctl,b_txctl;wire [3:0] a_data,b_data;
 wire #(RX_DELAY) a_rxclk=b_clk;wire #(RX_DELAY) b_rxclk=a_clk;
 wire a_valid,b_valid,a_online,b_online,a_config,b_config,a_link,b_link;
 wire [7:0] a_extension,b_extension;reg [7:0] a_feedback=8'h1e;wire [7:0] b_phase;reg period_step=0;reg [1:0] period_switches=0;
 wire [20:0] a_peer,b_peer;wire a_mdc,b_mdc;tri1 a_mdio,b_mdio;
 wire a_ready,b_ready;wire [2:0] a_state;wire mode;wire [1:0] event_type;
 wire remote_valid;wire [10:0] remote_command;wire [2:0] status_net;wire status_valid;
 phy_model #(.ADDR(1)) phy_a(.mdc(a_mdc),.mdio(a_mdio),.link_enable(connected),.ready(a_ready));
 phy_model #(.ADDR(3)) phy_b(.mdc(b_mdc),.mdio(b_mdio),.link_enable(connected),.ready(b_ready));
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) a(
  .clk(a_clk),.tx_clk90(a90),.rst(rst),.local_state(status_net),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(a_feedback),
  .eth_rx_clk(a_rxclk),.eth_rx_ctl(connected?b_txctl:1'b0),.eth_rxd(b_data),
  .eth_tx_clk(a_txclk),.eth_tx_ctl(a_txctl),.eth_txd(a_data),.eth_mdc(a_mdc),.eth_mdio(a_mdio),
  .peer_valid(a_valid),.peer_message(a_peer),.peer_extension(a_extension),.peer_online(a_online),.phy_configured(a_config),.phy_link(a_link),.tx_active(),.stream_valid(1'b0),.stream_data(224'd0),.stream_ready(),.peer_stream());
 ethernet_command_link #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) b(
  .clk(b_clk),.tx_clk90(b90),.rst(rst),.local_state(b_state),.local_sequence(b_seq),.local_command_active(b_armed),.local_extension(b_phase),
  .eth_rx_clk(b_rxclk),.eth_rx_ctl(connected?a_txctl:1'b0),.eth_rxd(a_data),
  .eth_tx_clk(b_txclk),.eth_tx_ctl(b_txctl),.eth_txd(b_data),.eth_mdc(b_mdc),.eth_mdio(b_mdio),
  .peer_valid(b_valid),.peer_message(b_peer),.peer_extension(b_extension),.peer_online(b_online),.phy_configured(b_config),.phy_link(b_link),.tx_active(),.stream_valid(1'b0),.stream_data(224'd0),.stream_ready(),.peer_stream());
 ethernet_mailbox #(.WIDTH(11)) commands(.src_clk(a_clk),.src_rst(rst),.src_valid(a_valid && a_peer[20]),.src_data(a_peer[10:0]),.src_ready(),
  .dst_clk(video_clk),.dst_rst(rst),.dst_valid(remote_valid),.dst_data(remote_command));
 dual_board_emergency_control control(.clk(video_clk),.rst(rst),.local_toggle(local_toggle),.local_event_step(local_step),
  .remote_valid(remote_valid),.remote_command(remote_command),.emergency_mode(mode),.emergency_event(event_type));
 assign a_state={event_type,mode};
 ethernet_mailbox #(.WIDTH(3)) status(.src_clk(video_clk),.src_rst(rst),.src_valid(1'b1),.src_data(a_state),.src_ready(),
  .dst_clk(a_clk),.dst_rst(rst),.dst_valid(status_valid),.dst_data(status_net));
 distributed_carousel_clock #(.CLK_FREQ_HZ(1000)) scheduler(.clk(b_clk),.rst(rst),
  .switches(period_switches),.period_step(period_step),.online(b_online),
  .feedback(b_extension[4:0]),.actual_emergency(b_peer[0]),.phase(b_phase));
 wire [8:0] delivered_phase;
 ethernet_mailbox #(.WIDTH(9)) phase_cdc(.src_clk(a_clk),.src_rst(rst),.src_valid(1'b1),
  .src_data({a_online,a_extension}),.src_ready(),.dst_clk(video_clk),.dst_rst(rst),
  .dst_valid(),.dst_data(delivered_phase));
 wire [1:0] period_ui=delivered_phase[8]?delivered_phase[4:3]:2'd0;
 reg [11:0] x=0,y=0,xp=0,yp=0;wire [23:0] rgb;wire [7:0] alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.ENABLE_PERIOD_OSD(1)) text(
  .clk(video_clk),.rst(rst),.emergency(1'b0),.blink_on(1'b0),.x(x),.y(y),.x_pre(xp),.y_pre(yp),
  .page_index(3'd2),.brightness(3'd4),.contrast(3'd4),.interval_selection(period_ui),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),
  .feature_mask(4'b0100),.res_str(" 640X 480"),.text_rgb(rgb),.text_alpha(alpha));
 text_overlay_link_baseline reference(.clk(video_clk),.rst(rst),.emergency(1'b0),
  .blink_on(1'b0),.x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(3'd2),
  .brightness(3'd4),.contrast(3'd4),.elapsed_seconds(7'd0),.scroll_phase(12'd0),
  .feature_mask(4'b0100),.res_str(" 640X 480"));
 integer ci,row,col,glyphs=0;reg [7:0] ch,glyph;
 task verify_osd;
  begin
   for(ci=0;ci<4;ci=ci+1)for(row=0;row<8;row=row+1)for(col=0;col<8;col=col+1)begin
    case(ci)0:ch="T";1:ch=period_ui==2?"1":"0";
     2:ch=period_ui==2?"0":(period_ui==1?"5":"3");3:ch="S";endcase
    glyph=reference.font_row(ch,row);
    @(negedge video_clk);xp=976+ci*16+col*2;yp=48+row*2;
    @(posedge video_clk);#1;x=xp;y=yp;#1;
    if(rgb!==(glyph[7-col]?24'hffffff:24'h12385a) || alpha!==(glyph[7-col]?8'd255:8'd180))
     $fatal(1,"Ethernet period OSD pixel mismatch");
    glyphs=glyphs+1;
   end
  end
 endtask
 task press_and_check(input [1:0] expected);
  begin
   @(negedge b_clk);period_step=1;@(negedge b_clk);period_step=0;
   wait(period_ui==expected);verify_osd;
   if(b_seq!=0 || mode || b_armed)$fatal(1,"period packet issued alarm command");
  end
 endtask
 integer count_a=0,count_b=0;
 always @(posedge a_clk)if(a_valid)count_a=count_a+1;
 always @(posedge b_clk)if(b_valid)count_b=count_b+1;
 initial begin
  #300;rst=0;
  wait(a_online && b_online && b_phase[5]);wait(period_ui==0);verify_osd;
  press_and_check(1);press_and_check(2);press_and_check(0);
  @(negedge a_clk);a_feedback=8'h1a;wait(!b_phase[5]);press_and_check(1);
  @(negedge a_clk);a_feedback=8'h1e;wait(b_phase[5]);
  connected=0;wait(!a_online && !b_online);wait(!delivered_phase[8]);
  if(period_ui!=0)$fatal(1,"offline OSD must report local 3s");
  @(negedge b_clk);period_step=1;@(negedge b_clk);period_step=0;
  repeat(5)@(negedge b_clk);if(scheduler.requested!=2)$fatal(1,"offline selection lost");
  connected=1;wait(a_online && b_online && b_phase[5]);wait(period_ui==2);verify_osd;
  if(glyphs!=1536)$fatal(1,"OSD pixel comparison count");
  $display("PASS: v4 real RGMII/MDIO/CRC, independent clocks and %0dns RX skew; B button-selected periods to A phase CDC; 1536 exact OSD RGB/alpha pixels; pause, disconnect local 3s, selected 10s reconnect; no alarm commands",RX_DELAY);$finish;
 end
 initial begin #15000000;$fatal(1,"FAIL: endpoint timeout config=%b%b link=%b%b online=%b%b packets=%0d/%0d",a_config,b_config,a_link,b_link,a_online,b_online,count_a,count_b);end
endmodule
