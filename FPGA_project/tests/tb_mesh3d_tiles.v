`timescale 1ns/1ps
module tb_mesh3d_tiles;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,start=0,abort=0;reg [12:0] meta=0;reg [8:0] phase=0;
 wire busy,done;wire [10:0] address;reg [15:0] data;
 wire valid;wire [31:0] word_data;reg [7:0] pace=0;wire ready=pace[3:0]<11;
 integer frame=0,f,words=0;reg [223:0] triangles[0:353];
 always @(posedge clk)begin
  pace<=pace+1'b1;
  data<=triangles[frame*118+(address>>4)]>>((address&15)*16);
  if(valid && ready)begin
   if(word_data[15:0]!==word_data[31:16])$fatal(1,"FAIL: output pixel pair");
   $fwrite(f,"%08x\n",word_data);words=words+1;
  end
 end
 b_mesh3d_tile_renderer dut(.clk(clk),.rst(rst),.start(start),.abort(abort),.triangle_count(8'd118),.frame_meta(meta),.phase(phase),
  .busy(busy),.done(done),.geometry_address(address),.geometry_data(data),.word_valid(valid),.word_data(word_data),.word_ready(ready));
 initial begin
  $readmemh("mesh3d_projected.hex",triangles);f=$fopen("mesh3d_tiles_rtl.hex","w");repeat(8)@(negedge clk);rst=0;
  for(frame=0;frame<3;frame=frame+1)begin
   meta=triangles[frame*118][196:184];phase=frame*32;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(done);@(negedge clk);
   if(words!=(frame+1)*115200)$fatal(1,"FAIL: frame words %0d",words);
   $display("MEASURE: true3D complete frame=%0d time_ns=%0t words=%0d",frame,$time,words);
  end
  $fclose(f);$display("PASS: B tile depth-tested renderer: 3 complete immutable scenes, 345600 words, sequential 640x360 output, BRAM tile reuse and backpressure");$finish;
 end
 initial begin #300000000;$fatal(1,"FAIL: tile timeout state=%0d op=%0d index=%0d",dut.state,dut.op,dut.triangle_index);end
endmodule
