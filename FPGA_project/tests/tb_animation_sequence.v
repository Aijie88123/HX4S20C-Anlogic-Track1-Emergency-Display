`timescale 1ns/1ps
module tb_animation_sequence;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,emergency=0,vs=0,complete=0;reg [2:0] role=2;
 wire ready,valid,animation,map_ready;wire [2:0] page;wire [4:0] feedback;
 reg [8:0] phase=9'h120;integer t=0;reg [2:0] history[0:15];integer changes=0;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1)) dut(
  .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.emergency(emergency),.vsync(vs),.remote_phase(phase),
  .incoming_complete(complete),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(ready),
  .staging_slot(),.display_slot(),.display_valid(valid),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(),.state_code(),.emergency_map_ready(map_ready),.normal_animation(animation));
 always @(negedge clk)begin
  t=t+1;vs=t%20<3;
  phase[0]=feedback[0];phase[2]=feedback[4] && dut.elapsed>=3000;phase[1]=feedback[4] && dut.elapsed>=2840;
 end
 reg [2:0] last=7;
 always @(negedge clk)if(!rst && valid && page!=last)begin history[changes]=page;changes=changes+1;last=page;end
 task deliver(input [2:0] r);
  begin @(negedge clk);role=r;complete=1;wait(ready);@(posedge clk);@(negedge clk);complete=0;repeat(20)@(negedge clk);end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  deliver(2);deliver(3);deliver(4);deliver(0);deliver(1);
  wait(animation);repeat(20000)@(negedge clk);
  if(page!=4 || changes!=3 || history[0]!=2 || history[1]!=3 || history[2]!=4)$fatal(1,"normal sequence wrapped or carrier displayed");
  emergency=1;wait(page==0);if(animation || map_ready)$fatal(1,"animation covered emergency prelude");
  wait(page==1);wait(map_ready);repeat(40)@(negedge clk);
  if(changes!=5 || history[3]!=0 || history[4]!=1)$fatal(1,"05/06 order");
  emergency=0;wait(animation);repeat(100)@(negedge clk);
  if(page!=4 || !animation)$fatal(1,"normal animation resume");
  $display("PASS: online timer 01->02->03->animation, 20s without wrapping, emergency 05->06->map, return resumes animation; carrier never displayed");$finish;
 end
 initial begin #1000000;$fatal(1,"sequence timeout page=%d elapsed=%d animation=%b phase=%h",page,dut.elapsed,animation,phase);end
endmodule
