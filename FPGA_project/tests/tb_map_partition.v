`timescale 1ns/1ps
module tb_map_partition;
 reg clk=0,rst=1,online=1;always #20 clk=~clk;
 reg [2:0] actual=1;reg [1:0] zoom=0,barriers=0;
 wire cv,cr;wire [223:0] control;wire txbusy,published;wire [3:0] nibble;
 wire [223:0] received;wire [20:0] message;wire [7:0] extension;
 reg inject=0,drop=0;reg [223:0] injected=0;
 wire live,sv;wire [223:0] scene;
 reg [5:0] gap=0;reg [31:0] clock_count=0;integer packets=0,scenes=0;
 assign cr=!txbusy&&gap==0;
 b_map_control_sender #(.UPDATE_CYCLES(2500)) controls(.clk(clk),.rst(rst),.online(online),.actual_state(actual),
  .switches(zoom),.barrier_mode(barriers),.stream_ready(cr),.stream_valid(cv),.stream_data(control));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) tx(
  .clk(clk),.rst(rst),.start(cv&&cr),.message(21'd0),.extension(8'd0),.stream_data(control),.busy(txbusy),.nibble(nibble));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) rx(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(txbusy),.error(1'b0),.packet_valid(published),.message(message),.extension(extension),.stream_data(received));
 a_map_scene_compute #(.CLK_HZ(25000000),.FRAME_CYCLES(1000),.TIMEOUT_CYCLES(15000),.DEBOUNCE_MS(0)) compute(
  .clk(clk),.rst(rst),.online(online),.actual_state(actual),.packet_valid(inject || (published&&!drop)),.packet(inject?injected:received),
  .controls_live(live),.scene_valid(sv),.scene(scene));
 always @(posedge clk)begin
  clock_count<=clock_count+1;
  if(txbusy)gap<=24;else if(gap!=0)gap<=gap-1'b1;
  if(published)packets<=packets+1;
  if(sv)scenes<=scenes+1;
 end
 task send_injected;input [223:0] p;begin @(negedge clk);inject=1;injected=p;@(negedge clk);inject=0;end endtask
 integer e,m,out;reg [223:0] old_control;reg [15:0] saved_seq;reg [15:0] blocked;
 initial begin
  out=$fopen("map_partition_scenes.txt","w");
  repeat(12)@(negedge clk);rst=0;
  wait(live);wait(sv);old_control=received;
  // Check B snapshots stay fixed while the stream is backpressured.
  force controls.stream_ready=0;wait(cv);old_control=control;
  zoom=2;barriers=2;repeat(300)@(negedge clk);
  if(control!==old_control)$fatal(1,"FAIL: B controls changed under backpressure");
  release controls.stream_ready;
  wait(compute.zoom==2 && compute.barriers==2);
  // Every event/barrier combination must complete locally and preserve valid
  // routes: no blocked edge, proper exit reachability and no-path when sealed.
  for(e=0;e<4;e=e+1)for(m=0;m<4;m=m+1)begin
   @(negedge clk);actual={e[1:0],1'b1};barriers=m;zoom=(e+m)%3;
   wait(live && compute.barriers==m && compute.zoom==(e+m)%3);
   wait(sv && scene[11:10]==e && compute.u_local_route.barrier_q==m && !compute.u_local_route.solver_busy);
   blocked=compute.u_local_route.closed;
   if((scene[107:92]&blocked)!=0 || scene[9]!=(m==3) || ((m==3)?scene[107:92]!=0:scene[107:92]==0))
    $fatal(1,"FAIL: route search event=%0d barrier=%0d scene=%h",e,m,scene);
   if(scene[223:188]!=0 || scene[7:0]!=3 || scene[13:12]!=(e+m)%3)$fatal(1,"FAIL: local scene fields");
   $fdisplay(out,"%0d %0d %056h %013h",e,m,scene,compute.u_local_route.nodes);
   repeat(3)@(negedge clk);
  end
  // Old and malformed reports cannot roll back applied controls.
  wait(published);@(negedge clk);drop=1;saved_seq=compute.control_sequence;old_control=received;
  send_injected(old_control ^ (224'd1<<188));
  send_injected(old_control ^ (224'd1<<80));
  old_control[33:18]=saved_seq-1;old_control[17:16]=0;send_injected(old_control);
  if(compute.control_sequence!=saved_seq || compute.barriers!=3)$fatal(1,"FAIL: malformed/stale controls accepted");
  // Silence freezes scene production; physical disconnect resets the epoch.
  wait(!live);repeat(10)@(negedge clk);if(sv)$fatal(1,"FAIL: stale scene after control timeout");
  online=0;repeat(20)@(negedge clk);online=1;drop=0;actual=1;barriers=0;zoom=1;
  wait(live && compute.zoom==1);wait(sv);
  if(compute.control_sequence>10)$fatal(1,"FAIL: reconnect sequence epoch not reset");
  if(packets<20 || scenes<16)$fatal(1,"FAIL: insufficient route/control exercise");
  $fclose(out);$display("PASS: A-local Dijkstra/walking with B control snapshots through actual v10 MAC/FCS; 16 event/barrier combinations, zoom, immutable backpressure, malformed/stale rejection, control timeout and reconnect epoch");$finish;
 end
 initial begin #30000000;$fatal(1,"FAIL: partition timeout packets=%0d scenes=%0d state=%h live=%b",packets,scenes,scene,live);end
endmodule
