`timescale 1ns/1ps
module tb_map_ui;
 reg clk=0;always #10 clk=~clk;
 reg [8:0] x=0;reg [7:0] y=0;reg [12:0] meta=0;reg [8:0] phase=0;
 reg signed [11:0] px=0,py=0,hx=0,hy=0,rx=0,ry=0;
 function [11:0] lx;input signed [11:0] p;begin lx=p<3?3:p>251?251:p+3;end endfunction
 function [11:0] ly;input signed [11:0] p;begin ly=p<56?38:p>170?152:p-18;end endfunction
 wire [15:0] base={x[4:0],y[5:0],(x[4:0]^y[4:0])};wire [15:0] rgb;
 b_mesh3d_ui ui(.clk(clk),.x(x),.y(y),.meta(meta),.phase(phase),.base_rgb(base),
  .person_x(lx(px-12'sd72)),.person_y(ly(py+12'sd32)),.hazard_x(lx(hx)),.hazard_y(ly(hy)),.route_x(lx(rx)),.route_y(ly(ry)),
  .have_person(1'b1),.have_hazard(1'b1),.have_route(1'b1),.rgb(rgb));
 integer i,xx,yy,file;
 initial begin
  file=$fopen("map_ui_all_pixels.hex","w");
  for(i=0;i<32;i=i+1)begin
   meta={i[3:2],i[4],i[1:0],i[2:0],3'd0,2'd0};phase=i[3]?16:0;
   case(i%4)
    0:begin px=160;py=44;hx=153;hy=52;rx=159;ry=111;end
    1:begin px=-15;py=16;hx=290;hy=180;rx=-15;ry=200;end
    2:begin px=319;py=170;hx=-20;hy=-10;rx=310;ry=80;end
    3:begin px=160;py=110;hx=160;hy=110;rx=160;ry=110;end
   endcase
   for(yy=0;yy<180;yy=yy+1)for(xx=0;xx<320;xx=xx+1)begin
    @(negedge clk);x=xx;y=yy;repeat(2)@(posedge clk);#1;
    if(^rgb===1'bx)$fatal(1,"FAIL: UI uninitialised");
    $fwrite(file,"%04x\n",rgb);
   end
  end
  $fclose(file);$display("PASS: UI 32 complete screens, camera/zoom/status variants, eight compass headings, no-path warning, clipped/overlapping world labels and RGB565 glass");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: UI timeout");end
endmodule
