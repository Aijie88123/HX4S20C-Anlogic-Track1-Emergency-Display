`timescale 1ns/1ps
module tb_button_carousel_real;
reg period_step=0;reg online=1;reg [1:0] switches=0;wire [7:0] phase;wire [4:0] feedback;wire [1:0] period_ui;
reg clk=0,rst=1,finish_toggle=0,ack=0;
reg key_next=1,key_auto=1,emergency=0;
always #5 clk=~clk;
wire req,en,valid,hard_recover;
wire visual,nearly,autoplay;
wire [31:0] data;
wire [2:0] page;
wire [1:0] wb,db;
wire [3:0] fault;
integer cycles=0,count=0,source_page=0,source_w=640,x,commits=0,errors=0,last_commit=0,load_begin=0;
integer shortest=99999999,longest=0;
reg active=0;
reg [2:0] previous_page=7;
reg [23:0] expected;
integer hold_page,hold_buf,old_commits,ready_cycle,late_start;
reg strict_intervals=1,ordinary_check=1;
distributed_carousel_clock #(.CLK_FREQ_HZ(1000000)) scheduler(.clk(clk),.rst(rst),.switches(switches),.period_step(period_step),
 .online(online),.feedback(feedback),.actual_emergency(emergency),.phase(phase));
sd_card_bmp #(.SD_POWERUP_WAIT_MS(0),.CLK_FREQ_HZ(1000000),.REMOTE_SCHEDULE(1)) dut(
 .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.emergency(emergency),.remote_phase({online,phase}),.carousel_feedback(feedback),.interval_selection(period_ui),
 .brightness_step_toggle(),.contrast_step_toggle(),.page_index_out(page),.state_code(),
 .load_fault(fault),.load_fault_recurring(),.hard_recover(hard_recover),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),
 .disp_src_w(),.disp_src_h(),.disp_src_toggle(),.load_nearly_done(nearly),.load_visual_active(visual),
 .write_finish_toggle(finish_toggle),.auto_play_en_out(autoplay),.write_buf_idx(wb),.disp_buf_idx(db),
 .write_req(req),.write_req_ack(ack),.write_en(en),.write_data(data),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
always @(posedge clk)begin
 if(rst)begin ack<=0;count=0;active=0;end
 else begin
  ack<=req;
  if(dut.load_start_pulse)load_begin=cycles;
  if(req&&!ack)begin
   count=0;active=1;source_page=dut.load_idx;
   source_w=(source_page==3)?427:((source_page==4)?1280:640);
  end
  if(active&&en)begin
   x=((count%640)*source_w)/640;
   expected={source_page[7:0],x[7:0],(x[7:0]^source_page[7:0])};
   if(data[31:8]!==expected)begin
    if(errors<3)$display("FAIL: uniform page=%0d pixel=%0d got=%h expected=%h",source_page,count,data[31:8],expected);
    errors=errors+1;
   end
   count=count+1;
   if(count==307200)begin
    finish_toggle<=~finish_toggle;active=0;
    if(source_page>=2)begin
     if(cycles-load_begin<shortest)shortest=cycles-load_begin;
     if(cycles-load_begin>longest)longest=cycles-load_begin;
     $display("TRACE: page=%0d actual load cycles=%0d",source_page,cycles-load_begin);
    end
   end
  end
 end
 #1;cycles=cycles+1;
 if(!rst)begin
  if(hard_recover||fault!=0)begin $display("FAIL: healthy prefetch triggered recovery fault=%0d",fault);$fatal(1);end
  if(dut.normal_prefetch && autoplay && !emergency)begin
   if(nearly && (!dut.load_frame_ready || !(online?phase[1]:dut.auto_cnt>=2840)))begin
    $display("FAIL: fade intent before complete frame and fade deadline");$fatal(1);
   end
   // Registered visual intent follows the readiness/deadline by one clock.
   if(visual && (!dut.load_frame_ready || !(online?phase[1]:dut.auto_cnt>=2840)))begin
    $display("FAIL: background prefetch darkened the display");$fatal(1);
   end
  end
  if(ordinary_check&&valid&&page!=previous_page)begin
   if(page<2||count!=307200)begin $display("FAIL: alarm/partial frame in ordinary carousel");errors=errors+1;end
   if(strict_intervals && commits>0 && (cycles-last_commit<((period_ui==1?5000000:period_ui==2?10000000:3000000)-1100) || cycles-last_commit>((period_ui==1?5000000:period_ui==2?10000000:3000000)+1100)))begin
    $display("FAIL: unequal visible interval page=%0d cycles=%0d expected 3000000",page,cycles-last_commit);errors=errors+1;
   end
   $display("TRACE: visible page=%0d interval=%0d",page,cycles-last_commit);
   previous_page=page;last_commit=cycles;commits=commits+1;
  end
 end
end
task check_ok;input ok;input [1023:0] message;
 begin if(!ok)begin $display("FAIL: %0s",message);$fatal(1);end end
endtask
task select_period;input [1:0] selection;input integer seconds;integer target;
 begin
  strict_intervals=0;@(negedge clk);period_step=1;@(negedge clk);period_step=0;
  wait(period_ui==selection);target=commits+1;wait(commits>=target);@(negedge clk);
  strict_intervals=1;target=commits+1;wait(commits>=target);@(negedge clk);
  check_ok(errors==0,"distributed interval or frame pixels incorrect");
  $display("PASS: B S2-selected timer %0ds controls actual A FAT/BMP/scaler and complete 307200-pixel commits",seconds);
 end
endtask
initial begin repeat(110000000)@(negedge clk);$fatal(1,"distributed carousel timeout");end
initial begin
 repeat(6)@(negedge clk);rst=0;wait(commits>=2);@(negedge clk);
 check_ok(errors==0,"default B carousel failed");
 select_period(1,5);select_period(2,10);select_period(0,3);
 strict_intervals=0;
 // Disconnect retains the ordinary full frame and restarts the 3 s fallback.
 online=0;old_commits=commits;late_start=cycles;
 wait(commits>old_commits);@(negedge clk);
 check_ok(cycles-late_start>=2998900 && cycles-late_start<=3001100,"A standalone fallback deadline");
 $display("PASS: network loss restarts local 3s carousel without partial buffer selection");
 online=1;wait(scheduler.active);wait(dut.load_frame_ready);@(negedge clk);
 key_auto=0;repeat(25000)@(negedge clk);key_auto=1;repeat(25000)@(negedge clk);
 check_ok(!autoplay,"S3 pause lost");hold_page=page;old_commits=commits;
 repeat(1200000)@(negedge clk);
 check_ok(page==hold_page && commits==old_commits && !visual && !phase[5],"B ignored A pause");
 key_auto=0;repeat(25000)@(negedge clk);key_auto=1;wait(autoplay);@(negedge clk);
 late_start=cycles;wait(commits>old_commits);@(negedge clk);
 check_ok(cycles-late_start>=2998900 && cycles-late_start<=3001100,"B resume full dwell");
 $display("PASS: A S3 pause/resume reaches B, holds the full prefetched buffer and resumes a fresh dwell");
 // TF read that runs beyond its deadline must keep the old frame and allow
 // the full 160 ms fade after real completion, rather than commit immediately.
 dut.sd_card_top_m0.spi_master_m0.slow_page4=1;
 wait(page==3);@(negedge clk);old_commits=commits;hold_buf=db;
 wait(scheduler.elapsed==2839);repeat(400000)@(negedge clk);
 check_ok(!dut.load_frame_ready && !visual && !phase[1] && db==hold_buf,"late TF started fade early");
 wait(dut.load_frame_ready);@(negedge clk);ready_cycle=cycles;
 wait(commits>old_commits);@(negedge clk);
 $display("TRACE: slow completion page=%0d commits=%0d old=%0d ready=%0d current=%0d delta=%0d elapsed=%0d",page,commits,old_commits,ready_cycle,cycles,cycles-ready_cycle,scheduler.elapsed);
 check_ok(page==4 && cycles-ready_cycle>=159000 && cycles-ready_cycle<=162100,"late TF shortened full fade");
 $display("PASS: B waits for actual A prefetch completion and preserves 160ms fade for slow TF");
 dut.sd_card_top_m0.spi_master_m0.slow_page4=0;
 // Old completed deadline for the previous epoch cannot release the new page.
 force dut.remote_phase={1'b1,2'b0,1'b1,2'b0,1'b1,1'b1,!dut.disp_src_toggle};
 old_commits=commits;repeat(200000)@(negedge clk);
 check_ok(commits==old_commits && !nearly && !visual,"stale epoch accepted");release dut.remote_phase;
 ordinary_check=0;emergency=1;repeat(5)@(negedge clk);
 check_ok(page==0 && db==2,"local emergency lost cached preemption");
 check_ok(errors==0,"frame data errors");
 $display("PASS: stale/duplicated prior-frame phases rejected and cached local emergency remains highest priority");$finish;
end
endmodule
