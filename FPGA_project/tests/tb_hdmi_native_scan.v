`timescale 1ns/1ps
module tb_hdmi_native_scan;
 reg clk=0,rst=1;always #6.666666 clk=~clk;
 reg [11:0] h=0;reg [9:0] v=0;
 wire raw_vs=v>=5&&v<10,raw_de=h>=370&&v>=36;
 reg [13:0] de_pipe=0,vs_pipe=0;
 always @(posedge clk)begin
  if(rst)begin h<=0;v<=0;de_pipe<=0;vs_pipe<=0;end
  else begin
   if(h==1649)begin h<=0;v<=v==755?0:v+1'b1;end else h<=h+1'b1;
   de_pipe<={de_pipe[12:0],raw_de};vs_pipe<={vs_pipe[12:0],raw_vs};
  end
 end
 wire user,valid,last,ready,locked;wire [23:0] data;
 video_rgb_to_axis_720p source(.I_clk(clk),.I_rst(rst),.I_vs(vs_pipe[13]),.I_de(de_pipe[13]),.I_rgb(24'h104080),.O_video_user(user),.O_video_valid(valid),.O_video_last(last),.O_video_data(data));
 wire [9:0] c0,c1,c2,ck;tri1 sda;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),.VTOTAL(756),.VSA(5),.VFP(5),.VBP(26),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) hdmi(
  .I_pixel_clk(clk),.I_rst(rst),.I_edid_read_trig(1'b0),.O_edid_read_valid(),.O_edid_read_data(),
  .I_axis_s_user(user),.I_axis_s_valid(valid),.I_axis_s_last(last),.I_axis_s_data(data),.O_axis_s_ready(ready),
  .I_audio_valid(1'b0),.I_audio_left_data(24'd0),.I_audio_right_data(24'd0),.I_acr_valid(1'b0),.I_acr_cts(20'd0),.I_acr_n(20'd6144),.O_video_locked(locked),.O_ddc_scl(),.IO_ddc_sda(sda),.O_ch0_tmds_data(c0),.O_ch1_tmds_data(c1),.O_ch2_tmds_data(c2),.O_clk_tmds_data(ck));
 function [7:0] decode;input [9:0] code;reg [7:0] qm;integer b;
 begin qm=code[9]?~code[7:0]:code[7:0];decode[0]=qm[0];for(b=1;b<8;b=b+1)decode[b]=code[8]?(qm[b]^qm[b-1]):~(qm[b]^qm[b-1]);end endfunction
 wire pure_payload=decode(c0)==8'h80 && decode(c1)==8'h40 && decode(c2)==8'h10;
 integer frames=0,accepted=0,rejected=0,stable_rejected=0,payload=0,run=0,max_run=0,lines=0;
 reg vs_d=0;
 always @(posedge clk)begin
  if(!rst)begin
   if(vs_pipe[13] && !vs_d)begin frames=frames+1;$display("TRACE: nativeHDMI source frame=%0d locked=%b accepted=%0d rejected=%0d stable_rejected=%0d payload=%0d lines=%0d max_run=%0d",frames,locked,accepted,rejected,stable_rejected,payload,lines,max_run);end
   if(valid)begin if(ready)accepted=accepted+1;else begin rejected=rejected+1;if(frames>=4)stable_rejected=stable_rejected+1;end end
   if(pure_payload)begin payload=payload+1;run=run+1;end
   else if(run!=0)begin if(run>max_run)max_run=run;if(run==1280)lines=lines+1;run=0;end
  end
  vs_d<=vs_pipe[13];
 end
 initial begin
  repeat(40)@(negedge clk);rst=0;wait(frames==10);repeat(20)@(negedge clk);
  if(!locked || max_run!=1280 || lines<6*720)$fatal(1,"native HDMI not producing full pure-color lines locked=%b max_run=%0d lines=%0d",locked,max_run,lines);
  if(stable_rejected!=0)$fatal(1,"native HDMI rejects running scan pixels stable_rejected=%0d",stable_rejected);
  $display("PASS: real encrypted HDMI core with exact production720p parameters and 14-cycle scan/overlay phase, accepted=%0d initial_rejected=%0d stable_rejected=%0d decoded_pure_payload=%0d full1280pixel_lines=%0d",accepted,rejected,stable_rejected,payload,lines);$finish;
 end
 initial begin #250000000;$fatal(1,"native HDMI timeout frames=%0d",frames);end
endmodule
