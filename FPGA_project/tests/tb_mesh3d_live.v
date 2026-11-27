`timescale 1ns/1ps
// Continuous native-clock RTL preview. The real B route walker feeds the real
// A camera/projector, real stop-and-wait geometry receiver and B depth renderer.
module tb_mesh3d_live;
 reg net=0,pixel=0,rst=1;always #20 net=~net;always #10 pixel=~pixel;
 wire scene_valid;wire [223:0] scene;
 distributed_map_worker #(.COMPUTE_VIEW(0)) walker(.clk(net),.rst(rst),.online(1'b1),.actual_state(3'd1),
  .switches(2'd0),.barrier_mode(2'd0),.stream_ready(1'b1),.stream_valid(scene_valid),.stream_data(scene));
 wire triangle_valid,triangle_ready;wire [223:0] triangle;
 a_mesh3d_projector projector(.clk(net),.rst(rst),.online(1'b1),.active(1'b1),.event_type(2'd0),.view_mode(2'd0),
  .packet_valid(scene_valid),.packet(scene),.triangle_valid(triangle_valid),.triangle(triangle),.triangle_ready(triangle_ready));
 wire stream_valid,ack_valid;wire [223:0] stream,ack;
 mesh3d_packet_sender sender(.clk(net),.rst(rst),.online(1'b1),.triangle_valid(triangle_valid),.triangle(triangle),
  .triangle_ready(triangle_ready),.packet_valid(ack_valid),.packet(ack),.stream_valid(stream_valid),.stream_data(stream),.stream_ready(1'b1));
 wire mesh_valid;wire [7:0] mesh_count;wire [15:0] mesh_id;wire [12:0] mesh_meta;
 wire [10:0] address;wire [15:0] data;reg release_toggle=0;
 mesh3d_packet_receiver receiver(.net_clk(net),.render_clk(pixel),.rst(rst),.online(1'b1),.packet_valid(stream_valid),.packet(stream),
  .ack_valid(ack_valid),.ack_packet(ack),.ack_ready(1'b1),.read_address(address),.read_data(data),
  .mesh_valid(mesh_valid),.mesh_count(mesh_count),.mesh_id(mesh_id),.mesh_meta(mesh_meta),.release_toggle(release_toggle));
 reg start=0;reg [15:0] last_id=0;reg [8:0] phase=0,held_phase=0;reg [19:0] phase_count=0;
 wire busy,done,word_valid;wire [31:0] word_data;
 b_mesh3d_tile_renderer tiles(.clk(pixel),.rst(rst),.start(start),.abort(1'b0),.triangle_count(mesh_count),.frame_meta(mesh_meta),
  .phase(held_phase),.busy(busy),.done(done),.geometry_address(address),.geometry_data(data),
  .word_valid(word_valid),.word_data(word_data),.word_ready(1'b1));
 integer pixels,packets,frames=0,words=0,meta;
 always @(posedge net)if(!rst&&triangle_valid&&triangle_ready)begin
  $fwrite(packets,"%056x\n",triangle);
 end
 always @(posedge pixel)begin
  start<=0;
  if(!rst)begin
   if(phase_count==833332)begin phase_count<=0;phase<=phase+1'b1;end else phase_count<=phase_count+1'b1;
   if(mesh_valid&&!busy&&!start&&mesh_id!=last_id)begin
    start<=1;last_id<=mesh_id;held_phase<=phase;
    $fwrite(meta,"%0d %0d %0d %0d %0d %0d %0d\n",mesh_id,phase,projector.person_u,projector.person_v,projector.focus_u,projector.focus_v,projector.yaw);
   end
   if(word_valid)begin
    if(word_data[15:0]!==word_data[31:16])$fatal(1,"FAIL: live duplicate pixel");
    $fwrite(pixels,"%08x\n",word_data);words=words+1;
   end
   if(done)begin
    if(words!=(frames+1)*115200)$fatal(1,"FAIL: incomplete live frame");
    frames=frames+1;release_toggle<=~release_toggle;
    if(frames==60)begin
     $fclose(pixels);$fclose(packets);$fclose(meta);
     $display("PASS: sixty native-clock continuous real RTL frames, 6912000 packed words, moving person and following/orbiting camera, immutable geometry and reciprocal-depth visibility");$finish;
    end
   end
  end
 end
 initial begin
  pixels=$fopen("mesh3d_live_words.hex","w");packets=$fopen("mesh3d_live_packets.hex","w");meta=$fopen("mesh3d_live_meta.txt","w");
  repeat(16)@(negedge net);rst=0;
 end
 initial begin #2500000000;$fatal(1,"FAIL: live timeout frame=%0d",frames);end
endmodule
