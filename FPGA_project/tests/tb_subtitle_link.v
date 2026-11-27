`timescale 1ns/1ps
module ethernet_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,extlock);
 reg divider=0;always @(posedge refclk)divider<=~divider;
 assign clk0_out=divider;assign #10 clk1_out=divider;assign clk2_out=0;assign extlock=1;
endmodule
module tb_subtitle_link #(parameter TEST_BAUD=1000000);
 localparam BIT=(1000000000+TEST_BAUD/2)/TEST_BAUD;
 reg refclk=0,rst_n=0,rx=1,connected=1;always #10 refclk=~refclk;
 reg aclk=0,a90=0,vclk=0;always #20 aclk=~aclk;initial begin #10;forever #20 a90=~a90;end
 always #6.667 vclk=~vclk;
 wire rst=~rst_n;wire tx;wire atxclk,atxctl,btxclk,btxctl;wire [3:0] adata,bdata;wire amdc,bmdc;tri1 amdio,bmdio;
 wire arxclk,b_rxclk;assign #2 arxclk=dut.net_clk;assign #2 b_rxclk=aclk;
 wire aready,bready;phy_model #(.ADDR(1)) pa(.mdc(amdc),.mdio(amdio),.link_enable(connected),.ready(aready));
 phy_model #(.ADDR(3)) pb(.mdc(bmdc),.mdio(bmdio),.link_enable(connected),.ready(bready));
 dual_board_control_top #(.ENABLE_MEDIA(0),.ENABLE_RASTER(0),.ENABLE_REMOTE_TF(0),.UART_BAUD(TEST_BAUD)) dut(
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

 // Actual48k PCM traffic remains highest priority during subtitle upload.
 reg pcm_enable=0,pcm_valid=0;reg [23:0] pcm_sample=0;integer pcm_phase=0,pcm_generated=0,pcm_received=0;
 wire pcm_stream_valid;wire [223:0] pcm_stream_data;reg [23:0] samples[0:131071];integer pk;
 distributed_pcm_sender pcm(.clk(aclk),.rst(rst),.online(ao),.sample_valid(pcm_valid),.sample(pcm_sample),.sample_restart(1'b0),.stream_ready(astready),.stream_valid(pcm_stream_valid),.stream_data(pcm_stream_data));
 always @(negedge aclk)begin
 pcm_valid=0;
 if(pcm_enable)begin pcm_phase=pcm_phase+48000;if(pcm_phase>=25000000)begin pcm_phase=pcm_phase-25000000;pcm_sample=(pcm_generated*12345+24'h13579b)&24'hffffff;samples[pcm_generated]=pcm_sample;pcm_generated=pcm_generated+1;pcm_valid=1;end end
 end
 always @(posedge dut.net_clk)if(dut.received&&dut.incoming_stream[7:0]==1)begin
 for(pk=0;pk<4;pk=pk+1)begin if(dut.incoming_stream[32+pk*24+:24]!==samples[pcm_received])$fatal(1,"PCM mismatch sample%0d",pcm_received);pcm_received=pcm_received+1;end end
 task finish_audio;begin pcm_enable=0;pcm_valid=0;#1000000;
 if(pcm_received!=(pcm_generated/4)*4||pcm_received<1000)$fatal(1,"PCM loss got%0d gen%0d",pcm_received,pcm_generated);
 $display("PASS: concurrent48k exact PCM=%0d while subtitle upload; production priority retained",pcm_received);end endtask
 wire subtitle_ack_valid;wire [223:0] subtitle_ack_packet;
 wire live,sv;wire [223:0] scene;reg pending=0;reg [223:0] held;
 a_map_scene_compute scene_compute(.clk(aclk),.rst(rst),.online(ao),.actual_state(status_net),.packet_valid(av),.packet(packet),
 .controls_live(live),.scene_valid(sv),.scene(scene));
 always @(posedge aclk)if(rst||!ao)pending<=0;else begin if(pending&&astready&&!pcm_stream_valid&&!subtitle_ack_valid)pending<=0;if(sv)begin pending<=1;held<=scene;end end
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12),.BURST_RASTER(1),.SUBTITLE(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) a(
 .clk(aclk),.tx_clk90(a90),.rst(rst),.local_state(status_net),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(8'h2e),
 .eth_rx_clk(arxclk),.eth_rx_ctl(connected?btxctl:1'b0),.eth_rxd(bdata),.eth_tx_clk(atxclk),.eth_tx_ctl(atxctl),.eth_txd(adata),
 .eth_mdc(amdc),.eth_mdio(amdio),.peer_valid(av),.peer_message(ap),.peer_extension(),.peer_online(ao),.phy_configured(ac),.phy_link(al),.tx_active(),
 .stream_valid(pcm_stream_valid||subtitle_ack_valid||pending&&live),.stream_data(pcm_stream_valid?pcm_stream_data:subtitle_ack_valid?subtitle_ack_packet:{12'd0,held[187:8],16'd0,8'd1,8'd14}),.stream_ready(astready),.peer_stream(packet));
 reg video_vs=0;integer vcount=0;
 always @(negedge vclk)if(rst)begin vcount=0;video_vs=0;end else begin vcount=vcount==1249999?0:vcount+1;video_vs=vcount<5;end
 reg [11:0] sx=0,sy=0;wire subactive,subpixel,subbar;integer pixout;
 subtitle_display display(.net_clk(aclk),.net_rst(rst),.packet_valid(av),.packet(packet),.ack_valid(subtitle_ack_valid),.ack_packet(subtitle_ack_packet),.ack_ready(astready&&!pcm_stream_valid),
 .video_clk(vclk),.video_rst(rst),.video_vs(video_vs),.emergency(mode),.x_pre(sx),.y_pre(sy),.custom_active(subactive),.custom_pixel(subpixel),.custom_bar(subbar));
 reg [11:0] aligned_x=0,aligned_y=0;always @(posedge vclk)begin aligned_x<=sx;aligned_y<=sy;end
 wire [23:0] osd_rgb;wire [7:0] osd_alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1)) text(
 .clk(vclk),.rst(rst),.emergency(1'b0),.custom_active(subactive),.custom_pixel(subpixel),.custom_bar(subbar),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),
 .x(aligned_x),.y(aligned_y),.x_pre(sx),.y_pre(sy),.page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
 .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(mode?4'd0:4'd1),.res_str(72'd0),.text_rgb(osd_rgb),.text_alpha(osd_alpha));
 task scan(input integer tag);integer xx,yy,top;begin top=mode?580:680;
 for(yy=top-4;yy<top+36;yy++)for(xx=0;xx<1280;xx++)begin @(negedge vclk);sx=xx;sy=yy;@(posedge vclk);#1;
 $fdisplay(pixout,"%0d %0d %0d %b %b %b %0d %06h %0d",tag,xx,yy,subactive,subpixel,subbar,display.phase,osd_rgb,osd_alpha);end end endtask
 reg binary_mode=0;reg [7:0] reply_bytes[0:8191];integer reply_count=0,replyout;
 reg [7:0] host_frames[0:4289];
 initial begin $readmemh("frames.hex",host_frames);pixout=$fopen("subtitle_pixels.txt","w");replyout=$fopen("binary_reply.hex","w");end
 task rawbyte(input [7:0] v);integer k;begin rx=0;#BIT;for(k=0;k<8;k++)begin rx=v[k];#BIT;end rx=1;#(BIT+BIT/3);end endtask
 task block(input integer frame,input bit corrupt,input [7:0] expected_status);integer j,start;begin
 start=reply_count;for(j=0;j<33;j++)rawbyte(host_frames[frame*33+j]^(corrupt&&j==32?8'd1:8'd0));
 wait(reply_count>=start+10);
 if(reply_bytes[start]!==27||reply_bytes[start+1]!==65||reply_bytes[start+2]!==1||reply_bytes[start+3]!==host_frames[frame*33+6]||reply_bytes[start+7]!==expected_status)
 $fatal(1,"binary frame%0d status=%0d wanted=%0d",frame,reply_bytes[start+7],expected_status);
 end endtask
 task upload;integer j;begin for(j=0;j<130;j++)block(j,0,0);end endtask
 string lines[0:127];string current="";integer line_count=0;integer capture,marks;reg [7:0] got;integer b;
 initial begin capture=$fopen("wire.txt","w");marks=$fopen("marks.txt","w");end
 always @(negedge tx)if(!rst)begin
 #(BIT+BIT/2);for(b=0;b<8;b=b+1)begin got[b]=tx;#BIT;end
 if(tx!==1)$fatal(1,"stop bit");$fwrite(capture,"%c",got);
 if(binary_mode)begin reply_bytes[reply_count]=got;reply_count++;$fdisplay(replyout,"%02h",got);end
 else if(got==10)begin lines[line_count]=current;line_count++;current="";end else if(got!=13)current={current,got};end
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
 #20000;pcm_enable=1;binary_mode=1;block(0,1,2);upload;
 if(!subactive)$fatal(1,"subtitle not activated after wire ACK");scan(0);
 if(TEST_BAUD==115200)begin finish_audio;
  $display("PASS: production115200 UART host bitmap -> actual B top/nativeMAC -> A dual-clockRAM/VS -> compositor pixels; full130frame upload,CRC rejection.");$finish;
 end
 // Duplicate completed commit must ACK without resetting phase or bank.
 block(129,0,0);scan(1);binary_mode=0;#20000;
 request("PING","PONG");
 request("DEMO FIRE","OK REQUEST STATE=1");settled(1);fresh(16'h0080,0);status_read("FIRE");wait(display.emergency_frame);scan(2);
 #20000;binary_mode=1;$readmemh("frames2.hex",host_frames);upload;scan(3);binary_mode=0;#20000;finish_audio;
 request("PING","PONG");
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
 $display("PASS: host Chinese bitmap/CRC/VS/OSD and actual B top UART -> native MAC/PHY -> A command CDC/control/route -> native MAC -> B fresh/closures/exit; 4 events,barrier,no-path,stop/local ownership,disconnect/reconnect,moving camera.");$finish;
 end
 integer acount=0,bcount=0,atcount=0,btcount=0;reg awas=0,bwas=0;integer cap;
 initial cap=$fopen("mac.hex","w");
 always @(posedge aclk)begin if(av)acount++;if(atxctl&&!awas)atcount++;awas=atxctl;end
 always @(posedge dut.net_clk)begin if(dut.received)bcount++;if(btxctl&&!bwas)btcount++;bwas=btxctl;end
 always @(posedge arxclk)if(btcount<3||(btcount==3&&bwas))begin if(btxctl)$fwrite(cap,"%x",bdata);else if(bwas)$fwrite(cap,"\n");end
 initial begin #(64'd2000000000);$fatal(1,"timeout lines=%0d online=%b A=%d desired=%d closed=%h",line_count,dut.online,astate,dut.desired,dut.u_uart_service.last_closed);end
endmodule


