`timescale 1ns/1ps
module tb_scan_diagnostic;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] switches=15;reg [11:0] h=0;reg [9:0] v=0;
 wire hs=h>=110&&h<150,vs=v>=5&&v<10,de=h>=370&&v>=36;
 wire [11:0] x=h>=370?h-370:0;wire [9:0] y=v>=36?v-36:0;
 reg [31:0] random_word=32'h1238abcd;
 wire [23:0] rgb=random_word[23:0];wire oh,ov,od,active;wire [1:0] mode;wire [23:0] out_rgb;
 scan_diagnostic_mux #(.ENABLE(1)) dut(.clk(clk),.rst(rst),.switches(switches),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb(rgb),.active(active),.mode(mode),.o_hs(oh),.o_vs(ov),.o_de(od),.o_rgb(out_rgb));
 wire dh,dv,dd,da;wire [1:0] dm;wire [23:0] dr;
 scan_diagnostic_mux #(.ENABLE(0)) disabled(.clk(clk),.rst(rst),.switches(switches),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb(rgb),.active(da),.mode(dm),.o_hs(dh),.o_vs(dv),.o_de(dd),.o_rgb(dr));
 wire valid,user,last;wire [23:0] axis_rgb;
 video_rgb_to_axis_720p converter(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(out_rgb),.O_video_valid(valid),.O_video_user(user),.O_video_last(last),.O_video_data(axis_rgb));
 wire output_reset,ready;
 hdmi_startup_guard #(.SETTLE_FRAMES(2)) guard(.clk(clk),.async_reset(rst),.memory_ready(active),.frame_sync(ov),.video_locked(1'b1),.image_complete(1'b0),.axis_valid(valid),.axis_ready(!output_reset),.output_reset(output_reset),.video_ready(ready));
 always @(posedge clk)begin
  if(rst)begin h<=0;v<=0;end
  else if(h==1649)begin h<=0;v<=v==755?0:v+1'b1;end else h<=h+1'b1;
  random_word<={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
 end
 integer frames=0,pixels=0,solid=0,pattern=0,normal=0,checks=0,xf,yf,phase=0;
 reg [23:0] expected,original_before;reg [1:0] selected;reg expected_valid,expected_user,expected_last;
 reg prev_vs=0;
 always @(posedge clk)begin
  if(!rst)begin
   xf=x;yf=y;selected=mode;expected_valid=de;original_before=rgb;
   expected=selected==0?rgb:!de?0:selected==1?24'h104080:
    xf==0?24'hD00000:xf==1279?24'h00D000:yf==0?24'h0000D0:yf==719?24'hD0D000:24'h104080;
   expected_last=de&&xf==1279;expected_user=de&&xf==0&&yf==0;
   if({oh,ov,od}!=={hs,vs,de})$fatal(1,"diagnostic altered scan controls");
   if(da || dm!=0 || {dh,dv,dd,dr}!=={hs,vs,de,rgb})$fatal(1,"default-disabled diagnostic changed original tuple");
   #1;
   if({valid,user,last,axis_rgb}!=={expected_valid,expected_user,expected_last,expected})$fatal(1,"diagnostic/AXIS alignment mode=%0d x=%0d y=%0d got=%h expected=%h valid=%b/%b SOF=%b/%b TLAST=%b/%b",selected,xf,yf,axis_rgb,expected,valid,expected_valid,user,expected_user,last,expected_last);
   if(valid)begin pixels=pixels+1;if(selected==1)solid=solid+1;else if(selected==2)pattern=pattern+1;else normal=normal+1;end
   checks=checks+1;
  end
 end
 task full_frame;begin @(posedge vs);@(negedge vs);repeat(10)@(negedge clk);end endtask
 integer i;
 initial begin
  repeat(10)@(negedge clk);rst=0;
  repeat(5)full_frame;
  if(!ready)$fatal(1,"pure mode required a TF commit or initialized SDRAM");
  for(i=0;i<128;i=i+1)begin full_frame;if(!ready || mode!=1)$fatal(1,"solid mode lost output without TF");end
  wait(de && x==640);@(negedge clk);switches=14;repeat(30)@(negedge clk);
  if(mode!=1)$fatal(1,"diagnostic mode changed midframe");
  repeat(8)full_frame;if(mode!=2)$fatal(1,"edge pattern not selected");
  switches=8;repeat(8)full_frame;if(mode!=0)$fatal(1,"normal output not restored");
  if(solid<128*921600 || pattern<7*921600 || normal<7*921600)$fatal(1,"insufficient diagnostic coverage");
  $display("PASS: diagnostic pure mode >=128 complete720p frames without TF commit/SDRAM-ready, solid=%0d pattern=%0d normal=%0d pixels; %0d tuple comparisons; one-pixel borders/SOF/TLAST/HS/VS/DE aligned, frame-only switches and default-disabled normal output identical",solid,pattern,normal,checks);$finish;
 end
 initial begin #2000000000;$fatal(1,"diagnostic continuous test timeout");end
endmodule
