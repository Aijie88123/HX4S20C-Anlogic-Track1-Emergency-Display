`timescale 1ns/1ps
module tb_six_packed_transport;
 parameter N=307200;localparam PN=N*3/4;
 reg clk=0;always #20 clk=~clk;
 reg ctl_clk=0;always #5 ctl_clk=~ctl_clk;
 reg rst=1,online=0,receiver_rst=1,vs=0,emergency=0;
 reg [5:0] available=0;reg [191:0] sizes=0;
 wire sv,sr;wire [223:0] sp;reg pv=0;reg [223:0] pp=0;
 wire av;wire [223:0] ap;wire rq,ren;reg rack=0;reg [31:0] rd=0;
 wire [2:0] role;reg [19:0] position=0;reg reading=0;
 wire wr,we,cv,cr,cancel,cv_ctl,cr_ctl;
 media_commit_cdc commit_bridge(.src_clk(clk),.dst_clk(ctl_clk),.rst(receiver_rst),.src_valid(cv),.src_ready(cr),.dst_valid(cv_ctl),.dst_ready(cr_ctl));wire [31:0] wd;reg wa=0,done=0,full=0;
 wire [2:0] crole,staging,display,page;wire [15:0] cw,ch,dw,dh;wire dv,epoch;
 wire [5:0] cached;integer count=0,commits=0,ticks=0,dropped=0,packets=0;
 reg drop_ack=0;reg [223:0] last_ack=0;reg [3:0] done_delay=0;
 reg [31:0] ram[0:7*PN-1];integer j;reg [2:0] base_slot;
 function [23:0] rgb;input integer x;input [2:0] r;begin rgb={r,5'd0,x[15:8],x[7:0]};end endfunction
 function [31:0] packed_word;input integer index;input [2:0] which;
  integer b,pos;reg [23:0] p;begin
   for(b=0;b<4;b=b+1)begin pos=index*4+b;p=rgb(pos/3,which);packed_word[b*8+:8]=p>>(8*(pos%3));end
  end endfunction
 wire empty=!reading || position>=N || ticks%7==0;
 assign sr=ticks%5!=0;
 media_image_sender #(.FRAME_PIXELS(N),.RETRY_CYCLES(160),.IMAGE_ROLES(6)) sender(.clk(clk),.rst(rst),.online(online),
  .available(available),.source_sizes(sizes),.source_fault(4'd0),.source_fault_recurring(1'b0),
  .packet_valid(pv),.packet(pp),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),
  .read_req(rq),.read_ack(rack),.read_empty(empty),.read_data(rd),.read_en(ren),.read_role(role));
 wire ax=av && ticks%9!=0;
 media_image_receiver #(.FRAME_PIXELS(N),.IMAGE_ROLES(6),.PACK_RGB888(1)) receiver(.clk(clk),.rst(receiver_rst),.online(online),
  .packet_valid(sv&&sr),.packet(sp),.ack_valid(av),.ack_packet(ap),.ack_ready(ax),
  .write_cancel(cancel),.write_req(wr),.write_ack(wa),.write_full(full),.write_done_toggle(done),.write_en(we),.write_data(wd),
  .frame_commit_valid(cv),.frame_commit_ready(cr),.commit_role(crole),.commit_width(cw),.commit_height(ch),.transfer_active(),.remote_fault(),.remote_fault_recurring());
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(4),.EMER_DWELL_MS(30),.IMAGE_ROLES(6),.EMER_SEQUENCE(1)) control(
  .clk(ctl_clk),.rst(receiver_rst),.key_next(1'b1),.key_auto(1'b1),.emergency(emergency),.vsync(vs),.remote_phase(9'd0),
  .incoming_complete(cv_ctl),.incoming_role(crole),.incoming_w(cw),.incoming_h(ch),.incoming_commit_ready(cr_ctl),
  .staging_slot(staging),.display_slot(display),.display_valid(dv),.page_index(page),.disp_src_w(dw),.disp_src_h(dh),
  .disp_src_toggle(epoch),.disp_audio_emergency(),.load_nearly_done(),.load_visual_active(),.auto_play_en_out(),
  .carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(cached),.state_code());
 always @(posedge clk)begin
  ticks<=ticks+1;vs<=ticks%128<10;full<=ticks%11==0;pv<=0;
  if(rst)begin rack<=0;position<=0;reading<=0;end
  else begin
   if(rq && !rack)begin rack<=1;position<=0;reading<=1;end
   else if(!rq)rack<=0;
   if(ren)begin rd<={rgb(position,role),8'd0};position<=position+1;end
  end
  if(receiver_rst)begin wa<=0;count<=0;done_delay<=0;done<=0;commits<=0;drop_ack<=0;end
  else begin
   if(cancel)begin wa<=0;count<=0;done_delay<=0;end
   else if(wr && !wa)begin wa<=1;count<=0;base_slot<=staging;end
   else if(!wr)wa<=0;
   if(we)begin
    if(dv && base_slot==display)$fatal(1,"FAIL: overwrites active frame");
    if(wd!==packed_word(count,crole))$fatal(1,"FAIL: pixel %0d role %0d actual %h",count,crole,wd);
    if(count>=PN)$fatal(1,"FAIL: duplicate pixels emitted");
    ram[base_slot*PN+count]<=wd;count<=count+1;
    if(count==PN-1)done_delay<=12;
   end
   if(done_delay!=0)begin done_delay<=done_delay-1;if(done_delay==1)done<=~done;end
   if(cv&&cr && receiver.state==5)begin if(count!=PN || done_delay!=0)$fatal(1,"FAIL: premature commit");commits<=commits+1;end
   if(ax)begin
    if(ap[7:0]==5 && ap[47:32]!=16'hffff && ap[47:32]!=16'hfffe && ap[47:32]%1009==1 && (!drop_ack || ap!=last_ack))begin
     drop_ack<=1;last_ack<=ap;dropped<=dropped+1;
    end else begin pv<=1;pp<=ap;end
   end
  end
  if(sv&&sr)packets<=packets+1;
 end
 task wait_all;integer guard;begin guard=0;while(cached!=63 || sender.sent!=63)begin @(negedge clk);guard=guard+1;if(guard>12000000)$fatal(1,"FAIL: cache timeout mask %b sender %d rx %d count %d",cached,sender.state,receiver.state,count);end end endtask
 initial begin
  for(j=0;j<6;j=j+1)sizes[j*32 +:32]=j==4?{16'd321,16'd427}:{16'd480,16'd640};
  repeat(8)@(negedge clk);rst=0;receiver_rst=0;online=1;available=63;
  wait_all;
  if(commits!=6 || dropped==0)$fatal(1,"FAIL: whole images and retries");
  for(j=0;j<6;j=j+1)begin
   if(ram[control.slot[j]*PN]!==packed_word(0,j) || ram[control.slot[j]*PN+PN-1]!==packed_word(PN-1,j))$fatal(1,"FAIL: final cache role %0d",j);
  end
  online=0;repeat(100)@(negedge clk);if(!dv || cached!=63)$fatal(1,"FAIL: offline cache lost");
  emergency=1;repeat(250)@(negedge clk);if(page>=2)$fatal(1,"FAIL: emergency cached switch");
  emergency=0;repeat(250)@(negedge clk);if(page<2)$fatal(1,"FAIL: normal restore");
  online=1;wait_all;
  // B reboot: retained A IDs must seed the next session, never stale completion.
  rst=1;repeat(8)@(negedge clk);rst=0;wait_all;
  // A reboot while B remains online/all sent: periodic status initiates replay.
  receiver_rst=1;repeat(8)@(negedge clk);receiver_rst=0;wait_all;
  // Mid-frame disconnect exercises draining an already issued RAM read.
  rst=1;repeat(8)@(negedge clk);rst=0;
  wait(sender.consumed>42 && sender.reading);@(negedge clk);online=0;
  repeat(N*3+100)@(negedge clk);if(sender.reading)$fatal(1,"FAIL: offline read not drained");
  online=1;wait_all;
  $display("PASS: six-role lossless packed RGB888 %0d-pixel frames, backpressure, %0d dropped ACKs, duplicates, complete SDRAM/VS commit, seven-slot isolation, unplug cache, emergency return, A/B reboot and mid-frame drain; packets=%0d",N,dropped,packets);$finish;
 end
 initial begin #2500000000;$fatal(1,"FAIL: timeout");end
endmodule
