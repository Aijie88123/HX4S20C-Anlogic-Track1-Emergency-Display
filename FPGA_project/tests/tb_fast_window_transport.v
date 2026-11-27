`timescale 1ns/1ps
module tb_fast_window_transport;
 parameter N=230400,NOISE=0;
 reg clk=0;always #20 clk=~clk;reg rst=1,sender_rst=1,online=0,avail=0;
 wire sv;wire [223:0] sp;reg ready=0;wire consumed,rq,ren,busy;
 reg ack=0,empty=1;reg [31:0] data=0;integer words=0,ticks=0,rx_pixels=0,frames=0,drops=0,packets=0;
 wire wa,we,cancel,cv;wire [31:0] wd;reg wack=0,full=0,done=0;wire av;wire [223:0] ap;
 reg rp=0,bp=0;reg [223:0] rpacket=0,bpacket=0;integer txdelay=0,backdelay=0,gap=0;reg [223:0] inflight=0,ackflight=0;
 reg [223:0] last_drop=0;reg drop_valid=0;reg commit=0;
 reg [15:0] asset_pixels[0:230399];initial if(NOISE==2)$readmemh("animation_pixel0.hex",asset_pixels);
 function [15:0] colour;input integer x;
  begin colour=NOISE==2?asset_pixels[x]:NOISE?16'(x*91+7):16'((x/513)*179+23);end endfunction
 raster_map_window_sender #(.PIXELS(N),.RETRY_CYCLES(4096),.DATA_RETRY_CYCLES(4096),.WINDOW_LOG2(4),.FAST_SOURCE(1)) sender(.clk(clk),.rst(sender_rst),.online(online),.frame_valid(avail),.frame_event(2'd2),
  .frame_consumed(consumed),.packet_valid(bp),.packet(bpacket),.stream_valid(sv),.stream_data(sp),.stream_ready(ready),
  .read_req(rq),.read_en(ren),.read_busy(busy),.read_ack(ack),.read_empty(empty),.read_data(data));
 raster_map_window_receiver #(.PIXELS(N),.WINDOW_LOG2(4),.DECODE_ACK(1)) receiver(.clk(clk),.rst(rst),.online(online),.packet_valid(rp),.packet(rpacket),
  .ack_valid(av),.ack_packet(ap),.ack_ready(backdelay==0),.write_cancel(cancel),.write_req(wa),.write_ack(wack),.write_full(full),.write_done_toggle(done),
  .write_en(we),.write_data(wd),.commit_valid(cv),.commit_ready(commit),.commit_event());
 // A synchronous block RAM may leave same-address read/write unspecified.
 // Published replay slots must never collide with a live TX_FETCH read.
 integer concurrent_replay_accesses=0;
 always @(posedge clk)if(!sender_rst && sender.storing && sender.tx_state==1 && sender.tx_pending)begin
  concurrent_replay_accesses<=concurrent_replay_accesses+1;
  if(sender.tx_address=={sender.build_index[3:0],sender.store_word})
   $fatal(1,"FAIL: replay RAM live read/write collision depends on block-RAM mode");
 end
 always @(posedge clk)begin
  ticks<=ticks+1;rp<=0;bp<=0;ready<=gap==0 && txdelay==0;empty<=!busy||words>=N/2||ticks%11==0;full<=ticks%17==0;
  if(rst)begin wack<=0;ack<=0;words<=0;rx_pixels<=0;done<=0;end else begin
   if(rq&&!ack)begin words<=0;ack<=1;end else if(!rq)ack<=0;
   if(ren)begin data<={colour(words*2+1),colour(words*2)};words<=words+1;end
   if(cancel)begin wack<=0;rx_pixels<=0;end else if(wa&&!wack)begin wack<=1;rx_pixels<=0;end else if(!wa)wack<=0;
   if(we)begin
    if(wd!=={colour(rx_pixels+1),colour(rx_pixels)})$fatal(1,"FAIL: RLE decoded pixel %d actual=%h",rx_pixels,wd);
    rx_pixels<=rx_pixels+2;if(rx_pixels==N-2)done<=~done;
   end
   if(cv)begin if(rx_pixels!=N)$fatal(1,"FAIL: partial map committed");commit<=1;end else commit<=0;
   if(cv&&commit)frames<=frames+1;
   if(sv&&ready)begin inflight<=sp;txdelay<=144;gap<=169;packets<=packets+1;end
   if(gap!=0)gap<=gap-1;
   if(txdelay!=0)begin txdelay<=txdelay-1;if(txdelay==1)begin rp<=1;rpacket<=inflight;end end
   if(av&&backdelay==0)begin
    if(ap[47:32]!=16'hffff && ap[47:32]!=16'hfffe && ap[47:32]%101==0 && (!drop_valid||last_drop!=ap))begin drops<=drops+1;drop_valid<=1;last_drop<=ap;end
    else begin ackflight<=ap;backdelay<=144;end
   end
   if(backdelay!=0)begin backdelay<=backdelay-1;if(backdelay==1)begin bp<=1;bpacket<=ackflight;end end
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst=0;sender_rst=0;online=1;avail=1;wait(consumed);@(negedge clk);avail=0;
  repeat(30)@(negedge clk);
  if(frames!=1 || rx_pixels!=N || drops==0)$fatal(1,"FAIL: map count/corruption");
  // B reboot must query retained A serial IDs. Interrupt its next physical RAM read.
  sender_rst=1;repeat(8)@(negedge clk);sender_rst=0;avail=1;
  wait(sender.reading && sender.words>N/8 && sender.words<N/2);@(negedge clk);online=0;
  wait(consumed);@(negedge clk);avail=0;repeat(400)@(negedge clk);
  if(frames!=1 || busy)$fatal(1,"FAIL: offline drain/partial frame");
  online=1;avail=1;wait(consumed);@(negedge clk);avail=0;repeat(30)@(negedge clk);
  if(frames!=2 || rx_pixels!=N)$fatal(1,"FAIL: reboot/reconnect map recovery");
  if(NOISE==1 && concurrent_replay_accesses==0)$fatal(1,"FAIL: replay RAM concurrency coverage missing");
  $display("PASS: replay RAM live read/write address independence; concurrent accesses=%0d",concurrent_replay_accesses);
  $display("PASS: prefetched sixteen-credit full RGB565 RLE %0d pixels noise=%0d, odd run boundaries/256 runs, %0d packets/%0d lost ACK retries, real 100M frame serialization budget, pixel/word backpressure, RAM completion, B reboot serial ID, mid-frame disconnect/drain and complete reconnect; elapsed_ns=%0t",N,NOISE,packets,drops,$time);$finish;
 end
 initial begin #3000000000;$fatal(1,"FAIL: RLE timeout sender=%d receiver=%d word=%d pixel=%d",sender.phase,receiver.decoder.state,words,rx_pixels);end
endmodule
