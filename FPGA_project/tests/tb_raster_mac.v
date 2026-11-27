`timescale 1ns/1ps
module tb_raster_mac;
 reg clk=0;always #20 clk=~clk;reg rst=1,starta=0,startb=0;reg [223:0] sa=0,sb=0;
 wire ba,bb;wire [3:0] na,nb;wire va,vb;wire [223:0] pa,pb;integer j,ca=0,cb=0,fd;
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1)) ta(.clk(clk),.rst(rst),.start(starta),.message(21'd0),.extension(8'd0),.stream_data(sa),.busy(ba),.nibble(na));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1)) tb(.clk(clk),.rst(rst),.start(startb),.message(21'd0),.extension(8'd0),.stream_data(sb),.busy(bb),.nibble(nb));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1)) ra(.clk(clk),.rst(rst),.nibble(na),.valid(ba),.error(1'b0),.packet_valid(va),.message(),.extension(),.stream_data(pa));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1)) rb(.clk(clk),.rst(rst),.nibble(nb),.valid(bb),.error(1'b0),.packet_valid(vb),.message(),.extension(),.stream_data(pb));
 always @(posedge clk)begin if(va)begin ca=ca+1;if(pa!==sa)$fatal(1,"FAIL: A->B ACK/PCM truncation");end
  if(vb)begin cb=cb+1;if(pb!==sb)$fatal(1,"FAIL: B->A media/map/spectrum payload");end
  if(bb)$fwrite(fd,"%1x",nb);if(!bb&&tb.position==0&&cb!=0)$fflush(fd);
 end
 task send;begin @(negedge clk);starta=1;startb=1;@(negedge clk);starta=0;startb=0;wait(!ba&&!bb);repeat(5)@(negedge clk);end endtask
 initial begin
  fd=$fopen("raster_tx_nibbles.hex","w");repeat(8)@(negedge clk);rst=0;
  for(j=0;j<12;j=j+1)begin
   sa=0;sb=0;sa[7:0]=j%3==0?1:j%3==1?5:8;sa[23:8]=sa[7:0]==1?16'd1:16'habcd;
   sa[47:32]=16'hfffe;sb[7:0]=j%4==0?2:j%4==1?4:j%4==2?7:6;
   sb[23:8]=sb[7:0]<=3?16'd1:16'hcdef;sb[199:56]=144'hfedcba98765432100123456789abcdef123456;
   if(sb[7:0]==3)sb[15:8]=8'h12;
   send;
  end
  if(ca!=12||cb!=12)$fatal(1,"FAIL: protocol v5 frame count %d/%d",ca,cb);
  $fclose(fd);$display("PASS: real protocol-v6 MAC TX/RX: 24 PCM/ACK/spectrum/map/media/status frames, full 224-bit media and 128-bit ACK, high frame IDs and original reserved fields");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: MAC timeout");end
endmodule
