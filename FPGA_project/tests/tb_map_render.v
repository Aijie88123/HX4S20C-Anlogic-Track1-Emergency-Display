`timescale 1ns/1ps
module tb_map_render;
 reg clk=0,rst=1;always #6.667 clk=~clk;
 reg [11:0] cx=1280,cy=0;reg capture_on=0,frame_tick=0;reg [4:0] capture_pipe=0;
 reg [187:0] scene=0;wire [23:0] rgb;wire [7:0] alpha;
 integer file_handle,pixels=0,case_index=-1;integer ix,iy;reg [11:0] step;
 integer signed ox,oy,expected_x,expected_y;
 emergency_map_top #(.REMOTE_MAP(1)) dut(.clk(clk),.rst(rst),.active(1'b1),.state(3'd3),
  .event_type(2'd0),.remote_live(1'b1),.remote_scene(scene),.blink_on(1'b1),
  .frame_tick(frame_tick),.cx(cx),.cy(cy),.map_rgb(rgb),.map_alpha(alpha));
 always @(posedge clk)begin
  if(capture_on)begin
   expected_x=($signed(scene[55:32])+cx*scene[91:80])>>>12;
   expected_y=($signed(scene[79:56])+cy*scene[91:80])>>>12;
   if(dut.scene_x!==expected_x[11:0] || dut.scene_y!==expected_y[11:0])
    $fatal(1,"Zoom projection mismatch case=%0d pixel=%0d/%0d x=%0d/%0d y=%0d/%0d",case_index,cx,cy,dut.scene_x,expected_x,dut.scene_y,expected_y);
  end
  capture_pipe={capture_pipe[3:0],capture_on};#1;
  if(capture_pipe[4])begin
   if(alpha!==255 || (^rgb===1'bx))$fatal(1,"Renderer pixel alpha/valid pipeline changed");
   $fwrite(file_handle,"%06x\n",rgb);pixels=pixels+1;
  end
 end
 task render(input integer z,input integer camera_x,input integer camera_y,input integer guide_x,input integer guide_y,input bit no_path);
  begin
   case_index=case_index+1;step=(z==1)?2458:(z==2)?2048:3072;
   ox=camera_x*4096-640*step;oy=camera_y*4096-360*step;
   scene=0;scene[7:0]=3;scene[13:12]=z;scene[9]=no_path;
   scene[55:32]=ox;scene[79:56]=oy;scene[91:80]=step;
   scene[107:92]=no_path?16'd0:16'h8010;scene[123:108]=16'h8010;scene[139:124]=no_path?16'hf080:16'h0080;
   scene[151:140]=guide_x;scene[163:152]=guide_y;scene[175:164]=384;scene[187:176]=534;
   file_handle=$fopen($sformatf("map_render_%0d.rgb",case_index),"w");pixels=0;
   @(negedge clk);cx=1280;cy=0;frame_tick=1;@(negedge clk);frame_tick=0;
   repeat(8)@(negedge clk);
   for(iy=0;iy<720;iy=iy+1)begin
    for(ix=0;ix<1280;ix=ix+1)begin @(negedge clk);cx=ix;cy=iy;capture_on=1;end
    @(negedge clk);cx=1280;capture_on=0;repeat(5)@(negedge clk);
   end
   repeat(10)@(negedge clk);$fclose(file_handle);
   if(pixels!=921600)$fatal(1,"Full map frame pixel count changed %0d",pixels);
  end
 endtask
 initial begin
  #100;rst=0;
  render(0,640,404,464,480,0);
  render(1,640,404,464,480,0);
  render(2,640,404,464,480,0);
  render(2,520,424,448,488,0);
  render(2,520,424,288,392,1);
  $display("PASS: 5 full 1280x720 RGB frames, 1x/1.25x/1.5x, camera follow, no-path rendering; 4608000 inverse-projection pixels and five-stage output alignment");$finish;
 end
endmodule
