`timescale 1ns/1ps
module tb_spectrum_frames;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,dv=0,error=0;reg [3:0] nibble=0;
 wire accepted;wire [20:0] message;wire [7:0] extension;wire [223:0] stream;
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1)) receiver(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(dv),.error(error),.packet_valid(accepted),.message(message),.extension(extension),.stream_data(stream));
 reg [3:0] vectors[0:4095];reg [15:0] lengths[0:20];reg [7:0] expect_accept[0:20];
 integer offset=0,accepted_count=0,i,n,start_count;
 always @(posedge clk)if(accepted)begin
  if(stream[7:0]!==1 || stream[127:32]!==96'h800001_ffffff_123456_000001)$fatal(1,"Published PCM changed");
  accepted_count=accepted_count+1;
 end
 initial begin
  $readmemh("spectrum_rx_vectors.hex",vectors);$readmemh("spectrum_rx_lengths.hex",lengths);$readmemh("spectrum_rx_expected.hex",expect_accept);
  #100;rst=0;
  for(i=0;i<12;i=i+1)begin
   start_count=accepted_count;
   for(n=0;n<lengths[i];n=n+1)begin
    @(negedge clk);dv=1;nibble=vectors[offset+n];error=(i==10 && n==70);
   end
   offset=offset+lengths[i];@(negedge clk);dv=0;error=0;repeat(26)@(negedge clk);
   if(accepted_count-start_count!=expect_accept[i])$fatal(1,"CRC/header/length/error rejection case %0d",i);
  end
  if(accepted_count!=2)$fatal(1,"Unexpected accepted frame count");
  $display("PASS: independently generated v3 FCS, PCM endian/sign, wrong version/MAC/kind/reserved flags/padding, CRC, truncated/overlong frames and PHY error");$finish;
 end
endmodule
