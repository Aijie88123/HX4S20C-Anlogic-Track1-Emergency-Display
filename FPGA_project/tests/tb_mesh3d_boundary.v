`timescale 1ns/1ps
module tb_mesh3d_boundary #(parameter SOURCE_B=0);
 reg clk=0,rst=1,start9=0,start10=0;always #20 clk=~clk;
 reg version10=1;reg [7:0] extension=0;reg [223:0] payload=0;
 wire busy9,busy10;wire [3:0] nibble9,nibble10;
 wire busy=version10?busy10:busy9;wire [3:0] nibble=version10?nibble10:nibble9;
 wire valid9,valid10;integer count9=0,count10=0,frames=0;
 ethernet_frame_tx #(.BOARD_B(SOURCE_B),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) tx9(
  .clk(clk),.rst(rst),.start(start9),.message(21'd1),.extension(extension),.stream_data(payload),.busy(busy9),.nibble(nibble9));
 ethernet_frame_tx #(.BOARD_B(SOURCE_B),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) tx10(
  .clk(clk),.rst(rst),.start(start10),.message(21'd1),.extension(extension),.stream_data(payload),.busy(busy10),.nibble(nibble10));
 ethernet_frame_rx #(.BOARD_B(!SOURCE_B),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) rx9(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(valid9),.message(),.extension(),.stream_data());
 ethernet_frame_rx #(.BOARD_B(!SOURCE_B),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) rx10(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(valid10),.message(),.extension(),.stream_data());
 always @(posedge clk)begin if(valid9)count9=count9+1;if(valid10)count10=count10+1;end
 task send(input ver,input [7:0] ext,input [7:0] kind,rev,input pass9,pass10);
  integer c9,c10;
  begin
   @(negedge clk);c9=count9;c10=count10;version10=ver;extension=ext;payload={208'd0,rev,kind};
   if(ver)start10=1;else start9=1;
   @(negedge clk);start9=0;start10=0;wait(!busy);repeat(30)@(negedge clk);frames=frames+1;
   if(count9-c9!=pass9||count10-c10!=pass10)$fatal(1,"FAIL: source=%0d version=%d kind=%d rev=%d accepted9=%0d accepted10=%0d",SOURCE_B,ver?10:9,kind,rev,count9-c9,count10-c10);
  end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst=0;
  send(1,8'h06,0,0,0,1);send(0,8'h06,0,0,1,0);
  if(!SOURCE_B)begin
   send(1,8'h66,0,0,0,1);send(1,8'ha6,0,0,0,0);
   send(1,8'h06,14,1,0,1);send(0,8'h06,14,1,0,0);
   send(1,8'h06,15,1,0,0);send(1,8'h06,14,2,0,0);
   send(1,8'h06,13,1,0,1);send(1,8'h06,10,0,0,1);
  end else begin
   send(1,8'h26,0,0,0,1);send(1,8'h46,0,0,0,0);
   send(1,8'h06,15,1,0,1);send(0,8'h06,15,1,0,0);
   send(1,8'h06,14,1,0,0);send(1,8'h06,15,2,0,0);
   send(1,8'h06,12,1,0,1);send(1,8'h06,9,0,0,1);
  end
  $display("PASS: v9/v10 mixed-version rejection both ways, v10 geometry/ACK direction and revision validation, existing TF/particle kinds and feedback bits sourceB=%d frames=%d",SOURCE_B,frames);$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: v10 boundary timeout");end
endmodule
