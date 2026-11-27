`timescale 1ns/1ps
module tb_distributed_frames;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,start=0;reg [20:0] outgoing;
 wire busy;wire [3:0] tx_nibble;
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1)) tx(.clk(clk),.rst(rst),.start(start),.message(outgoing),.extension(8'h2a),.busy(busy),.nibble(tx_nibble));
 reg injection=0;reg [3:0] in_nibble;reg in_valid=0,in_error=0;
 wire [7:0] extension;wire packet_valid;wire [20:0] message;
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1)) rx(.clk(clk),.rst(rst),.nibble(injection?in_nibble:tx_nibble),.valid(injection?in_valid:busy),.error(injection?in_error:1'b0),.packet_valid(packet_valid),.message(message),.extension(extension));
 integer received=0,k,j,n,expected,limit;reg [7:0] golden[0:1313];reg [20:0] expected_message;integer log_file;
 always @(posedge clk)if(busy)$fwrite(log_file,"%x",tx_nibble);
 always @(posedge clk)if(packet_valid)begin received=received+1;if(!injection && (message!==expected_message || extension!==8'h2a))$fatal(1,"FAIL: TX/RX message mismatch");end
 task nyb;input [3:0] d;input v,e;begin @(negedge clk);in_nibble=d;in_valid=v;in_error=e;end endtask
 initial begin
  log_file=$fopen("distributed_core_tx_nibbles.hex","w");
  $readmemh("distributed_golden_frames.hex",golden);repeat(4)@(negedge clk);rst=0;
  for(k=0;k<24;k=k+1)begin
   outgoing={k[0],1'b1,8'd7,(k==23?8'hff:k[7:0]),k[2:0]};expected_message=outgoing;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(busy);wait(!busy);
   repeat(4)@(negedge clk);
   if(received!=k+1)$fatal(1,"FAIL: missing valid frame");
  end
  $fclose(log_file);
  injection=1;
  for(k=0;k<18;k=k+1)begin
   expected=received;limit=(k==13?71:(k==14?73:72));
   for(j=0;j<limit;j=j+1)begin
    nyb(golden[k*73+j][3:0],1,(k==16 && j*2==27));
    if(!(k==17 && j==limit-1))nyb(golden[k*73+j][7:4],1,(k==16 && j*2+1==27));
   end
   nyb(0,0,0);repeat(4)@(negedge clk);
   if(k<8 && received!=expected+1)$fatal(1,"FAIL: Python golden frame rejected");
   if(k>=8 && received!=expected)$fatal(1,"FAIL: malformed frame accepted case %0d",k);
  end
  $display("PASS: protocol v2 reserved epoch/phase bits and legacy v1 rejection; 24 TX/RX frames and 18 independent Python CRC vectors; wrong peer/type/version/reserved bits, corrupt FCS, RX error, short/long/half frames rejected");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: frame test timeout");end
endmodule
