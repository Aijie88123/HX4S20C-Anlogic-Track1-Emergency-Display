`timescale 1ns/1ps
module tb_tf_protocol9_boundary;
 reg clk=0,rst=1,start7=0,start8=0;always #20 clk=~clk;
 reg version8=1;reg [7:0] extension=0;wire busy7,busy8;wire [3:0] nibble7,nibble8;
 wire busy=version8?busy8:busy7;wire [3:0] nibble=version8?nibble8:nibble7;
 wire valid7,valid8;integer accepted7=0,accepted8=0,frames=0;
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) tx7(
  .clk(clk),.rst(rst),.start(start7),.message(21'd1),.extension(extension),.stream_data(224'd0),.busy(busy7),.nibble(nibble7));
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) tx8(
  .clk(clk),.rst(rst),.start(start8),.message(21'd1),.extension(extension),.stream_data(224'd0),.busy(busy8),.nibble(nibble8));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) rx7(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(valid7),.message(),.extension(),.stream_data());
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) rx8(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(valid8),.message(),.extension(),.stream_data());
 always @(posedge clk)begin if(valid7)accepted7=accepted7+1;if(valid8)accepted8=accepted8+1;end
 task send(input ver,input [7:0] ext,input pass7,input pass8);
  integer before7,before8;
  begin @(negedge clk);before7=accepted7;before8=accepted8;version8=ver;extension=ext;
   if(ver)start8=1;else start7=1;
   @(negedge clk);start7=0;start8=0;wait(!busy);repeat(30)@(negedge clk);frames=frames+1;
   if(accepted7-before7!=pass7||accepted8-before8!=pass8)$fatal(1,"FAIL: version/extension boundary ver=%0d ext=%h old=%0d new=%0d",ver,ext,accepted7-before7,accepted8-before8);
  end
 endtask
 initial begin repeat(8)@(negedge clk);rst=0;
  send(1,8'h06,0,1);send(1,8'h26,0,1);
  send(1,8'h66,0,1);send(1,8'ha6,0,0);
  send(0,8'h06,1,0);send(0,8'h26,1,0);
  $display("PASS: true MAC/CRC protocol boundary frames=%0d: v9 accepts A animation bit6 and map bit5, rejects bit7; v8 still rejects bit6; mixed v8/v9 rejected in both directions",frames);$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: protocol boundary timeout");end
endmodule
