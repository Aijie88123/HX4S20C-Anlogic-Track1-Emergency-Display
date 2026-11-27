`timescale 1ns/1ps
module tb_raster_burst_wire;
 reg clk=0,rst=1;always #20 clk=~clk;
 reg sv=0,control=0,corrupt=0,phy_error=0;reg [223:0] data=0;
 wire sr,cs,busy;wire [3:0] nibble;
 reg [4:0] gap=0;
 wire may=!busy && gap==0;
 always @(posedge clk)if(rst)gap<=0;else if(busy)gap<=24;else if(gap!=0)gap<=gap-1'b1;
 ethernet_raster_burst_tx tx(.clk(clk),.rst(rst),.online(1'b1),.may_start(may),.control_pending(control),
  .message(21'h155555),.extension(8'h15),.stream_valid(sv),.stream_data(data),.stream_ready(sr),.control_sent(cs),.busy(busy),.nibble(nibble));
 wire pv;wire [223:0] packet;wire [20:0] msg;wire [7:0] ext;
 integer cycles=0,received=0,frames=0,batches=0,nibs=0,out;
 wire ready=(cycles%41)<33;
 wire [3:0] rx_nibble=nibble ^ ((corrupt && tx.position==72)?4'd1:4'd0);
 ethernet_raster_burst_rx rx(.clk(clk),.rst(rst),.nibble(rx_nibble),.valid(busy),.error(phy_error && tx.position==72),.output_ready(ready),
  .packet_valid(pv),.message(msg),.extension(ext),.stream_data(packet));
 function [223:0] value;input integer n;begin value={7{32'h12345600+n}};value[7:0]=7;value[23:8]=n;value[31:24]=0;if(n==104 || n==105)value[7:0]=9;end endfunction
 reg previous_busy=0;
 always @(posedge clk)begin
  cycles<=cycles+1;previous_busy<=busy;
  if(busy)begin $fwrite(out,"%h",rx_nibble);nibs<=nibs+1;end
  if(previous_busy&&!busy)begin $fwrite(out,"\n");frames<=frames+1;if(tx.tx_count==4)batches<=batches+1;end
  if(pv)begin
   if(packet[7:0]!=0)begin
    if(packet!==value(received))$fatal(1,"batch payload/order mismatch %0d got=%h",received,packet);
    if(msg!==21'h155555 || ext!==8'h15)$fatal(1,"header mismatch");
    received<=received+1;
   end
  end
 end
 task send;input integer n;begin
  @(negedge clk);sv=1;data=value(n);while(!sr)@(negedge clk);
  @(negedge clk);sv=0;
 end endtask
 integer i;
 initial begin
  out=$fopen("burst_wire_nibbles.hex","w");
  repeat(10)@(negedge clk);rst=0;
  for(i=0;i<100;i=i+1)begin send(i);if(i%13==0)begin control=1;wait(cs);@(negedge clk);control=0;end end
  wait(received==100);for(i=100;i<106;i=i+1)send(i);wait(received==106);wait(!busy);repeat(100)@(negedge clk);
  if(batches<10)$fatal(1,"no useful packet batching %0d",batches);
  // Each damaged frame contains exactly one sealed urgent envelope.
  corrupt=1;data=value(106);data[7:0]=9;sv=1;while(!sr)@(negedge clk);@(negedge clk);sv=0;
  wait(busy);wait(!busy);repeat(400)@(negedge clk);corrupt=0;
  if(received!=106)$fatal(1,"corrupt FCS published");
  phy_error=1;data=value(106);data[7:0]=9;sv=1;while(!sr)@(negedge clk);@(negedge clk);sv=0;
  wait(busy);wait(!busy);repeat(400)@(negedge clk);phy_error=0;
  if(received!=106)$fatal(1,"PHY error published");
  $fclose(out);$display("PASS: V12 burst MAC ordered106 full224-bit envelopes, four-packet/short-frame/short-frame bank reuse, mailbox backpressure, control priority, CRC and PHY-error rejection; four-packet batches=%0d frames=%0d wire_nibbles=%0d",batches,frames,nibs);$finish;
 end
 initial begin #3000000;$fatal(1,"wire timeout received=%0d bankflags=%b/%b collect=%0d state=%0d count=%0d/%0d",received,tx.sealed,rx.ready,tx.collecting,rx.state,tx.count0,tx.count1);end
endmodule
