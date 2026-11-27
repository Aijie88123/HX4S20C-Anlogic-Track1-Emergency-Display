`timescale 1ns/1ps
module tb_fast_geometry_continuous;
 reg clk=0,rst=1;always #6.666 clk=~clk;
 reg eligible=0,commit_toggle=0;reg [2:0] selection=1,source_slot=2;
 wire active,flip,back,hold;wire [11:0] width,left;wire [9:0] height,top;wire [16:0] inv_x,inv_y;
 wire [5:0] animation_phase;wire [2:0] old_slot,new_slot,idle_slot;
 wire frame_start;
 photo_geometry_control #(.PHASE_STEP(2)) control(.clk(clk),.rst(rst),.frame_start(frame_start),.eligible(eligible),.selector(selection),
  .slot_in(source_slot),.commit_toggle(commit_toggle),.active(active),.flip(flip),.phase(animation_phase),
  .old_slot(old_slot),.new_slot(new_slot),.width(width),.height(height),.left(left),.top(top),.inv_x(inv_x),.inv_y(inv_y),
  .back_half(back),.idle_slot(idle_slot),.hold_slot(hold));
 wire [20:0] geo_base;
 wire req,en,ack,word_read,pixel_empty;wire [31:0] pixel_data;reg [31:0] word_data=0;
 wire [20:0] base=active?geo_base:(hold?idle_slot:source_slot)*21'd230400;reg req_d=0,stream=0;reg [20:0] held_base=0;integer word_index=0,cycles=0;
 wire word_empty=!stream || word_index>=(active?512:230400) || cycles%127==13;
 assign ack=req_d;
 wire hs,vs,de,ready,rawvs,rawde;wire [11:0] rawx,rawy;wire [23:0] rgb;
 rgb888_frame_unpack #(.FAST_WORD_READ(1)) unpack(.clk(clk),.rst(rst),.restart(req),.fast_mode(active),
  .word_empty(word_empty),.word_data(word_data),.word_read(word_read),.pixel_read(en),.pixel_empty(pixel_empty),.pixel_data(pixel_data));
 video_scanout_720p #(.ENABLE_GEOMETRY(1)) dut(.clk(clk),.rst(rst),.read_req(req),.read_req_ack(ack),
  .read_en(en),.read_data(pixel_data),.read_empty(pixel_empty),.hs(hs),.vs(vs),.de(de),.rgb(rgb),.pixel_ready(ready),
  .raw_hs(),.raw_vs(rawvs),.raw_de(rawde),.raw_x(rawx),.raw_y(rawy),.raw_frame_start(frame_start),
  .geometry_active(active),.geometry_flip(flip),.geometry_width(width),.geometry_left(left),
  .geometry_height(height),.geometry_top(top),.geometry_inv_x(inv_x),.geometry_inv_y(inv_y),
  .geometry_old_base(old_slot*21'd230400),.geometry_new_base(new_slot*21'd230400),.geometry_back_half(back),.geometry_read_base(geo_base));
 function [23:0] pixel;input integer slot,sx,sy;
  begin pixel={8'h30+slot[7:0]*8'd17,sx[7:0]^slot[7:0],sy[7:0]^{6'd0,sx[9:8]}};end
 endfunction
 function [31:0] packed_word;input integer addr;integer slot,local_word,j,b,pidx;reg [23:0] color;
  begin
   slot=addr/230400;local_word=addr%230400;packed_word=0;
   for(j=0;j<4;j=j+1)begin b=local_word*4+j;pidx=b/3;color=pixel(slot,pidx%640,pidx/640);packed_word[j*8+:8]=color[(b%3)*8+:8];end
  end
 endfunction
 function [23:0] normal_pixel;input integer page,ox,oy;
 integer ax,bx,ay,by,w,c,a,b;reg [23:0] p00,p01,p10,p11,result;
 begin
  ax=ox/2;bx=ax==639?639:ax+1;ay=(2*oy)/3;by=ay==479?479:ay+1;
  p00=pixel(page,ax,ay);p01=pixel(page,bx,ay);p10=pixel(page,ax,by);p11=pixel(page,bx,by);
  w=ay==479?0:oy%3==1?171:oy%3==2?85:0;
  for(c=0;c<3;c=c+1)begin
   a=(p00>>(8*c))&255;b=(p10>>(8*c))&255;
   if(ox%2)begin a=(a+((p01>>(8*c))&255))/2;b=(b+((p11>>(8*c))&255))/2;end
   result[c*8+:8]=((256-w)*a+w*b+128)/256;
  end
  normal_pixel=result;
 end endfunction
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
     sx=x/2;sy=(2*y)/3;slot=old_slot;
     if(!active)begin expected=normal_pixel(hold?idle_slot:source_slot,x,y);end
     else if(flip)begin
      if(width==0 || x<left || x>=left+width)begin expected=0;black_pixels=black_pixels+1;end
      else begin sx=((x-left)*inv_x)>>12;if(sx>639)sx=639;slot=back?new_slot:old_slot;expected=pixel(slot,sx,sy);end
     end else begin
      if(width!=0 && x>=left && x<left+width && y>=top && y<top+height)begin
       sx=((x-left)*inv_x)>>12;sy=((y-top)*inv_y)>>12;
       if(sx>639)sx=639;if(sy>479)sy=479;slot=new_slot;new_pixels=new_pixels+1;
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
 integer completed_frames=0,flip_frames=0,zoom_frames=0,normal_frames=0;
 always @(posedge clk)begin #2;if(!rst && de && x==1280 && y==719)begin completed_frames=completed_frames+1;
  if(active)begin if(flip)flip_frames=flip_frames+1;else zoom_frames=zoom_frames+1;end
  else normal_frames=normal_frames+1;
 end end
 task commit;input [2:0] page;
 begin @(posedge rawvs);@(negedge clk);source_slot=page;commit_toggle=~commit_toggle;end endtask
 initial begin
  repeat(10)@(negedge clk);rst=0;checking=1;
  wait(completed_frames>=2);@(posedge rawvs);eligible=1;
  repeat(2)@(posedge rawvs);
  commit(3);wait(active);wait(!active);
  wait(completed_frames>=22);selection=2;commit(4);wait(active);
  wait(animation_phase==8);commit(5);commit(6);
  wait(!active);wait(active);wait(!active);
  wait(normal_frames>=5);checking=0;
  if(flip_frames!=17 || zoom_frames!=34)$fatal(1,"incomplete animation raster count flip=%0d zoom=%0d",flip_frames,zoom_frames);
  $display("PASS: continuous real controller/row reader/fast RGB888 unpack/original normal scanout; %0d complete frames (%0d flip/%0d zoom/%0d normal), %0d exact RGB/pixel_ready checks, source commits queued during zoom, no raster reset across entry/exit and restored bilinear source sampling",completed_frames,flip_frames,zoom_frames,normal_frames,total);
  $finish;
 end
 initial begin #2500000000;$fatal(1,"geometry timeout cases=%0d checks=%0d",cases,checks);end
endmodule
