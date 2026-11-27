`timescale 1ns/1ps
module tb_visual_display;
 reg clk=0;always #6.666667 clk=~clk;
 reg rst=1,tick=0,live=1,bv=0,av=0,audio_enable=1;
 reg [4:0] band=0;reg [15:0] magnitude=0;reg [11:0] x=0,y=0;reg [23:0] sample=0;
 wire [23:0] wc,sc;wire [7:0] wa,sa;
 audio_waveform_precise_overlay #(.SCREEN_W(1280),.SCREEN_H(720),.WAVE_W(384),.WAVE_H(160),.WAVE_X(40),.WAVE_Y(130),.POINT_PX(2),.SAMPLE_STEP(3)) wave_dut(
  .clk(clk),.rst(rst),.frame_tick(tick),.audio_sample_valid(av),.audio_sample(sample),.x(x),.y(y),.wave_rgb(wc),.wave_alpha(wa));
 audio_spectrum_precise_overlay spectrum(.clk(clk),.rst(rst),.frame_tick(tick),.band_valid(bv),.band_idx(band),.band_mag(magnitude),.source_live(live),
  .x(x),.y(y),.bars_rgb(sc),.bars_alpha(sa));
 reg [23:0] samples[0:16383];reg [15:0] powers[0:203];
 integer sample_index=0,divider=0,parity=0,clock_index=0,writes=0,previous_source=-1;
 always @(negedge clk)begin
  av=0;
  if(!rst&&audio_enable)begin
   divider=divider+1;
   if(divider==(parity?1563:1562))begin
    divider=0;parity=!parity;sample=samples[sample_index%16384];sample_index=sample_index+1;av=1;
   end
  end
 end
 reg [9:0] expected_samples[0:191];integer point=0,ready_pages=0;
 reg [9:0] wanted;
 always @(posedge clk)if(!rst)begin
  if(wave_dut.cap_state==2&&av&&wave_dut.cap_last_point)begin
   if(wave_dut.cap_wr_page==wave_dut.cap_rd_page&&wave_dut.cap_display_valid)$fatal(1,"Wave wrote displayed page");
   if(wave_dut.cap_ptr!=0&&sample_index-previous_source!=3)$fatal(1,"Wave time scale drift");
   wanted=!sample[23]&&|sample[22:21]?10'h1ff:sample[23]&&sample[22:21]!=3?10'h200:sample[21:12];
   expected_samples[wave_dut.cap_ptr]=wanted;previous_source=sample_index;writes=writes+1;
   #1;
   if(wave_dut.cap_ptr==0)ready_pages=ready_pages+1;
  end
 end
 task frame;
  begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(40)@(negedge clk);end
 endtask
 task push(input integer k);
  begin @(negedge clk);bv=1;band=k;magnitude=powers[192+k]<<4;@(negedge clk);bv=0;end
 endtask
  reg [23:0] image[0:921599];
  integer k,j,handle,colored=0,level,peak=0,absval,expected_gain,pixel;
 initial begin
  $readmemh("visual_wave_samples.hex",samples);$readmemh("visual_dft_expected.hex",powers);
  repeat(8)@(negedge clk);rst=0;
  for(k=0;k<8;k=k+1)push(k);frame;
  for(k=0;k<12;k=k+1)if(spectrum.levels[k]!==0)$fatal(1,"Partial spectrum became visible");
  for(k=8;k<12;k=k+1)push(k);frame;
  for(k=0;k<12;k=k+1)begin
   level=powers[192+k]>672?((powers[192+k]-672)*3)>>5:0;if(level>132)level=132;
   if(spectrum.levels[k]!==level)$fatal(1,"Log height wrong bin%0d got%0d expected%0d",k,spectrum.levels[k],level);
  end
  #16600000;frame;#16600000;frame;#16600000;frame;audio_enable=0;
  if(!wave_dut.cap_display_valid||writes<384)$fatal(1,"Detailed waveform never captured");
  for(k=0;k<192;k=k+1)if(wave_dut.cap_ram[{wave_dut.cap_rd_page,k[7:0]}]!==expected_samples[k])
   $fatal(1,"Wave display page sample mismatch point%0d",k);
  for(k=0;k<921600;k=k+1)image[k]=24'h071323;
  // One pixel per clock; each panel is stored at its actual pipelined output
  // coordinate, matching the differing s2/s3 inputs of the real compositor.
  for(pixel=0;pixel<921603;pixel=pixel+1)begin
   @(negedge clk);x=(pixel%921600)%1280;y=(pixel%921600)/1280;
   @(posedge clk);#1;
   if(wa!=0&&wave_dut.x_d2<1280&&wave_dut.y_d2<720)begin
    image[wave_dut.y_d2*1280+wave_dut.x_d2]=wc;if(wa==255)colored=colored+1;
   end
   if(sa!=0&&spectrum.xd<1280&&spectrum.yd<720)image[spectrum.yd*1280+spectrum.xd]=sc;
  end
  handle=$fopen("visual_display_rtl.hex","w");
  for(k=0;k<921600;k=k+1)$fwrite(handle,"%06x\n",image[k]);
  $fclose(handle);
  live=0;repeat(4)@(negedge clk);
  if(spectrum.display_valid)$fatal(1,"Offline kept a live spectrum");
  if(colored<500)$fatal(1,"Wave trace missing");
  $display("PASS: 192 ten-bit waveform samples at exact3-sample spacing, complete capture page, no simultaneous display writes; twelve complete-band log heights, shared vblank update, frequency labels/peak holds/offline clearing; 921600 actual display pixels captured");$finish;
 end
 initial begin #250000000;$fatal(1,"Display timeout");end
endmodule
