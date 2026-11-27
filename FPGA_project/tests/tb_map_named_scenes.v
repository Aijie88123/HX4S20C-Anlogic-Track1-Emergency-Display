`timescale 1ns/1ps
module tb_map_named_scenes;
 reg clk=0,rst=1,online=1,ready=1;always #20 clk=~clk;
 reg [1:0] barrier=0,ref_barrier=0,zoom=0;reg [2:0] actual=1,ref_actual=1;
 reg [4:0] resolved_controls[0:11];
 wire nv,ov;wire [223:0] nd,od;
 a_distributed_map_worker #(.CLK_HZ(1000),.FRAME_CYCLES(1000),.DEBOUNCE_MS(2)) current(
  .clk(clk),.rst(rst),.online(online),.actual_state(actual),.switches(zoom),.barrier_mode(barrier),
  .stream_ready(ready),.stream_valid(nv),.stream_data(nd));
 reference_distributed_map_worker #(.CLK_HZ(1000),.FRAME_CYCLES(1000),.DEBOUNCE_MS(2)) original(
  .clk(clk),.rst(rst),.online(online),.actual_state(ref_actual),.switches(zoom),.barrier_mode(ref_barrier),
  .stream_ready(ready),.stream_valid(ov),.stream_data(od));
 integer cycles=0,packets=0,cases=0,b,e,z;
 always @(posedge clk)begin
  cycles=cycles+1;
  #1;if(!rst)begin
   if(nv!==ov || nd!==od)$fatal(1,"Resolved scene parameters changed expected V12 outputs cycle=%0d",cycles);
   if(nv&&ready)begin
    if((nd[107:92]&nd[139:124])!=0)$fatal(1,"route crosses closure");
    packets=packets+1;
   end
  end
 end
 initial begin
  $readmemh("scene_controls.hex",resolved_controls);
  repeat(5)@(negedge clk);rst=0;
  for(e=0;e<4;e=e+1)for(b=0;b<4;b=b+1)for(z=0;z<3;z=z+1)begin
   @(negedge clk);ref_actual=(e<<1)|1;ref_barrier=b;zoom=z;
   if(e<3)begin actual=resolved_controls[e*4+b][2:0];barrier=resolved_controls[e*4+b][4:3];end
   else begin actual=7;barrier=b;end
   repeat(2400)@(negedge clk);cases=cases+1;
   if(current.event_q!==e || current.barrier_q!==b)$fatal(1,"Resolved controls not applied");
   if(current.exit_node!==original.exit_node || current.no_path!==original.no_path)$fatal(1,"automatic exit/no-path changed");
  end
  @(negedge clk);ready=0;repeat(2500)@(negedge clk);ready=1;
  online=0;repeat(100)@(negedge clk);online=1;repeat(2500)@(negedge clk);
  rst=1;repeat(8)@(negedge clk);rst=0;repeat(2500)@(negedge clk);
  if(packets<90)$fatal(1,"insufficient packet coverage");
  $display("PASS: real Python-resolved A/B/C parameters drive unchanged production A worker; %0d event/barrier/zoom cases including drill, %0d cycles/%0d packets match independent canonical controls; automatic exits/closures/no-path, stall/offline/reset retained",cases,cycles,packets);$finish;
 end
 initial begin #100000000;$fatal(1,"named scene timeout");end
endmodule
