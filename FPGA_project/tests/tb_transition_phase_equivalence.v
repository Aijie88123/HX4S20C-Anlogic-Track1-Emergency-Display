`timescale 1ns/1ps
module tb_transition_phase_equivalence;
 reg [11:0] x=0,y=0;reg [2:0] fx=0;
 wire [7:0] p0,p63,p128,p255;
 transition_fx #(.SPREAD(0)) d0(.x(x),.y(y),.fx_sel(fx),.phase(p0));
 transition_fx #(.SPREAD(63)) d63(.x(x),.y(y),.fx_sel(fx),.phase(p63));
 transition_fx #(.SPREAD(128)) d128(.x(x),.y(y),.fx_sel(fx),.phase(p128));
 transition_fx #(.SPREAD(255)) d255(.x(x),.y(y),.fx_sel(fx),.phase(p255));
 integer xx,yy,mode,i,checks=0,raw,dx,dy;reg [31:0] random_word=32'h5830a761;
 function [7:0] accepted_clamp(input integer value,input integer spread);
  accepted_clamp=value>spread?spread:value;
 endfunction
 task check;begin
  #1;
  dx=x>640?x-640:640-x;dy=y>360?y-360:360-y;
  case(fx)
   0,1,2,4,5,6,7:raw=0;
   3:raw=(x[6]^y[6])?128:0;
  endcase
  if(p0!==accepted_clamp(raw,0)||p63!==accepted_clamp(raw,63)||
     p128!==accepted_clamp(raw,128)||p255!==accepted_clamp(raw,255))
   $fatal(1,"Transition phase changed x=%0d y=%0d mode=%0d raw=%0d",x,y,fx,raw);
  checks=checks+1;
 end endtask
 initial begin
  // Exhaust the retained checkerboard phase over the full raster.
  fx=3;
  for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<1280;xx=xx+1)begin x=xx;y=yy;check;end
  // Other effects and the complete 12-bit input range, including wrap cases.
  for(mode=0;mode<8;mode=mode+1)begin
   fx=mode;
   for(i=0;i<8192;i=i+1)begin
    random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
    x=random_word[11:0];y=random_word[23:12];check;
   end
  end
  $display("PASS: %0d independent phase vectors at four saturation limits (0/63/128/255), full 1280x720 retained-mode raster, all eight switch codes and 12-bit coordinate wrap cases; exact accepted >-clamp formula",checks);
  $finish;
 end
endmodule
