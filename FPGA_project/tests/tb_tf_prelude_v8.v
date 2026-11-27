`timescale 1ns/1ps
module tb_tf_prelude_v8;
 reg clk=0,net=0,rst=1,emergency=0,vs=0,incoming=0,next_key=1;
 always #5 clk=~clk;always #20 net=~net;
 integer ticks=0;always @(negedge clk)begin ticks=ticks+1;vs=ticks%10==0;end
 reg [2:0] role=0;wire commit,shown,ready;wire [2:0] page;wire [4:0] feedback;wire [5:0] valid;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(2),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1)) dut(
  .clk(clk),.rst(rst),.key_next(next_key),.key_auto(1'b1),.emergency(emergency),.vsync(vs),.remote_phase(9'd0),
  .incoming_complete(incoming),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(commit),
  .staging_slot(),.display_slot(),.display_valid(shown),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(valid),.state_code(),.emergency_map_ready(ready));
 wire [5:0] transferred_feedback;
 ethernet_mailbox #(.WIDTH(6)) feedback_cdc(.src_clk(clk),.src_rst(rst),.src_valid(1'b1),.src_data({ready,feedback}),.src_ready(),
  .dst_clk(net),.dst_rst(rst),.dst_valid(),.dst_data(transferred_feedback));
 wire busy,received;wire [3:0] nibble;wire [7:0] b_feedback;wire [20:0] b_message;
 reg [4:0] gap=0;wire send=!rst&&!busy&&gap==0;
 always @(posedge net)if(rst)gap<=0;else if(busy)gap<=24;else if(gap!=0)gap<=gap-1'b1;
 ethernet_frame_tx #(.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) tx(
  .clk(net),.rst(rst),.start(send),.message({18'd0,2'd0,emergency}),.extension({2'd0,transferred_feedback}),.stream_data(224'd0),.busy(busy),.nibble(nibble));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) rx(
  .clk(net),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(received),.message(b_message),.extension(b_feedback),.stream_data());
 wire b_render_enabled=b_message[0]&&b_feedback[5];
 integer previous_page=7,displayed05=0,displayed06=0,cycle05=0,cycle06=0,ready_frames=0;
 always @(posedge clk)begin #1;
  if(!rst && emergency)begin
   if(shown&&page==0&&previous_page!=0)begin displayed05=displayed05+1;cycle05=ticks;end
   if(shown&&page==1&&previous_page!=1)begin
    if(!displayed05||ticks-cycle05<2000)$fatal(1,"FAIL: 06 overtakes complete 05 dwell");
    displayed06=displayed06+1;cycle06=ticks;
   end
   if(ready && (!displayed05 || !displayed06 || ticks-cycle06<2000))$fatal(1,"FAIL: map bypassed actual two slides");
  end
  previous_page=page;
 end
 always @(posedge net)if(received&&b_feedback[5])ready_frames=ready_frames+1;
 task load;input [2:0] r;begin
  @(negedge clk);role=r;incoming=1;wait(commit);@(posedge clk);#1;@(negedge clk);incoming=0;
 end endtask
 initial begin
  repeat(12)@(negedge clk);rst=0;
  load(4);load(5);repeat(50)@(negedge clk);if(shown)$fatal(1,"FAIL: boot skips missing 01");
  load(2);repeat(30)@(negedge clk);if(page!=2||!shown)$fatal(1,"FAIL: first ordinary image is not 01");
  next_key=0;repeat(12)@(negedge clk);next_key=1;repeat(5000)@(negedge clk);
  if(page!=2)$fatal(1,"FAIL: ordinary carousel skips missing 02");
  load(3);repeat(50)@(negedge clk);if(page!=3)$fatal(1,"FAIL: queued next did not show 02");
  emergency=1;repeat(15000)@(negedge clk);
  if(ready||b_render_enabled||displayed05||displayed06)$fatal(1,"FAIL: 5-second timeout bypasses prelude");
  load(1);repeat(7000)@(negedge clk);
  if(ready||b_render_enabled||displayed06)$fatal(1,"FAIL: early 06 skips missing 05");
  load(0);wait(page==0);wait(page==1);wait(ready);wait(b_render_enabled);repeat(2)@(negedge net);
  if(displayed05!=1||displayed06!=1||!ready_frames)$fatal(1,"FAIL: v8 prelude status did not reach B");
  repeat(2500)@(negedge clk);if(page!=1)$fatal(1,"FAIL: prelude loops after map stage");
  emergency=0;repeat(2000)@(negedge clk);if(page<2||b_render_enabled)$fatal(1,"FAIL: return or render gate not cleared");
  $display("PASS: strict 01/02/03/04 ordering and queued manual selection, missing 05 beyond15s, 06 arrives7s early, actual 05 then06 2s dwell, protocol-v8 real CRC/IFG/CDC delivers ready bit5 to B, no premature map and normal restore");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: prelude timeout page=%d stage=%d ready=%b bflag=%h",page,dut.emergency_stage,ready,b_feedback);end
endmodule
