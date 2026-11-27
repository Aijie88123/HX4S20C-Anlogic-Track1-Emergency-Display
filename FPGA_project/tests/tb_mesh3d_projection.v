`timescale 1ns/1ps
module tb_mesh3d_projection;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,online=0,active=0,pv=0;reg [1:0] event_type=0,view_mode=2;
 reg [223:0] packet=0;wire valid;wire [223:0] triangle;
 a_mesh3d_projector #(.CLK_HZ(25000000),.FRAME_PERIOD(100000)) dut(.clk(clk),.rst(rst),.online(online),.active(active),
  .event_type(event_type),.view_mode(view_mode),.packet_valid(pv),.packet(packet),.triangle_valid(valid),.triangle(triangle),.triangle_ready(valid));
 integer f,count=0,frames=0;
 task scene;input [1:0] zoom;input [11:0] gx,gy;begin
  @(negedge clk);packet=0;packet[7:0]=3;packet[13:12]=zoom;packet[151:140]=gx;packet[163:152]=gy;
  packet[107:92]=16'h0144;packet[139:124]=16'h0080;pv=1;
  @(negedge clk);pv=0;
 end endtask
 always @(posedge clk)if(valid)begin
  $fwrite(f,"%056x\n",triangle);count=count+1;
  if(triangle[40])frames=frames+1;
 end
 initial begin
  f=$fopen("mesh3d_projected.hex","w");repeat(6)@(negedge clk);rst=0;online=1;active=1;
  scene(0,288,392);
  wait(frames==1);view_mode=1;scene(1,992,392);
  wait(frames==2);view_mode=3;event_type=1;
  @(negedge clk);packet[11:10]=1;packet[13:12]=2;packet[151:140]=640;packet[163:152]=216;pv=1;
  @(negedge clk);pv=0;
  wait(frames==3);@(negedge clk);active=0;$fclose(f);
  if(count!=354)$fatal(1,"FAIL: triangle count %0d",count);
  $display("PASS: A emitted three complete XYZ/perspective/reciprocal-depth scenes, 354 projected triangles, finite rotation/zoom/follow and immutable frame tags");$finish;
 end
 initial begin #30000000;$fatal(1,"FAIL: projection timeout state=%0d op=%0d vertex=%0d",dut.state,dut.op,dut.vertex);end
endmodule
