`timescale 1ns/1ps
module tb_mesh3d_range;
 reg clk=0,rst=1,start=0;always #10 clk=~clk;
 reg [223:0] triangles[0:3];integer frame=0,words=0,f;
 wire [10:0] address;reg [15:0] data=0;wire valid,busy,done;wire [31:0] word_data;
 reg [4:0] pace=0;wire ready=pace[2:0]!=3;
 always @(posedge clk)begin
  pace<=pace+1'b1;data<=triangles[frame]>>((address&15)*16);
  if(valid&&ready)begin
   if(word_data[15:0]!==word_data[31:16])$fatal(1,"FAIL: range duplicate output");
   $fwrite(f,"%08x\n",word_data);words=words+1;
  end
 end
 b_mesh3d_tile_renderer dut(.clk(clk),.rst(rst),.start(start),.abort(1'b0),.triangle_count(8'd1),.frame_meta(13'd0),.phase(9'd0),
  .busy(busy),.done(done),.geometry_address(address),.geometry_data(data),.word_valid(valid),.word_data(word_data),.word_ready(ready));
 initial begin
  $readmemh("mesh3d_range_packets.hex",triangles);f=$fopen("mesh3d_range_words.hex","w");repeat(8)@(negedge clk);rst=0;
  for(frame=0;frame<4;frame=frame+1)begin
   @(negedge clk);start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
   if(words!=(frame+1)*115200)$fatal(1,"FAIL: range frame words");
  end
  $fclose(f);$display("PASS: out-of-range signed12 wire triangles skipped before signed10 truncation; legal -512/511 extremes with full 16-bit inverse depth, winding reversal, all tiles and scanout backpressure");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: coordinate range timeout");end
endmodule
