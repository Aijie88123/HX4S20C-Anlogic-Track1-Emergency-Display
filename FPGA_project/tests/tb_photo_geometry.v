`timescale 1ns/1ps
module tb_photo_geometry;
 reg clk=0,rst=1;always #6.666 clk=~clk;
 reg flip=0,back=0;reg [11:0] width=640,left=320;reg [9:0] height=360,top=180;
 reg [16:0] inv_x=4096,inv_y=5461;
 wire req,en,ack,word_read,pixel_empty;wire [31:0] pixel_data;reg [31:0] word_data=0;
 wire [20:0] base;reg req_d=0,stream=0;reg [20:0] held_base=0;integer word_index=0,cycles=0;
 wire word_empty=!stream || word_index>=512 || cycles%127==13;
 assign ack=req_d;
 wire hs,vs,de,ready,rawvs,rawde,frame_start;wire [11:0] rawx,rawy;wire [23:0] rgb;
 rgb888_frame_unpack #(.FAST_WORD_READ(1)) unpack(.clk(clk),.rst(rst),.restart(req),.fast_mode(1'b1),
  .word_empty(word_empty),.word_data(word_data),.word_read(word_read),.pixel_read(en),.pixel_empty(pixel_empty),.pixel_data(pixel_data));
 video_scanout_720p #(.ENABLE_GEOMETRY(1)) dut(.clk(clk),.rst(rst),.read_req(req),.read_req_ack(ack),
  .read_en(en),.read_data(pixel_data),.read_empty(pixel_empty),.hs(hs),.vs(vs),.de(de),.rgb(rgb),.pixel_ready(ready),
  .raw_hs(),.raw_vs(rawvs),.raw_de(rawde),.raw_x(rawx),.raw_y(rawy),.raw_frame_start(frame_start),
  .geometry_active(1'b1),.geometry_flip(flip),.geometry_width(width),.geometry_left(left),
  .geometry_height(height),.geometry_top(top),.geometry_inv_x(inv_x),.geometry_inv_y(inv_y),
  .geometry_old_base(21'd460800),.geometry_new_base(21'd691200),.geometry_back_half(back),.geometry_read_base(base));
 function [23:0] pixel;input integer slot,sx,sy;
  begin pixel={8'h30+slot[7:0]*8'd17,sx[7:0]^slot[7:0],sy[7:0]^{6'd0,sx[9:8]}};end
 endfunction
 function [31:0] packed_word;input integer addr;integer slot,local_word,j,b,pidx;reg [23:0] color;
  begin
   slot=addr/230400;local_word=addr%230400;packed_word=0;
   for(j=0;j<4;j=j+1)begin b=local_word*4+j;pidx=b/3;color=pixel(slot,pidx%640,pidx/640);packed_word[j*8+:8]=color[(b%3)*8+:8];end
  end
 endfunction
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(rst)begin req_d<=0;stream<=0;word_index<=0;end
  else begin
   req_d<=req;
   if(req)begin held_base<=base;word_index<=0;stream<=0;end
   else if(req_d)stream<=1;
   if(word_read && !word_empty)begin word_data<=packed_word(held_base+word_index);word_index<=word_index+1;end
  end
 end
 integer x=0,y=0,checks=0,total=0,cases=0,old_pixels=0,new_pixels=0,black_pixels=0;
 integer sx,sy,slot;reg [23:0] expected;reg previous_de=0,previous_vs=0;reg checking=0;
 always @(posedge clk)begin
  #1;
  if(rst)begin x=0;y=0;previous_de=0;previous_vs=0;end
  else begin
   if(vs && !previous_vs)begin x=0;y=0;end
   if(de)begin
    if(!previous_de)x=0;
    if(checking)begin
     sx=x/2;sy=(2*y)/3;slot=2;
     if(flip)begin
      if(width==0 || x<left || x>=left+width)begin expected=0;black_pixels=black_pixels+1;end
      else begin sx=((x-left)*inv_x)>>12;if(sx>639)sx=639;slot=back?3:2;expected=pixel(slot,sx,sy);end
     end else begin
      if(width!=0 && x>=left && x<left+width && y>=top && y<top+height)begin
       sx=((x-left)*inv_x)>>12;sy=((y-top)*inv_y)>>12;
       if(sx>639)sx=639;if(sy>479)sy=479;slot=3;new_pixels=new_pixels+1;
      end else old_pixels=old_pixels+1;
      expected=pixel(slot,sx,sy);
     end
     if(!ready || rgb!==expected)$fatal(1,"geometry pixel mismatch case=%0d flip=%0d back=%0d width=%0d x=%0d y=%0d ready=%b got=%h expected=%h state=%0d count=%0d",cases,flip,back,width,x,y,ready,rgb,expected,dut.geometry_coordinate.u_geometry_reader.state,dut.geometry_coordinate.u_geometry_reader.received);
     checks=checks+1;total=total+1;
    end
    x=x+1;
   end
   if(!de && previous_de)begin
    if(x!=1280)$fatal(1,"geometry raster line length %0d",x);
    y=y+1;
   end
   previous_de=de;previous_vs=vs;
  end
 end
 task scenario;input is_flip;input backface;input integer scale;
 begin
  checking=0;rst=1;repeat(10)@(negedge clk);
  flip=is_flip;back=backface;width=40*scale;height=720*scale/32;left=(1280-width)/2;top=(720-height)/2;
  inv_x=width?640*4096/width:0;inv_y=height?480*4096/height:0;
  checks=0;cases=cases+1;rst=0;checking=1;
  wait(checks==921600);@(negedge clk);checking=0;
  $display("PASS: geometry case %0d flip=%0d back=%0d scale=%0d full720p exact=%0d",cases,flip,back,scale,checks);
 end endtask
 initial begin
  scenario(1,0,32);scenario(1,0,16);scenario(1,0,2);scenario(1,1,0);scenario(1,1,16);scenario(1,1,32);
  scenario(0,0,0);scenario(0,0,1);scenario(0,0,16);scenario(0,0,31);scenario(0,0,32);
  if(old_pixels==0 || new_pixels==0 || black_pixels==0)$fatal(1,"missing geometry coverage");
  $display("PASS: %0d geometry cases %0d exact RGB/pixel_ready checks; old background=%0d new foreground=%0d flip-mask=%0d; full-width zoom keeps two complete rows supplied with real fast RGB888 unpack and periodic word stalls",cases,total,old_pixels,new_pixels,black_pixels);
  $finish;
 end
 initial begin #400000000;$fatal(1,"geometry timeout cases=%0d checks=%0d",cases,checks);end
endmodule
