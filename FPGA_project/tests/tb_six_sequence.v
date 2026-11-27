`timescale 1ns/1ps
module tb_six_sequence;
 reg clk=0,rst=1,emergency=0,vs=0,incoming=0,next_key=1,auto_key=1;
 always #5 clk=~clk;
 integer divider=0;
 always @(negedge clk)begin divider=divider+1;vs=(divider%10)==0;end
 reg [2:0] role=0;reg [15:0] width=640,height=480;
 wire commit,shown,map_ready;wire [2:0] staging,display,page;wire [5:0] cached;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(2),.EMER_DWELL_MS(80),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.EMER_WAIT_MS(120)) dut(
  .clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.emergency(emergency),.vsync(vs),.remote_phase(9'd0),
  .incoming_complete(incoming),.incoming_role(role),.incoming_w(width),.incoming_h(height),.incoming_commit_ready(commit),
  .staging_slot(staging),.display_slot(display),.display_valid(shown),.page_index(page),.cached_roles(cached),
  .disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),.load_nearly_done(),.load_visual_active(),
  .auto_play_en_out(),.carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.state_code(),.emergency_map_ready(map_ready));
 wire map_mode;reg map_complete=1;
 map_received_frame_control map_control(.clk(clk),.rst(rst),.vsync(vs),.emergency(emergency&&map_ready),.event_type(2'd0),
  .complete(map_complete),.incoming_event(2'd0),.commit_ready(),.staging_slot(),.display_slot(),.map_mode(map_mode),.have_map());
 integer i,j;integer observed=0;reg [2:0] previous_page=7;reg old_ready=0;integer emergency_pages=0;
 always @(posedge clk)begin
  #1;
  if(!rst)begin
   for(i=0;i<6;i=i+1)begin
    if(dut.slot[i]==staging)$fatal(1,"FAIL: staging overlaps role %d",i);
    for(j=i+1;j<6;j=j+1)if(dut.slot[i]==dut.slot[j])$fatal(1,"FAIL: duplicate role slots");
   end
   if(emergency && page<2 && shown && page!=previous_page)emergency_pages=emergency_pages+1;
   if(emergency && map_mode && !map_ready)$fatal(1,"FAIL: map visible before prelude completion");
   previous_page=page;old_ready=map_ready;
  end
 end
 task load;input [2:0] r;begin
  @(negedge clk);role=r;incoming=1;wait(commit);@(posedge clk);#1;@(negedge clk);incoming=0;
 end endtask
 task next;begin
  @(negedge clk);next_key=0;repeat(12)@(negedge clk);next_key=1;repeat(25)@(negedge clk);
 end endtask
 task reset_control;begin
  @(negedge clk);rst=1;emergency=0;incoming=0;repeat(4)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 end endtask
 initial begin
  reset_control;
  load(2);load(3);load(4);load(5);load(0);load(1);
  if(cached!=63 || !shown || page!=2)$fatal(1,"FAIL: initial six frame cache");
  next;if(page!=3)$fatal(1,"FAIL: 01->02");
  next;if(page!=4)$fatal(1,"FAIL: 02->03");
  next;if(page!=5)$fatal(1,"FAIL: 03->04");
  next;if(page!=2)$fatal(1,"FAIL: 04->01");
  wait(page==3);wait(page==4);wait(page==5);wait(page==2);observed=4;
  @(negedge clk);emergency=1;
  wait(page==0);if(map_ready)$fatal(1,"FAIL: map overtakes 05");
  wait(page==1);if(map_ready)$fatal(1,"FAIL: map overtakes 06");
  wait(map_mode);if(emergency_pages!=2)$fatal(1,"FAIL: emergency prelude did not show both slides");
  repeat(250)@(negedge clk);if(page!=1 || !map_ready)$fatal(1,"FAIL: prelude loops after map");
  emergency=0;repeat(30)@(negedge clk);if(page!=2||map_mode)$fatal(1,"FAIL: restore ordinary page after map");
  emergency=1;wait(page==0);@(negedge clk);emergency=0;repeat(30)@(negedge clk);
  if(page!=2||map_mode)$fatal(1,"FAIL: cancel during 05");
  emergency=1;wait(page==0);wait(page==1);wait(map_mode);emergency=0;repeat(30)@(negedge clk);
  reset_control;load(2);emergency=1;wait(map_mode);if(page!=2)$fatal(1,"FAIL: missing slides disturbed ordinary cache");
  reset_control;load(2);load(1);emergency=1;wait(page==1);wait(map_mode);
  $display("PASS: six distinct cached roles and free staging, manual and automatic 01/02/03/04 carousel, 05->06->map once, restore/cancel/re-entry, missing 05/06 finite fallback");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: sequence timeout page=%d stage=%d map=%b",page,dut.emergency_stage,map_mode);end
endmodule
