`timescale 1ns/1ps
module tb_animation_transport #(parameter PROFILE=1);wire dense;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,online=1,valid_frame=0;reg [6:0] frame_index=0;
 wire consumed,req,ren,busy,rack,empty,storage_req,storage_en,storage_busy,fault;
 wire [31:0] data;reg storage_ack=0;reg [31:0] storage_data=0;integer rd_index=0,rd_start=0;
 reg [31:0] source[0:307199];reg [31:0] received[0:115199];
 wire sv,av;wire [223:0] sp,ap;reg pv_a=0,pv_b=0;reg [223:0] pa=0,pb=0;
 integer fwd=0,back=0,gap=0,bgap=0,packets=0,commits=0,rxwords=0,ticks=0;
 reg [223:0] fhold,bhold;reg drop_ack=1;integer duplicates=0;
 wire sr=fwd==0 && gap==0,ar=back==0 && bgap==0;
 wire wrq,wcancel,wen,cv;wire [31:0] wdata;wire [1:0] cev;wire ca;
 reg wack=0,done=0;wire cr=cv;integer start_tick=0;
 b_animation_cache cache(.clk(clk),.rst(rst),.enabled(online),.frame_index(frame_index),.frame_consumed(consumed),
  .raster_req(req),.raster_en(ren),.raster_ack(rack),.raster_empty(empty),.raster_data(data),
  .storage_req(storage_req),.storage_en(storage_en),.storage_busy(storage_busy),.storage_ack(storage_ack),
  .storage_empty(1'b0),.storage_data(storage_data),.fault(fault),.dense_mode(dense));
 raster_map_window_sender #(.ALLOW_ANIMATION(1),.RETRY_CYCLES(5000000)) sender(.clk(clk),.rst(rst),.online(online),
  .frame_valid(valid_frame),.frame_event(2'd0),.frame_animation(1'b1),.current_animation(),.frame_consumed(consumed),
  .packet_valid(pv_b),.packet(pb),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),
  .read_req(req),.read_en(ren),.read_busy(busy),.read_ack(rack),.read_empty(empty),.read_data(data));
 raster_map_window_receiver #(.ALLOW_ANIMATION(1)) receiver(.clk(clk),.rst(rst),.online(online),.packet_valid(pv_a),.packet(pa),
  .ack_valid(av),.ack_packet(ap),.ack_ready(ar),.write_cancel(wcancel),.write_req(wrq),.write_ack(wack),.write_full(1'b0),
  .write_done_toggle(done),.write_en(wen),.write_data(wdata),.commit_valid(cv),.commit_ready(cr),.commit_event(cev),.commit_animation(ca));
 always @(posedge clk)begin
  ticks<=ticks+1;pv_a<=0;pv_b<=0;
  if(storage_req && !storage_ack)begin storage_ack<=1;rd_index<=0;rd_start<=frame_index*(dense?3584:5632);end
  if(!storage_req)storage_ack<=0;
  if(storage_en)begin storage_data<=source[rd_start+rd_index];rd_index<=rd_index+1;end
  if(sv && sr)begin fhold<=sp;fwd<=144;gap<=169;packets<=packets+1;end
  if(gap!=0)gap<=gap-1;
  if(fwd!=0)begin fwd<=fwd-1;if(fwd==1)begin pv_a<=1;pa<=fhold;end end
  if(av && ar)begin
   if(drop_ack && ap[47:32]==2 && !ap[31] && !ap[29])begin drop_ack<=0;duplicates<=duplicates+1;end
   else begin bhold<=ap;back<=144;bgap<=169;end
  end
  if(bgap!=0)bgap<=bgap-1;
  if(back!=0)begin back<=back-1;if(back==1)begin pv_b<=1;pb<=bhold;end end
  wack<=wrq;
  if(wrq || wcancel)rxwords<=0;
  if(wen)begin
   if(rxwords>=115200)$fatal(1,"frame overrun");received[rxwords]<=wdata;
   if(rxwords==115199)done<=~done;
   rxwords<=rxwords+1;
  end
  if(cv && cr)begin
   if(!ca || rxwords!=115200)$fatal(1,"partial or mistagged animation frame");
   commits<=commits+1;
  end
 end
 integer x,y,pixel,word_index,idx;reg [23:0] rgb;reg [15:0] colour;
 task check_frame(input integer n);
  begin
   for(y=0;y<360;y=y+1)for(x=0;x<320;x=x+1)begin
    pixel=PROFILE==2?(y*3/10)*192+x*3/5:(y*3/8)*240+x*3/4;
    word_index=n*(PROFILE==2?3584:5632)+20+pixel/6;idx=(source[word_index]>>(8+4*(pixel%6)))&15;
    rgb=source[n*(PROFILE==2?3584:5632)+4+idx]>>8;colour={rgb[23:19],rgb[15:10],rgb[7:3]};
    if(received[y*320+x]!=={colour,colour})$fatal(1,"animation golden mismatch frame=%0d x=%0d y=%0d got=%h expected=%h",n,x,y,received[y*320+x],{colour,colour});
   end
  end
 endtask
 task show(input [6:0] n);
  integer c,p,t;
  begin
   @(negedge clk);frame_index=n;valid_frame=1;c=commits;p=packets;t=ticks;
   wait(consumed);@(negedge clk);valid_frame=0;
   if(commits!=c+1)$fatal(1,"frame released without commit");check_frame(n);
   $display("MEASURE: frame=%0d packets=%0d frame_ms=%0.3f",n,packets-p,(ticks-t)/25000.0);
   repeat(40)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh(PROFILE==2?"../assets/normal_animation_v2/animation_words.hex":"../assets/normal_animation/animation_words.hex",source);
  repeat(20)@(negedge clk);rst=0;
  show(0);show(1);show(PROFILE==2?42:20);show(PROFILE==2?83:39);show(0);
  if(duplicates!=1 || fault)$fatal(1,"retry/header coverage");
  // Disconnect a frame in flight: no partial frame may commit, reconnect restarts.
  @(negedge clk);valid_frame=1;frame_index=2;wait(rxwords>1000);@(negedge clk);online=0;
  repeat(40)@(negedge clk);valid_frame=0;repeat(1000)@(negedge clk);online=1;repeat(40)@(negedge clk);
  show(2);
  $display("PASS: 0/1/20/39/0 animation loop, 691200 complete RGB565 words independently checked, 100M wire budget, lost ACK retry, partial frame discarded on disconnect and complete reconnect");
  $finish;
 end
 initial begin #1500000000;$fatal(1,"animation transport timeout sender=%d cache=%d receiver=%d",sender.phase,cache.state,receiver.decoder.state);end
endmodule
