`timescale 1ns/1ps
module tb_map_worker_client;
 reg clk=0,vclk=0;always #20 clk=~clk;always #6.667 vclk=~vclk;
 reg rst=1,online=1,ready=1,frame=0;reg [2:0] state=1;reg [1:0] switches=0,barrier=0;
 wire valid;wire [223:0] data;reg inject=0;reg [223:0] forged=0;
 wire live;wire [187:0] scene;
 distributed_map_worker #(.CLK_HZ(1000),.FRAME_CYCLES(500),.DEBOUNCE_MS(2)) worker(
  .clk(clk),.rst(rst),.online(online),.actual_state(state),.switches(switches),.barrier_mode(barrier),
  .stream_ready(ready),.stream_valid(valid),.stream_data(data));
 distributed_map_client #(.TIMEOUT_FRAMES(4)) client(.net_clk(clk),.video_clk(vclk),.rst(rst),
  .online(online),.packet_valid(inject||(valid&&ready)),.packet(inject?forged:data),
  .frame_tick(frame),.event_type(state[2:1]),.live(live),.scene(scene));
 reg [187:0] held_scene;integer sent=0;reg [223:0] last_packet;
 always @(posedge clk)if(valid && ready)begin
  if(data[7:0]!==3 || data[223:188]!==0 || data[15:14]!==0)$fatal(1,"Malformed map packet");
  if((data[107:92]&data[139:124])!=0)$fatal(1,"Worker packet draws a closed route");
  last_packet=data;sent=sent+1;
 end
 task commit;begin @(negedge vclk);frame=1;@(negedge vclk);frame=0;#100;end endtask
 task send_bad(input [223:0] p);begin @(negedge clk);forged=p;inject=1;@(negedge clk);inject=0;#1000;commit();end endtask
 initial begin
  #100;rst=0;#40000;
  if(live)$fatal(1,"Map enabled before vertical blank commit");commit();
  if(!live || scene[91:80]!=3072 || scene[13:12]!=0)$fatal(1,"Default map projection missing");
  held_scene=scene;#25000;
  if(scene!==held_scene)$fatal(1,"Received scene changed mid-frame");
  commit();
  if(scene[55:32]==held_scene[55:32])$fatal(1,"Camera does not follow the moving guide");
  for(integer z=1;z<=2;z=z+1)begin
   switches=z;#45000;commit();
   if(!live || scene[13:12]!=z || scene[91:80]!=(z==1?2458:2048))$fatal(1,"Manual zoom missing");
  end
  switches=3;#45000;commit();if(scene[13:12]!=0)$fatal(1,"All switches high must default to 1x");
  held_scene=scene;barrier=1;#45000;commit();
  if(scene[107:92]==held_scene[107:92])$fatal(1,"Same-start road closure did not replan");
  if((scene[107:92]&scene[139:124])!=0)$fatal(1,"Replanned route uses a closed edge");
  barrier=3;#45000;commit();if(!live || !scene[9] || scene[107:92]!=0)$fatal(1,"No-path condition unsafe");
  ready=0;#1000;held_scene=scene;
  send_bad({36'd0,scene[187:32],16'h0000,scene[15:9],1'b0,8'd3}); // obsolete sequence
  if(scene!==held_scene)$fatal(1,"Obsolete map packet accepted");
  send_bad(last_packet|224'h4000); // reserved flags
  if(scene!==held_scene)$fatal(1,"Reserved flag accepted");
  send_bad(last_packet|(224'd1<<200));if(scene!==held_scene)$fatal(1,"Nonzero map padding accepted");
  online=0;#1000;commit();if(live)$fatal(1,"Offline map not cleared at frame boundary");
  online=1;ready=1;barrier=0;#45000;commit();if(!live || scene[9])$fatal(1,"Map did not recover after reconnect");
  ready=0;#1000;for(integer i=0;i<5;i=i+1)commit();if(live)$fatal(1,"Stale map did not time out");
  $display("PASS: B manual zoom, real same-start replanning, no-path, smooth camera following, packet validation, atomic vblank, obsolete rejection, stale timeout and reconnect, sent=%0d",sent);$finish;
 end
 initial begin #2000000;$fatal(1,"Map worker/client timeout");end
endmodule
