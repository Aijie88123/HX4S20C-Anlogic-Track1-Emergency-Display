`timescale 1ns/1ps
module tb_map_wire_flags;
 reg clk=0,rst=1,dv=0,error=0;reg [3:0] nibble=0;always #20 clk=~clk;
 wire accepted;wire [223:0] payload;wire [20:0] message;wire [7:0] extension;
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1)) rx(
  .clk(clk),.rst(rst),.nibble(nibble),.valid(dv),.error(error),.packet_valid(accepted),
  .message(message),.extension(extension),.stream_data(payload));
 reg [3:0] vectors[0:4095];reg [15:0] lengths[0:19];reg [7:0] expect_accept[0:19];reg [223:0] expected[0:19];
 integer i,n,offset=0,count=0,start_count;
 always @(posedge clk)if(accepted)begin
  if(dv)$fatal(1,"Published map start_count validated frame end");
  if(payload!==expected[i])$fatal(1,"Map fields changed on the wire");count=count+1;
 end
 initial begin
  $readmemh("map_wire_nibbles.hex",vectors);$readmemh("map_wire_lengths.hex",lengths);
  $readmemh("map_wire_accept.hex",expect_accept);$readmemh("map_wire_payload.hex",expected);
  #100;rst=0;
  for(i=0;i<20;i=i+1)begin
   start_count=count;
   for(n=0;n<lengths[i];n=n+1)begin @(negedge clk);dv=1;nibble=vectors[offset+n];error=(i==13 && n==70);end
   offset=offset+lengths[i];@(negedge clk);dv=0;error=0;repeat(26)@(negedge clk);
   if(count-start_count!=expect_accept[i])$fatal(1,"v4 frame rejection failed at case %0d",i);
  end
  if(count!=5)$fatal(1,"v4 acceptance count differs %0d",count);
  $display("PASS: v4 independent CRC, complete scene fields, coexistence with spectrum/control, old version/wrong role/zoom/reserved/padding/CRC/half/short/long/PHY error rejected");$finish;
 end
endmodule

module tb_map_button;
 reg clk=0,rst=1,button=1;always #20 clk=~clk;wire short_press,long_press;integer shorts=0,longs=0;
 map_event_button #(.CLK_HZ(1000),.DEBOUNCE_MS(5),.HOLD_MS(700)) dut(.*);
 always @(posedge clk)begin if(short_press)shorts=shorts+1;if(long_press)longs=longs+1;end
 initial begin
  #100;rst=0;repeat(10)@(negedge clk);
  button=0;repeat(2)@(negedge clk);button=1;repeat(10)@(negedge clk);
  if(shorts || longs)$fatal(1,"Contact bounce created map command");
  button=0;repeat(100)@(negedge clk);button=1;repeat(10)@(negedge clk);
  if(shorts!=1 || longs)$fatal(1,"Short release event missing");
  button=0;repeat(750)@(negedge clk);button=1;repeat(10)@(negedge clk);
  if(shorts!=1 || longs!=1)$fatal(1,"Long press also changed the incident");
  button=0;repeat(750)@(negedge clk);repeat(750)@(negedge clk);button=1;repeat(10)@(negedge clk);
  if(shorts!=1 || longs!=2)$fatal(1,"Long hold repeats or leaks short event");
  button=0;repeat(100)@(negedge clk);rst=1;repeat(5)@(negedge clk);button=1;rst=0;repeat(10)@(negedge clk);
  if(shorts!=1 || longs!=2)$fatal(1,"Reset leaked a command");
  $display("PASS: shared parameter-scaled physical S2 debounce, short release, 700ms long hold, one closure step per hold, no short/long double command and reset");$finish;
 end
endmodule
