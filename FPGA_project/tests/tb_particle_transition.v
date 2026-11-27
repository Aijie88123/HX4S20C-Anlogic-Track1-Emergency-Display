`timescale 1ns/1ps
module tb_particle_transition;
 reg clk=0,rst=1;always #6.666 clk=~clk;
 reg [3:0] sw=1;reg [2:0] photo=2;reg emergency=0;reg [1:0] ready_animation=0;
 reg complete=0;wire complete_ack,staging,display,map_mode,display_animation,have;
 reg photo_commit=0;reg [2:0] photo_seen=2;
 always @(posedge clk)if(rst)begin photo_commit<=0;photo_seen<=2;end
  else if(photo!=photo_seen)begin photo_commit<=~photo_commit;photo_seen<=photo;end
 wire req,en,ack,empty,hs,vs,de;wire [20:0] base,length;wire [23:0] rgb;
 reg [31:0] word_data=0;reg req_d=0,stream=0;reg [20:0] held_base=0,held_length=0;integer word_index=0,cycles=0;
 assign ack=req_d;assign empty=!stream || word_index>=held_length || cycles%127==13;
 particle_transition_probe d(.video_clk(clk),.rst_all(rst),.sw(sw),.display_slot(photo),.disp_src_toggle(photo_commit),.emergency_mode(emergency),.emergency_event(2'd0),
  .normal_animation_ready_video(ready_animation),.map_cdc_valid(complete),.map_commit_event(2'd0),.map_commit_animation(1'b1),
  .map_cdc_ready(complete_ack),.map_staging_slot(staging),.map_display_slot(display),.map_mode(map_mode),.map_display_animation(display_animation),.map_have(have),
  .video_read_req(req),.video_read_en(en),.video_read_req_ack(ack),.video_read_empty(empty),.video_read_data(word_data),.read_base(base),.read_len(length),
  .hs(hs),.vs(vs),.de(de),.vout_data_raw(rgb));
 function [23:0] pixel;input integer slot,sx,sy;
  reg [11:0] p;
  begin
   if(slot>=8)begin p={(4'h8+slot[3:0]),sx[5:2]^slot[3:0],sy[5:2]};pixel={p[11:8],p[11:8],p[7:4],p[7:4],p[3:0],p[3:0]};end
   else pixel={8'h30+slot[7:0]*8'd17,sx[7:0]^slot[7:0],sy[7:0]^{6'd0,sx[9:8]}};
  end
 endfunction
 function [31:0] packed_word;input integer addr;
  integer slot,local_word,j,b,pidx,bitno;reg [23:0] color;reg [11:0] c;
  begin
   packed_word=0;
   if(addr>=1843200)begin
    slot=8+(addr-1843200)/115200;local_word=(addr-1843200)%115200;
    for(j=0;j<32;j=j+1)begin bitno=local_word*32+j;pidx=bitno/12;color=pixel(slot,pidx%640,pidx/640);c={color[23:20],color[15:12],color[7:4]};packed_word[j]=c[bitno%12];end
   end else begin
    slot=addr/230400;local_word=addr%230400;
    for(j=0;j<4;j=j+1)begin b=local_word*4+j;pidx=b/3;color=pixel(slot,pidx%640,pidx/640);packed_word[j*8+:8]=color[(b%3)*8+:8];end
   end
  end
 endfunction
 function [23:0] normal_pixel;input integer page,ox,oy;
  integer ax,bx,ay,by,w,c,a,b;reg [23:0] p00,p01,p10,p11,result;
  begin
   ax=ox/2;bx=ax==639?639:ax+1;ay=(2*oy)/3;by=ay==479?479:ay+1;
   p00=pixel(page,ax,ay);p01=pixel(page,bx,ay);p10=pixel(page,ax,by);p11=pixel(page,bx,by);
   w=ay==479?0:oy%3==1?171:oy%3==2?85:0;
   for(c=0;c<3;c=c+1)begin a=(p00>>(8*c))&255;b=(p10>>(8*c))&255;
    if(ox%2)begin a=(a+((p01>>(8*c))&255))/2;b=(b+((p11>>(8*c))&255))/2;end
    result[c*8+:8]=((256-w)*a+w*b+128)/256;
   end
   normal_pixel=result;
  end
 endfunction
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(rst)begin req_d<=0;stream<=0;word_index<=0;end
  else begin
   req_d<=req;
   if(req)begin held_base<=base;held_length<=length;word_index<=0;stream<=0;end
   else if(req_d)stream<=1;
   if(en && !empty)begin word_data<=packed_word(held_base+word_index);word_index<=word_index+1;end
   if(d.freeze_dynamic_frame && complete_ack)$fatal(1,"complete frame acknowledged while frozen");
  end
 end
 integer x=0,y=0,checks=0,frames=0,flip_frames=0,zoom_frames=0,dynamic_frames=0,normal_frames=0;
 integer sx,sy,slot;reg [23:0] expected;reg previous_de=0,previous_vs=0;reg checking=0;
 always @(posedge clk)begin #1;
  if(rst)begin x=0;y=0;previous_de=0;previous_vs=0;end
  else begin
   if(vs && !previous_vs)begin x=0;y=0;end
   if(de)begin
    if(!previous_de)x=0;
    if(checking)begin
     sx=x/2;sy=(2*y)/3;slot=d.photo_geometry_old;
     if(d.photo_geometry_active)begin
      if(d.photo_geometry_flip)begin
       if(d.photo_geometry_width==0 || x<d.photo_geometry_left || x>=d.photo_geometry_left+d.photo_geometry_width)expected=0;
       else begin sx=((x-d.photo_geometry_left)*d.photo_geometry_inv_x)>>12;if(sx>639)sx=639;slot=d.photo_geometry_back?d.photo_geometry_new:d.photo_geometry_old;expected=pixel(slot,sx,sy);end
      end else begin
       if(d.photo_geometry_width!=0 && x>=d.photo_geometry_left && x<d.photo_geometry_left+d.photo_geometry_width && y>=d.photo_geometry_top && y<d.photo_geometry_top+d.photo_geometry_height)begin
        sx=((x-d.photo_geometry_left)*d.photo_geometry_inv_x)>>12;sy=((y-d.photo_geometry_top)*d.photo_geometry_inv_y)>>12;
        if(sx>639)sx=639;if(sy>479)sy=479;slot=d.photo_geometry_new;
       end
       expected=pixel(slot,sx,sy);
      end
     end else if(d.dynamic_scanout)expected=pixel(d.geometry_idle_source,x/2,(2*y)/3);
     else expected=normal_pixel(d.geometry_idle_source,x,y);
     if(rgb!==expected)$fatal(1,"particle transition pixel frame=%0d phase=%0d active=%b dyn=%b old=%0d new=%0d x=%0d y=%0d got=%h expected=%h",frames,d.photo_geometry_phase,d.photo_geometry_active,d.dynamic_scanout,d.photo_geometry_old,d.photo_geometry_new,x,y,rgb,expected);
     checks=checks+1;
    end
    x=x+1;
   end
   if(!de && previous_de)begin if(x!=1280)$fatal(1,"line width %0d",x);y=y+1;
    if(y==720)begin frames=frames+1;if(d.photo_geometry_active)begin if(d.photo_geometry_flip)flip_frames=flip_frames+1;else zoom_frames=zoom_frames+1;end else if(d.dynamic_scanout)dynamic_frames=dynamic_frames+1;else normal_frames=normal_frames+1;end
   end
   previous_de=de;previous_vs=vs;
  end
 end
 task send_complete;
  begin @(negedge clk);complete=1;wait(complete_ack);@(posedge clk);@(negedge clk);complete=0;end
 endtask
 task enter_particle;
  begin
   $display("TRACE: entry request frame=%0d",frames);
   @(posedge d.raw_vs);@(negedge clk);ready_animation=3;
   // A previously cached complete particle frame can begin the effect
   // before this newer complete is acknowledged. Observe both events.
   fork begin send_complete;end begin wait(d.photo_geometry_active);end join
   $display("TRACE: entry observed frame=%0d active=%b",frames,d.photo_geometry_active);
  end
 endtask
 task leave_particle;
  begin $display("TRACE: exit request frame=%0d",frames);@(posedge d.raw_vs);@(negedge clk);ready_animation=0;photo=3;wait(d.photo_geometry_active);end
 endtask
 integer mark;
 initial begin
  repeat(10)@(negedge clk);rst=0;checking=1;wait(frames>=3);
  enter_particle;
  // A further complete frame remains queued; neither slot nor ACK moves
  // while the current particle endpoint participates in the effect.
  fork begin send_complete;end begin wait(!d.photo_geometry_active);end join
  wait(dynamic_frames>=2);mark=flip_frames;
  send_complete;repeat(2)@(posedge d.raw_vs);
  if(flip_frames!=mark)$fatal(1,"live particle buffer swap restarted flip");
  leave_particle;wait(!d.photo_geometry_active);wait(normal_frames>=5);
  if(flip_frames!=34)$fatal(1,"flip entry/exit incomplete frames=%0d",flip_frames);
  @(posedge d.raw_vs);@(negedge clk);sw=2;photo=4;wait(d.photo_geometry_active);wait(!d.photo_geometry_active);
  enter_particle;wait(!d.photo_geometry_active);wait(dynamic_frames>=4);
  leave_particle;wait(!d.photo_geometry_active);wait(normal_frames>=7);
  if(zoom_frames!=51)$fatal(1,"zoom photo/entry/exit incomplete frames=%0d",zoom_frames);
  // Explicit FX_OFF keeps hard-cut behavior, then an emergency cancels
  // an in-progress geometry effect at its existing frame boundary.
  @(posedge d.raw_vs);@(negedge clk);sw=10;photo=5;repeat(3)@(posedge d.raw_vs);
  if(d.photo_geometry_active || d.freeze_dynamic_frame)$fatal(1,"FX_OFF ignored");
  @(negedge clk);sw=1;repeat(2)@(posedge d.raw_vs);photo=6;wait(d.photo_geometry_active);emergency=1;
  repeat(2)@(posedge d.raw_vs);if(d.photo_geometry_active || d.freeze_dynamic_frame)$fatal(1,"emergency failed to cancel geometry");
  checking=0;
  $display("PASS: real top wiring, continuous flip34/zoom51 full-phase entry/exit rasters; %0d frames %0d RGB checks, %0d live frames; held complete/ACK, resumed dynamic buffer swaps, hard-cut switch and emergency cancellation",frames,checks,dynamic_frames);
  $finish;
 end
 initial begin #2000000000;#2000000000;$fatal(1,"particle transition timeout frame=%0d active=%b map=%b",frames,d.photo_geometry_active,map_mode);end
endmodule
