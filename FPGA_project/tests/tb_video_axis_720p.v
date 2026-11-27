module tb_video_axis_720p;
 reg clk=0,rst=1,vs=0,de=0;reg [23:0] rgb=0;always #5 clk=~clk;
 wire u,v,l;wire [23:0] data;
 video_rgb_to_axis_720p dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .O_video_user(u),.O_video_valid(v),.O_video_last(l),.O_video_data(data));
 integer frames=0,ends=0,pixels=0,users=0,x,y,f,frame_ends,frame_users;
 task cycle;input d;input [23:0] colour;input expected_last,expected_user;
 begin
  @(negedge clk);de=d;rgb=colour;
  @(posedge clk);#1;
  if(v!==d||l!==expected_last||u!==expected_user||data!==colour)
   $fatal(1,"AXIS contract frame=%0d row=%0d col=%0d valid=%b last=%b user=%b data=%h",f,y,x,v,l,u,data);
  if(v)pixels=pixels+1;if(v&&l)begin ends=ends+1;frame_ends=frame_ends+1;end
  if(v&&u)begin users=users+1;frame_users=frame_users+1;end
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  for(f=0;f<3;f=f+1)begin
   @(negedge clk);vs=1;repeat(5)@(negedge clk);vs=0;
   cycle(0,24'd0,0,0);frame_ends=0;frame_users=0;
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)cycle(1,{f[1:0],y[10:0],x[10:0]},x==1279,y==0&&x==0);
    cycle(0,24'd0,0,0);repeat(4+(y%7))cycle(0,24'd0,0,0);
   end
   if(frame_ends!=720||frame_users!=1)$fatal(1,"Frame markers count ends=%0d users=%0d",frame_ends,frame_users);
   frames=frames+1;
   // A second output reset after frame one must not retain the column phase.
   if(f==0)begin @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;end
  end
  if(pixels!=2764800||ends!=2160||users!=3)$fatal(1,"Coverage");
  $display("PASS: %0d full 1280x720 frames, %0d RGB/VALID checks, exactly %0d end-of-line TLAST and %0d SOF; variable blanking and output reset recovery",frames,pixels,ends,users);$finish;
 end
 initial begin #100000000;$fatal(1,"AXIS timeout");end
endmodule
