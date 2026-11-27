`timescale 1ns/1ps
module tb_native_smooth_steady #(parameter MAP_TEST=0);localparam BURST=1,LOSS=0;
 reg clk=0,rst=1;always #20 clk=~clk;reg render_clk=0;always #10 render_clk=~render_clk;
 reg enabled=0,particle=!MAP_TEST,run_animation=1;wire [187:0] scene;wire scene_valid,scene_ready;wire [223:0] computed_scene,controls,controls_rx,scene_rx;wire control_valid,control_ready,controls_valid_rx;wire [3:0] ctl_nib,scene_nib;wire ctl_busy,scene_busy;
 b_map_control_sender #(.UPDATE_CYCLES(1000000)) controls_b(.clk(clk),.rst(rst),.online(1'b1),.actual_state(3'd1),.switches(2'd0),.barrier_mode(2'd0),.stream_ready(!ctl_busy),.stream_valid(control_valid),.stream_data(controls));
 a_map_scene_compute #(.CLK_HZ(50000000),.FRAME_CYCLES(416667)) scene_a(.clk(clk),.rst(rst),.online(1'b1),.actual_state(3'd1),.packet_valid(controls_valid_rx),.packet(controls_rx),.controls_live(),.scene_valid(scene_ready),.scene(computed_scene));
 wire [223:0] scene_wire={12'd0,computed_scene[187:8],16'd0,8'd1,8'd14};
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) control_tx(.clk(clk),.rst(rst),.start(control_valid&&!ctl_busy),.message(21'd0),.extension(8'd0),.stream_data(controls),.busy(ctl_busy),.nibble(ctl_nib));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) control_rx(.clk(clk),.rst(rst),.nibble(ctl_nib),.valid(ctl_busy),.error(1'b0),.packet_valid(controls_valid_rx),.message(),.extension(),.stream_data(controls_rx));
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) scene_tx(.clk(clk),.rst(rst),.start(scene_ready&&!scene_busy),.message(21'd0),.extension(8'd0),.stream_data(scene_wire),.busy(scene_busy),.nibble(scene_nib));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) scene_rx_mac(.clk(clk),.rst(rst),.nibble(scene_nib),.valid(scene_busy),.error(1'b0),.packet_valid(scene_valid),.message(),.extension(),.stream_data(scene_rx));
 reg [187:0] frozen_scene=0;reg scene_captured=0;
 always @(posedge clk)if(scene_valid && !scene_captured)begin frozen_scene<={scene_rx[211:32],8'd3};scene_captured<=1;end
 assign scene=frozen_scene;
 wire wr_req,wr_en,wr_cancel,frame_valid,consumed,frame_animation;wire [31:0] wr_data;wire [1:0] event_type;wire [8:0] motion;
 reg wr_done=0;reg [31:0] bmem[0:115199],amem[0:115199];integer nw=0,na=0,frames=0,ticks=0;
 b_map_frame_renderer_vga renderer(.clk(render_clk),.rst(rst),.enabled(enabled),.particle_mode(particle),.animation_run(run_animation),.scene_valid(scene_valid),.scene(scene),
  .frame_animation(frame_animation),.motion_phase(motion),.write_req(wr_req),.write_ack(wr_req),.write_full(1'b0),.write_done_toggle(wr_done),
  .write_en(wr_en),.write_data(wr_data),.write_cancel(wr_cancel),.frame_valid(frame_valid),.frame_event(event_type),.frame_consumed(consumed));
 // Deterministic frame phase independently reproduced by the Python model.
 reg [8:0] test_phase=0;initial force renderer.frame_phase=test_phase;
 reg [31:0] golden[0:691199];initial if(MAP_TEST)$readmemh("native_steady_map.hex",golden);else $readmemh("native_steady_particles.hex",golden);
 wire req,pair_en,pair_empty,raw_en;wire [31:0] pair_data;reg [31:0] raw_data;integer raw_index=0;
 rgb444_pair_reader expand(.clk(clk),.rst(rst),.start(req),.raw_ack(req),.raw_empty(raw_index>=115200),.raw_data(raw_data),.raw_en(raw_en),.pair_en(pair_en),.pair_empty(pair_empty),.pair_data(pair_data));
 wire sv,sr,av,ar;wire [223:0] sp,ap,bp,pa;wire b2a,a2b;
 wire [3:0] forward_nibble,ack_nibble;wire forward_busy,ack_busy;reg [4:0] gap=0,ack_gap=0;
 integer packets=0,dropped=0;integer wire_frames=0,wire_nibbles=0;reg previous_busy=0;
 wire forward_start=!forward_busy && gap==0;
 assign ar=!ack_busy && ack_gap==0;
 wire [9:0] tx_position;
 wire inject=LOSS && !dropped && sender.phase==5 && forward_busy &&
   tx_position==100;
 generate if(BURST)begin: burst_wire
  assign tx_position=transmitter.position;
  ethernet_raster_burst_tx transmitter(.clk(clk),.rst(rst),.online(1'b1),.may_start(forward_start),.control_pending(1'b0),
   .message(21'd0),.extension(8'd0),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),.control_sent(),.busy(forward_busy),.nibble(forward_nibble));
  wire mail_ready,rx_valid;wire [223:0] rx_payload;
  ethernet_raster_burst_rx receiver(.clk(clk),.rst(rst),.nibble(forward_nibble^(inject?4'd1:4'd0)),.valid(forward_busy),.error(1'b0),.output_ready(mail_ready),
   .packet_valid(rx_valid),.message(),.extension(),.stream_data(rx_payload));
  ethernet_mailbox #(.WIDTH(224)) mailbox(.src_clk(clk),.src_rst(rst),.src_valid(rx_valid),.src_data(rx_payload),.src_ready(mail_ready),
   .dst_clk(clk),.dst_rst(rst),.dst_valid(b2a),.dst_data(bp));
 end else begin: legacy_wire
  assign tx_position={2'd0,transmitter.position};
  assign sr=forward_start;
  ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) transmitter(
   .clk(clk),.rst(rst),.start(sv&&sr),.message(21'd0),.extension(8'd0),.stream_data(sp),.busy(forward_busy),.nibble(forward_nibble));
  ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) receiver(
   .clk(clk),.rst(rst),.nibble(forward_nibble^(inject?4'd1:4'd0)),.valid(forward_busy),.error(1'b0),.packet_valid(b2a),.message(),.extension(),.stream_data(bp));
 end endgenerate
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) ack_tx(
  .clk(clk),.rst(rst),.start(av&&ar),.message(21'd0),.extension(8'd0),.stream_data(ap),.busy(ack_busy),.nibble(ack_nibble));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(12)) ack_rx(
  .clk(clk),.rst(rst),.nibble(ack_nibble),.valid(ack_busy),.error(1'b0),.packet_valid(a2b),.message(),.extension(),.stream_data(pa));
 always @(posedge clk)begin
  if(forward_busy)begin gap<=24;wire_nibbles<=wire_nibbles+1;end else if(gap!=0)gap<=gap-1'b1;
  if(ack_busy)ack_gap<=24;else if(ack_gap!=0)ack_gap<=ack_gap-1'b1;
  if(sv&&sr)packets<=packets+1;
  if(inject)dropped<=1;
  previous_busy<=forward_busy;if(forward_busy&&!previous_busy)wire_frames<=wire_frames+1;
 end
 raster_map_window_sender #(.PIXELS(307200),.ANIMATION_PIXELS(307200),.ALLOW_ANIMATION(1),.NATIVE_VGA(1),.WINDOW_LOG2(BURST?4:2),.FAST_SOURCE(BURST),.DATA_RETRY_CYCLES(50000)) sender(
  .clk(clk),.rst(rst),.online(1'b1),.frame_valid(frame_valid),.frame_event(event_type),.frame_consumed(consumed),.frame_animation(frame_animation),.current_animation(),
  .packet_valid(a2b),.packet(pa),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),.read_req(req),.read_en(pair_en),.read_busy(),.read_ack(req),.read_empty(pair_empty),.read_data(pair_data));
 wire rq,re,cancel,commit,anim;wire [31:0] rd;wire [1:0] cev;reg adone=0;reg commit_ready=0;
 wire full=ticks%79==7 || ticks%79==8 || ticks%79==9;
 raster_map_window_receiver #(.PIXELS(307200),.ANIMATION_PIXELS(307200),.ALLOW_ANIMATION(1),.NATIVE_VGA(1),.DECODE_ACK(BURST),.WINDOW_LOG2(BURST?4:2)) receiver(
  .clk(clk),.rst(rst),.online(1'b1),.packet_valid(b2a),.packet(bp),.ack_valid(av),.ack_packet(ap),.ack_ready(ar),
  .write_cancel(cancel),.write_req(rq),.write_ack(rq),.write_full(full),.write_done_toggle(adone),.write_en(re),.write_data(rd),
  .commit_valid(commit),.commit_ready(commit_ready),.commit_event(cev),.commit_animation(anim));
 integer i,j,diversity;integer out;time last_commit=0;integer cadence=0;reg [2:0] last_retries=0;
 always @(posedge clk)begin
  last_retries<=sender.retries;
  if(BURST && sender.retries!=0 && sender.retries!=last_retries)$display("RETRY: ticks=%0d base=%0d sent=%0d built=%0d next=%0d decode=%0d count=%0d states=%0d/%0d",ticks,sender.base_index,sender.sent_limit,sender.build_index,receiver.next_index,receiver.decoder.next_index,receiver.count,receiver.qstate,receiver.decoder.state);
  if(BURST && b2a && bp[7:0]==7 && !bp[31] && bp[47:32]==receiver.next_index && receiver.count>=16)$display("OVERFLOW: index=%0d",bp[47:32]);
 end
 time ready_at;reg ready_before=0;
 always @(posedge clk)begin ready_before<=frame_valid;if(frame_valid&&!ready_before)ready_at<=$time;end
 always @(posedge render_clk)begin
  if(MAP_TEST && renderer.state==3 && (renderer.u_renderer.flow!==((frames+1)*3) || renderer.active_scene!==frozen_scene))$fatal(1,"map phase/scene changed inside raster frame");
  if(wr_req)nw<=0;
  if(wr_en)begin
   if(nw>=115200)$fatal(1,"native B frame overrun");
   if(wr_data!==golden[frames*115200+nw])$fatal(1,"native independent shader/packing mismatch word=%0d got=%h expected=%h",nw,wr_data,golden[frames*115200+nw]);
   bmem[nw]=wr_data;nw<=nw+1;if(nw==115199)wr_done<=~wr_done;
  end
 end
 always @(posedge clk)begin
  ticks<=ticks+1;commit_ready<=commit && ticks%416667==0;
  if(req)raw_index<=0;else if(raw_en)begin raw_data<=bmem[raw_index];raw_index<=raw_index+1;end
  if(rq)na<=0;
  if(re)begin
   if(na>=115200 || rd!==bmem[na])$fatal(1,"B->A exact native RGB444 word mismatch %0d got=%h expected=%h",na,rd,bmem[na]);
   amem[na]=rd;na<=na+1;if(na==115199)adone<=~adone;
  end
  if(commit && commit_ready)begin
   if(last_commit!=0)begin
    if($time-last_commit<33000000 || $time-last_commit>34000000)$fatal(1,"cadence gap %0d",$time-last_commit);
    cadence<=cadence+1;
   end
   last_commit<=$time;
   if(na!=115200)$fatal(1,"partial native frame commit %0d",na);

   begin
    frames<=frames+1;test_phase<=test_phase+2;
    out=$fopen("native_steady_last.hex","w");
    for(i=0;i<115200;i=i+1)$fdisplay(out,"%08h",amem[i]);$fclose(out);
    $display("FRAME: burst=%0d loss=%0d animation=%0d words=%0d packets=%0d ticks=%0d transfer_ns=%0d wire_frames=%0d wire_nibbles=%0d",BURST,LOSS,anim,na,packets,ticks,$time-ready_at,wire_frames,wire_nibbles);
   end
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst=0;wait(scene_captured);repeat(4)@(negedge clk);if(MAP_TEST)wait(renderer.have_scene && renderer.pending_scene==frozen_scene);enabled=1;
  wait(frames==6);enabled=0;wait(consumed);repeat(50)@(negedge clk);
  if(cadence!=5)$fatal(1,"cadence coverage");
  if(MAP_TEST)$display("PASS: six native640x480 indoor-map frames match six independent arrow-phase references; phase/scene immutable during each raster; real100M V12 MAC, RGB444 source/sink, complete-frame 60Hz display commit; five consecutive33.333ms intervals (simulation only), no partial image or source overlap");else $display("PASS: six native640x480 particle frames independently match six separate motion phases; real100M V12 MAC, RGB444 source/sink, complete-frame 60Hz display commit; five consecutive 33.333ms frame intervals (simulation only), no partial image or source overlap");$finish;
 end
 initial begin #1500000000;$fatal(1,"timeout renderer=%0d sender=%0d decoder=%0d words=%0d raw=%0d frames=%0d",renderer.state,sender.phase,receiver.decoder.state,na,raw_index,frames);end
endmodule
