`timescale 1ns/1ps
module tb_blue_smooth_preview;
 reg clk=0;always #5 clk=~clk;
 reg [8:0] x=0,phase=0;reg [7:0] y=0;wire [15:0] rgb;
 b_particle_shader dut(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(rgb));
 reg [15:0] expected[0:14745599];integer i,n,f;
 initial begin
  $readmemh("blue_smooth_reference.hex",expected);f=$fopen("blue_smooth_rtl.hex","w");
  for(i=0;i<14745604;i=i+1)begin
   @(negedge clk);n=i%57600;x=n%320;y=n/320;phase=(i/57600)*2;
   @(posedge clk);#1;
   if(i>=4)begin
    if(rgb!==expected[i-4])$fatal(1,"FAIL: continuous preview pixel %0d expected %h got %h",i-4,expected[i-4],rgb);
    $fwrite(f,"%04x\n",rgb);
   end
  end
  $fclose(f);
  $display("PASS: 14,745,600 independent RGB565 checks in 256 consecutive animation frames, natural two-phase steps at a 30fps presentation target; preview captured from actual B RTL");$finish;
 end
endmodule
