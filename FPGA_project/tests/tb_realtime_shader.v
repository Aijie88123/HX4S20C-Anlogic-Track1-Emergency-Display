`timescale 1ns/1ps
module tb_realtime_shader;
 reg clk=0;always #5 clk=~clk;
 reg [8:0] x=0,phase=0;reg [7:0] y=0;wire [15:0] rgb;
 b_particle_shader dut(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(rgb));
 reg [15:0] expected[0:1843199];integer i,n,f,changes=0;
 initial begin
  $readmemh("realtime_reference.hex",expected);f=$fopen("realtime_rtl.hex","w");
  for(i=0;i<1843204;i=i+1)begin
   @(negedge clk);n=i%57600;x=n%320;y=n/320;phase=(i/57600)*16;
   @(posedge clk);#1;
   if(i>=4)begin
    if(rgb!==expected[i-4])$fatal(1,"FAIL: shader RGB pixel %0d phase %0d xy %0d,%0d expected %h got %h",i-4,((i-4)/57600)*16,(i-4)%320,((i-4)%57600)/320,expected[i-4],rgb);
    $fwrite(f,"%04x\n",rgb);
    if(i>=57604 && rgb!=expected[i-4-57600])changes=changes+1;
   end
  end
  $fclose(f);if(changes<50000)$fatal(1,"FAIL: no real particle motion");
  $display("PASS: 1,843,200 independent RGB565 checks, complete inward and outward cycle, changing particle positions/tails/glints/gold and five-stage shader alignment; changed pixels=%0d",changes);$finish;
 end
endmodule
