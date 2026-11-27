`timescale 1ns/1ps
module tb_manual_animation_top;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 dual_board_control_top dut(.clk(clk),.rst_n(rst_n),.key_next(1'b1),.key_auto(1'b1),.key_emergency(1'b1),.sw(4'd0),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.eth_rx_clk(1'b0),.eth_rx_ctl(1'b0),.eth_rxd(4'd0),
  .eth_tx_clk(),.eth_tx_ctl(),.eth_txd(),.eth_mdc(),.eth_mdio(),.led(),.seg_sel(),.seg_data());
 wire net=dut.net_clk;wire av,wrq,cancel,wen,cv,ca,cr;
 reg nk=1,ak=1,vs=0,source_complete=0;reg [2:0] source_role=2;integer ticks=0;
 wire [4:0] feedback;wire normal_animation,map_ready,autoplay,showing_animation;wire [2:0] page;
 wire source_ready;
 always @(negedge net)begin ticks=ticks+1;vs=ticks%20<3;end
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) controls(
  .animation_visible(showing_animation),
  .clk(net),.rst(!rst_n),.key_next(nk),.key_auto(ak),.emergency(dut.u_ethernet_link.emergency),.vsync(vs),.remote_phase(9'd0),
  .incoming_complete(source_complete),.incoming_role(source_role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(source_ready),
  .staging_slot(),.display_slot(),.display_valid(),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(autoplay),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(),.state_code(),.emergency_map_ready(map_ready),.normal_animation(normal_animation));
 map_received_frame_control #(.NORMAL_ANIMATION(1)) displayed(
  .clk(net),.rst(!rst_n),.vsync(vs),.emergency(dut.u_ethernet_link.emergency && map_ready),.event_type(2'd0),
  .complete(cv),.incoming_event(2'd0),.commit_ready(cr),.incoming_animation(ca),.animation_requested(normal_animation),
  .staging_slot(),.display_slot(),.map_mode(showing_animation),.have_map());
 task deliver(input [2:0] role);begin
  @(negedge net);source_role=role;source_complete=1;wait(source_ready);@(posedge net);@(negedge net);source_complete=0;repeat(20)@(negedge net);
 end endtask
 task next;begin @(negedge net);nk=0;repeat(12)@(negedge net);nk=1;repeat(35)@(negedge net);end endtask
 task pause_resume;begin @(negedge net);ak=0;repeat(12)@(negedge net);ak=1;repeat(35)@(negedge net);end endtask
 wire [223:0] ap;wire [31:0] wd;
 reg ack=0,done=0;integer writes=0,commits=0,normal_frames=0,map_frames=0,last_frame=-1;
 raster_map_window_receiver #(.ALLOW_ANIMATION(1)) receiver(.clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(dut.stream_valid&&dut.stream_ready),.packet(dut.outgoing_stream),.ack_valid(av),.ack_packet(ap),.ack_ready(1'b1),
  .write_cancel(cancel),.write_req(wrq),.write_ack(ack),.write_full(1'b0),.write_done_toggle(done),.write_en(wen),.write_data(wd),
  .commit_valid(cv),.commit_ready(cr),.commit_event(),.commit_animation(ca));
 always @(posedge net)begin
  if(rst_n && dut.u_ethernet_link.emergency && !map_ready && dut.media_service.rendered_map.active_sync[1])$fatal(1,"actual B renderer enabled before A prelude completion");
  dut.u_ethernet_link.ack_in<=av;dut.u_ethernet_link.ack_data<=ap;ack<=wrq;
  if(cancel || wrq)writes<=0;
  if(wen)begin writes<=writes+1;if(writes==115199)done<=~done;end
  if(cv && cr)begin
   if(writes!=115200)$fatal(1,"partial top frame");commits<=commits+1;
   if(ca)begin
    if(dut.media_service.animation_frame>=84)$fatal(1,"invalid animation frame index");
    normal_frames<=normal_frames+1;
   end else map_frames<=map_frames+1;
  end
 end
 integer marker_scans=0;
 always @(posedge clk)if(rst_n && dut.seg_sel==6'b111110)begin
  if(dut.seg_data!==8'h83)$fatal(1,"B role marker changed");marker_scans<=marker_scans+1;
 end
 integer prior_count;
 initial begin
  force dut.media_service.available=6'b100000;
  force dut.u_ethernet_link.feedback={1'b0,normal_animation,map_ready,feedback};
  force dut.media_service.u_storage.sd_ready=0;
  // Accelerate only the inter-frame wall clock, retain actual frame/owner logic.
  force dut.media_service.animation_clock=0;
  // A still-image sender can own SDRAM longer than the animation watchdog.
  force dut.media_service.read_owned=1;
  force dut.media_service.read_owner=0;
  repeat(30)@(negedge net);rst_n=1;wait(dut.media_service.u_storage.initialized);
  $readmemh("../assets/normal_animation_v2/animation_words.hex",dut.media_service.u_storage.U3.ram,1536000,1843199);
  deliver(2);deliver(3);deliver(4);deliver(0);deliver(1);
  pause_resume;next;next;next;
  if(!normal_animation || autoplay || !feedback[2])$fatal(1,"first paused animation visit was not primed");
  repeat(3000000)@(negedge net);
  if(dut.media_service.animation_fault || dut.media_service.rendered_map.u_animation.state!=0)
   $fatal(1,"legitimate shared SDRAM ownership incorrectly triggers animation watchdog");
  release dut.media_service.read_owned;
  release dut.media_service.read_owner;
  wait(normal_frames>=1);wait(!dut.media_service.map_busy);repeat(1000)@(negedge net);prior_count=commits;
  repeat(10000)@(negedge net);
  if(commits!=prior_count || autoplay || !showing_animation)$fatal(1,"first animation frame did not settle in PAUSE");
  pause_resume;
  wait(normal_frames==3);
  pause_resume;if(autoplay)$fatal(1,"A S3 failed to pause");
  wait(!dut.media_service.map_busy);repeat(1000)@(negedge net);prior_count=commits;
  repeat(10000)@(negedge net);if(commits!=prior_count)$fatal(1,"A pause did not stop actual B sender");
  if(!showing_animation)$fatal(1,"pause hid completed A frame");
  next;repeat(25)@(negedge net);if(page!=2 || normal_animation || showing_animation)$fatal(1,"A S2 failed to leave animation while paused page=%d normal=%b shown=%b pending=%b",page,normal_animation,showing_animation,controls.manual_pending);
  next;next;next;if(page!=4 || !normal_animation || autoplay)$fatal(1,"manual return to paused animation");
  pause_resume;wait(normal_frames>=5);
  // Leave a playing animation with a frame in flight; its late commit cannot
  // cover the new static page. B remains responsible for all raster pixels.
  wait(dut.media_service.map_busy);next;
  repeat(25)@(negedge net);if(page!=2 || normal_animation || showing_animation)$fatal(1,"late raster overlays selected01");
  pause_resume;wait(!dut.media_service.map_busy);repeat(1000)@(negedge net);
  if(showing_animation || dut.media_service.animation_fault)$fatal(1,"midframe manual exit caused a fault");
  next;next;next;pause_resume;wait(normal_frames>=6);
  @(negedge net);dut.u_ethernet_link.emergency=1;
  wait(page==0);if(map_ready)$fatal(1,"map overtook05");
  wait(page==1);if(map_ready)$fatal(1,"map overtook06");wait(map_ready);
  wait(map_frames==1);
  if(marker_scans<100 || dut.media_service.animation_fault)$fatal(1,"B regression");
  $display("PASS: real A S2/S3/cache controller drives production B ANIM02 cache/sender, pauses after complete current frame, resumes, manual exit/re-entry including midframe exit cannot expose late raster, emergency prelude gates actual B shader; complete A SDRAM receiver and VS frame control");$finish;
 end
 initial begin #1000000000;$fatal(1,"B top timeout frames=%d owner=%d sender=%d decoder=%d",normal_frames,dut.media_service.read_owner,dut.media_service.rendered_map.u_raster_sender.state,dut.media_service.rendered_map.u_animation.state);end
endmodule
