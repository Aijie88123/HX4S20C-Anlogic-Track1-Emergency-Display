`timescale 1ns/1ps
module tb_playback_osd;
 reg clk=0,rst=1,playing=1;always #5 clk=~clk;
 reg [11:0] xp=0,yp=0,x=0,y=0;wire [23:0] rgb;wire [7:0] alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.ENABLE_PERIOD_OSD(1),.ENABLE_PLAYBACK_OSD(1)) dut(
  .clk(clk),.rst(rst),.emergency(1'b0),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b1),
  .x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd1),.playback_running(playing),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'h4),.res_str(" 640X 480"),.text_rgb(rgb),.text_alpha(alpha));
 function [7:0] glyph(input [7:0] ch,input integer row);
  begin case(ch)
   "T":case(row)0:glyph='h7e;default:glyph=row<7?'h18:0;endcase
   "0":case(row)0,6:glyph='h3c;1:glyph='h42;2:glyph='h46;3:glyph='h4a;4:glyph='h52;5:glyph='h62;default:glyph=0;endcase
   "5":case(row)0:glyph='h7e;1:glyph='h40;2:glyph='h40;3:glyph='h7c;4:glyph='h02;5:glyph='h42;6:glyph='h3c;default:glyph=0;endcase
   "P":case(row)0,3:glyph='h7c;1,2:glyph='h42;4,5,6:glyph='h40;default:glyph=0;endcase
   "L":glyph=row==6?'h7e:row<6?'h40:0;
   "A":case(row)0:glyph='h18;1:glyph='h24;3:glyph='h7e;2,4,5,6:glyph='h42;default:glyph=0;endcase
   "Y":case(row)0,1:glyph='h42;2:glyph='h24;3,4,5,6:glyph='h18;default:glyph=0;endcase
   "U":glyph=row==6?'h3c:row<6?'h42:0;
   "S":case(row)0:glyph='h3e;1,2:glyph='h40;3:glyph='h3c;4:glyph='h02;5:glyph='h42;6:glyph='h3c;default:glyph=0;endcase
   "E":case(row)0,6:glyph='h7e;3:glyph='h7c;1,2,4,5:glyph='h40;default:glyph=0;endcase
   default:glyph=0;
  endcase end
 endfunction
 integer mode,ci,ri,co,checks=0;reg [79:0] label;reg [7:0] gl;reg expected;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(mode=0;mode<2;mode=mode+1)begin
   playing=mode==0;label=playing?"T05S PLAY ":"T05S PAUSE";
   for(ci=0;ci<10;ci=ci+1)for(ri=0;ri<8;ri=ri+1)for(co=0;co<8;co=co+1)begin
    @(negedge clk);xp=976+ci*16+co*2;yp=48+ri*2;
    @(posedge clk);#1;x=xp;y=yp;#1;
    gl=glyph(label[(9-ci)*8 +:8],ri);expected=gl[7-co];
    if((alpha==255 && rgb==24'hffffff)!==expected)$fatal(1,"OSD mismatch mode=%d char=%d row=%d col=%d",mode,ci,ri,co);
    checks=checks+1;
   end
  end
  $display("PASS: independent PLAY/PAUSE and period glyph pixels, same existing font port and +1 pixel stage, %d pixels",checks);$finish;
 end
endmodule
