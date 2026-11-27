`timescale 1ns/1ps
module tb_native_vga_chain;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg enabled=0,particle=1,run_animation=1;wire [187:0] scene;wire scene_valid,scene_ready;wire [223:0] computed_scene,controls,controls_rx,scene_rx;wire control_valid,control_ready,controls_valid_rx;wire [3:0] ctl_nib,scene_nib;wire ctl_busy,scene_busy;
 b_map_control_sender #(.UPDATE_CYCLES(1000000)) controls_b(.clk(clk),.rst(rst),.online(1'b1),.actual_state(3'd1),.switches(2'd0),.barrier_mode(2'd0),.stream_ready(!ctl_busy),.stream_valid(control_valid),.stream_data(controls));
 a_map_scene_compute #(.CLK_HZ(50000000),.FRAME_CYCLES(416667)) scene_a(.clk(clk),.rst(rst),.online(1'b1),.actual_state(3'd1),.packet_valid(controls_valid_rx),.packet(controls_rx),.controls_live(),.scene_valid(scene_ready),.scene(computed_scene));
 wire [223:0] scene_wire={12'd0,computed_scene[187:8],16'd0,8'd1,8'd14};
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(11)) control_tx(.clk(clk),.rst(rst),.start(control_valid&&!ctl_busy),.message(21'd0),.extension(8'd0),.stream_data(controls),.busy(ctl_busy),.nibble(ctl_nib));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(11)) control_rx(.clk(clk),.rst(rst),.nibble(ctl_nib),.valid(ctl_busy),.error(1'b0),.packet_valid(controls_valid_rx),.message(),.extension(),.stream_data(controls_rx));
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(11)) scene_tx(.clk(clk),.rst(rst),.start(scene_ready&&!scene_busy),.message(21'd0),.extension(8'd0),.stream_data(scene_wire),.busy(scene_busy),.nibble(scene_nib));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(11)) scene_rx_mac(.clk(clk),.rst(rst),.nibble(scene_nib),.valid(scene_busy),.error(1'b0),.packet_valid(scene_valid),.message(),.extension(),.stream_data(scene_rx));
 assign scene={scene_rx[211:32],8'd3};
 wire wr_req,wr_en,wr_cancel,frame_valid,consumed,frame_animation;wire [31:0] wr_data;wire [1:0] event_type;wire [8:0] motion;
 reg wr_done=0;reg [31:0] bmem[0:115199],amem[0:115199];integer nw=0,na=0,frames=0,ticks=0;
 b_map_frame_renderer_vga renderer(.clk(clk),.rst(rst),.enabled(enabled),.particle_mode(particle),.animation_run(run_animation),.scene_valid(scene_valid),.scene(scene),
  .frame_animation(frame_animation),.motion_phase(motion),.write_req(wr_req),.write_ack(wr_req),.write_full(1'b0),.write_done_toggle(wr_done),
  .write_en(wr_en),.write_data(wr_data),.write_cancel(wr_cancel),.frame_valid(frame_valid),.frame_event(event_type),.frame_consumed(consumed));
 // Deterministic frame phase independently reproduced by the Python model.
 initial force renderer.frame_phase=9'd0;
 reg [31:0] golden[0:115199];initial $readmemh("native_vga_particle.hex",golden);
 wire req,pair_en,pair_empty,raw_en;wire [31:0] pair_data;reg [31:0] raw_data;integer raw_index=0;
 rgb444_pair_reader expand(.clk(clk),.rst(rst),.start(req),.raw_ack(req),.raw_empty(raw_index>=115200),.raw_data(raw_data),.raw_en(raw_en),.pair_en(pair_en),.pair_empty(pair_empty),.pair_data(pair_data));
 wire sv,sr,av,ar;wire [223:0] sp,ap;reg b2a=0,a2b=0;reg [223:0] bp=0,pa=0;
 integer fwd=0,back=0,gap=0,packets=0,dropped=0;reg [223:0] fh,bh;
 assign sr=fwd==0 && gap==0;assign ar=back==0;
 raster_map_window_sender #(.PIXELS(307200),.ANIMATION_PIXELS(307200),.ALLOW_ANIMATION(1),.NATIVE_VGA(1),.DATA_RETRY_CYCLES(2000)) sender(
  .clk(clk),.rst(rst),.online(1'b1),.frame_valid(frame_valid),.frame_event(event_type),.frame_consumed(consumed),.frame_animation(frame_animation),.current_animation(),
  .packet_valid(a2b),.packet(pa),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),.read_req(req),.read_en(pair_en),.read_busy(),.read_ack(req),.read_empty(pair_empty),.read_data(pair_data));
 wire rq,re,cancel,commit,anim;wire [31:0] rd;wire [1:0] cev;reg adone=0;reg commit_ready=0;
 wire full=ticks%79==7 || ticks%79==8 || ticks%79==9;
 raster_map_window_receiver #(.PIXELS(307200),.ANIMATION_PIXELS(307200),.ALLOW_ANIMATION(1),.NATIVE_VGA(1)) receiver(
  .clk(clk),.rst(rst),.online(1'b1),.packet_valid(b2a),.packet(bp),.ack_valid(av),.ack_packet(ap),.ack_ready(ar),
  .write_cancel(cancel),.write_req(rq),.write_ack(rq),.write_full(full),.write_done_toggle(adone),.write_en(re),.write_data(rd),
  .commit_valid(commit),.commit_ready(commit_ready),.commit_event(cev),.commit_animation(anim));
 integer i,j,diversity;integer out;
 always @(posedge clk)begin
  ticks<=ticks+1;b2a<=0;a2b<=0;commit_ready<=0;
  if(wr_req)nw<=0;
  if(wr_en)begin
   if(nw>=115200)$fatal(1,"native B frame overrun");
   if(particle && wr_data!==golden[nw])$fatal(1,"native independent shader/packing mismatch word=%0d got=%h expected=%h",nw,wr_data,golden[nw]);
   bmem[nw]=wr_data;nw<=nw+1;if(nw==115199)wr_done<=~wr_done;
  end
  if(req)raw_index<=0;else if(raw_en)begin raw_data<=bmem[raw_index];raw_index<=raw_index+1;end
  if(sv&&sr)begin fh<=sp;fwd<=32;gap<=336;packets<=packets+1;end
  if(gap!=0)gap<=gap-1;
  if(fwd!=0)begin fwd<=fwd-1;if(fwd==1)begin
   if(!dropped && fh[7:0]==7 && !fh[31] && fh[47:32]==3)begin dropped<=1;end
   else begin b2a<=1;bp<=fh;end
  end end
  if(av&&ar)begin bh<=ap;back<=32;end
  if(back!=0)begin back<=back-1;if(back==1)begin a2b<=1;pa<=bh;end end
  if(rq)na<=0;
  if(re)begin
   if(na>=115200 || rd!==bmem[na])$fatal(1,"B->A exact native RGB444 word mismatch %0d got=%h expected=%h",na,rd,bmem[na]);
   amem[na]=rd;na<=na+1;if(na==115199)adone<=~adone;
  end
  if(commit)begin
   if(na!=115200)$fatal(1,"partial native frame commit %0d",na);
   commit_ready<=1;
   if(!commit_ready)begin
    frames<=frames+1;
    if(frames==0)out=$fopen("native_particle_words.hex","w");else out=$fopen("native_map_words.hex","w");
    for(i=0;i<115200;i=i+1)$fdisplay(out,"%08h",amem[i]);$fclose(out);
    $display("FRAME: native640x480 animation=%0d words=%0d packets=%0d ticks=%0d",anim,na,packets,ticks);
   end
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst=0;enabled=1;
  wait(frames==1);enabled=0;wait(consumed);@(negedge clk);particle=0;enabled=1;
  wait(frames==2);enabled=0;wait(consumed);repeat(50)@(negedge clk);
  diversity=0;for(j=1;j<115200;j=j+1)if(amem[j]!=amem[j-1])diversity=diversity+1;
  if(diversity<1000)$fatal(1,"blank 2.5D scene %0d",diversity);
  $display("PASS: native640x480 particle independently matched all307200 pixels; native2.5D full frame using actual bidirectional V11 MAC, B control packets and A Dijkstra/camera scene; RGB444 SDRAM transport exact230400 words, injected packet loss/retry, FIFO backpressure and complete-frame ACK");$finish;
 end
 initial begin #1500000000;$fatal(1,"timeout renderer=%0d sender=%0d decoder=%0d words=%0d raw=%0d frames=%0d",renderer.state,sender.phase,receiver.decoder.state,na,raw_index,frames);end
endmodule
