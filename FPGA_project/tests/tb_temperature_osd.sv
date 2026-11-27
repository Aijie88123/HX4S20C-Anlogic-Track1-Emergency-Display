`timescale 1ns/1ps
module tb_temperature_osd;
 reg nc=0,vc=0,rst=1,online=0,ready=1,deliver=1,inject=0,emergency=0;
 always #20 nc=~nc;
 always #6.666 vc=~vc;
 reg [23:0] sensor=24'hc00163;
 wire txv;wire [223:0] txd;reg [223:0] injected=0,last_packet=0;
 wire rv=inject||(deliver&&txv&&ready);wire [223:0] packet=inject?injected:txd;
 wire live,scene_valid,t_live;wire [223:0] scene;wire [23:0] t_data;
 b_map_control_sender #(.UPDATE_CYCLES(23),.ENABLE_TEMPERATURE(1)) sender(
  .clk(nc),.rst(rst),.online(online),.actual_state(3'd0),.switches(2'd0),.barrier_mode(2'd0),
  .temperature_status(sensor),.stream_ready(ready),.stream_valid(txv),.stream_data(txd));
 a_map_scene_compute #(.ENABLE_TEMPERATURE(1),.TIMEOUT_CYCLES(512),.FRAME_CYCLES(101),.DEBOUNCE_MS(0)) receiver(
  .clk(nc),.rst(rst),.online(online),.actual_state(3'd0),.packet_valid(rv),.packet(packet),
  .controls_live(live),.scene_valid(scene_valid),.scene(scene),.temperature_live(t_live),.temperature_status(t_data));
 wire [24:0] video;
 ethernet_mailbox #(.WIDTH(25)) cdc(.src_clk(nc),.src_rst(rst),.src_valid(1'b1),.src_data({t_live,t_data}),.src_ready(),
   .dst_clk(vc),.dst_rst(rst),.dst_valid(),.dst_data(video));
 reg [11:0] xp=200,yp=80;wire [23:0] rgb,old_rgb;wire [7:0] alpha,old_alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1),.ENABLE_TEMPERATURE_OSD(1)) dut(
  .clk(vc),.rst(rst),.temperature_status(video),.emergency(emergency),.custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),
  .startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),.x(xp),.y(yp),.x_pre(xp),.y_pre(yp),
  .page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'hf),.res_str(" 640X 480"),
  .text_rgb(rgb),.text_alpha(alpha));
 temperature_parent_text #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1)) parent(
  .clk(vc),.rst(rst),.emergency(emergency),.custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),
  .startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),.x(xp),.y(yp),.x_pre(xp),.y_pre(yp),
  .page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'hf),.res_str(" 640X 480"),
  .text_rgb(old_rgb),.text_alpha(old_alpha));
 integer cases=0,pixels=0,outside=0,i,j,n,raw,v,fraction,ix,iy,fd,wait_count;
 string expected,state_expected;reg [23:0] expected_colour;reg [223:0] held;
 always @(posedge nc)if(!rst&&deliver&&txv&&ready)last_packet<=txd;
 task pixel(input integer x,y);
  begin @(negedge vc);xp=x;yp=y;@(posedge vc);#1;end
 endtask
 task snapshot;
  begin pixel(0,0);for(integer k=1;k<10;k=k+1)pixel(k,0);pixel(200,80);end
 endtask
 task settle;
  begin
   wait_count=0;
   while(video!=={1'b1,sensor})begin @(posedge vc);#1;wait_count=wait_count+1;if(wait_count>5000)$fatal(1,"telemetry delivery timeout sensor=%h got=%h",sensor,video);end
   snapshot();
  end
 endtask
 task check_chars(input string want,input string state_want);
  begin
   if(want.len()!=16)$fatal(1,"bad independent expected length %0d %s",want.len(),want);
   for(integer k=0;k<16;k=k+1)if(dut.temperature_char(k)!==want[k])$fatal(1,"format raw=%h char=%0d got=%h want=%h %s",sensor,k,dut.temperature_char(k),want[k],want);
   for(integer k=0;k<2;k=k+1)if(dut.temperature_state_char(k)!==state_want[k])$fatal(1,"state %0d got=%h want=%h",k,dut.temperature_state_char(k),state_want[k]);
   cases=cases+1;
  end
 endtask
 task check_pixel(input integer x,y);
  reg ink,bar;reg [7:0] ch,glyph;integer col,row;
  begin
   pixel(x,y);ink=0;bar=x>=20&&x<284&&y>=16&&y<38;
   if(x>=24&&x<280&&(y>=18&&y<34))begin
    col=(x-24)/16;row=(y-18)/2;
    ch=expected[col];
    glyph=ch=="K"?(row==0?8'h42:row==1?8'h44:row==2?8'h48:row==3?8'h70:row==4?8'h48:row==5?8'h44:row==6?8'h42:8'h00):ch=="-"?(row==3?8'h7e:8'd0):parent.font_row(ch,row);
    ink=glyph[7-(((x-24)%16)/2)];
   end
   if(bar)begin
    if(rgb!==(ink?expected_colour:(emergency?24'hb00000:24'h12385a)) || alpha!==(ink?8'd255:(emergency?8'd220:8'd180)))
     $fatal(1,"pixel x=%0d y=%0d got=%h/%0d ink=%0d",x,y,rgb,alpha,ink);
   end else if(x>=20&&x<140&&y>=14&&y<42)begin
    if(rgb!==0||alpha!==0)$fatal(1,"removed clock left pixels at %0d,%0d",x,y);
   end else begin
    if(rgb!==old_rgb||alpha!==old_alpha)$fatal(1,"outside temperature changed x=%0d y=%0d got=%h/%0d old=%h/%0d",x,y,rgb,alpha,old_rgb,old_alpha);
    outside=outside+1;
   end
   pixels=pixels+1;
  end
 endtask
 task scan_header(input string filename);
  begin
   fd=$fopen(filename,"w");
   for(integer y=0;y<76;y=y+1)for(integer x=0;x<320;x=x+1)begin
    // Do not synthesize another frame-start while sweeping a captured frame.
    if(x==0&&y==0)begin pixel(1,0);end else check_pixel(x,y);
    $fdisplay(fd,"%06x %02x",rgb,alpha);
   end
   $fclose(fd);
  end
 endtask
 task manual_packet(input [223:0] p);
  begin @(negedge nc);injected=p;inject=1;@(negedge nc);inject=0;end
 endtask
 initial begin
  repeat(8)@(posedge nc);@(negedge nc);rst=0;online=1;settle();
  expected="TEMP   22.19C OK";state_expected="OK";expected_colour=24'h70ffd0;
  check_chars(expected,state_expected);scan_header("normal_pixels.txt");
  // Every representable sensor raw value in the specified -55..125C range.
  for(raw=-880;raw<=2000;raw=raw+1)begin
   @(negedge nc);sensor={8'hc0,raw[15:0]};settle();v=raw<0?-raw:raw;
   fraction=((v%16)*625+50)/100;
   expected=$sformatf("TEMP %s%3d.%0d%0dC OK",raw<0?"-":" ",v/16,fraction/10,fraction%10);
   check_chars(expected,"OK");
  end
  @(negedge nc);sensor=24'he002d0;settle();expected="TEMP   45.00C HI";state_expected="HI";expected_colour=24'hffca48;
  check_chars(expected,state_expected);scan_header("warning_pixels.txt");
  sensor=24'hf00370;settle();expected="TEMP   55.00C AL";state_expected="AL";expected_colour=24'hff5656;
  emergency=1;check_chars(expected,state_expected);scan_header("alarm_pixels.txt");emergency=0;
  sensor=24'h930370;settle();expected="TEMP ----.--C A3";state_expected="A3";expected_colour=24'hff5656;
  check_chars(expected,state_expected);scan_header("alarm_fault_pixels.txt");
  sensor=24'h83ff5e;settle();expected="TEMP ----.--C E3";state_expected="E3";expected_colour=24'hffe0a0;
  check_chars(expected,state_expected);scan_header("crc_pixels.txt");
  sensor=24'h81ff5e;settle();check_chars("TEMP ----.--C E1","E1");
  sensor=24'hc00163;settle();expected="TEMP   22.19C OK";state_expected="OK";expected_colour=24'h70ffd0;
  // A changed bundle between frame starts cannot tear the existing digits.
  sensor=24'hc0ff5e;wait(video=={1'b1,sensor});repeat(30)@(posedge vc);
  check_chars(expected,state_expected);snapshot();expected="TEMP - 10.13C OK";check_chars(expected,state_expected);scan_header("negative_pixels.txt");
  // Backpressured packets remain immutable even while the probe value changes.
  @(negedge nc);ready=0;wait(txv);held=txd;sensor=24'hc001e0;
  repeat(20)begin @(posedge nc);#1;if(txd!==held||!txv)$fatal(1,"backpressure changed packet");end
  @(negedge nc);ready=1;settle();
  // Duplicates with altered payload must neither replace the sample nor keep
  // it fresh. Malformed extension marker/range/reserved bits are rejected.
  @(negedge nc);deliver=0;held=last_packet;
  injected=held;injected[49:34]=16'd2000;manual_packet(injected);repeat(4)@(posedge nc);
  if(t_data!==sensor)$fatal(1,"duplicate overwrote temperature");
  injected=held;injected[33:18]=held[33:18]+1'b1;injected[73:58]=16'h5402;manual_packet(injected);
  injected=held;injected[33:18]=held[33:18]+1'b1;injected[187]=1;manual_packet(injected);
  injected=held;injected[33:18]=held[33:18]+1'b1;injected[49:34]=16'd2001;manual_packet(injected);
  repeat(4)@(posedge nc);if(t_data!==sensor)$fatal(1,"malformed telemetry accepted");
  for(n=0;n<60;n=n+1)begin manual_packet(held);repeat(10)@(posedge nc);end
  if(t_live)$fatal(1,"replayed sequence kept temperature fresh");
  wait(!video[24]);snapshot();check_chars("TEMP ----.--C --","--");
  @(negedge nc);deliver=1;settle();
  @(negedge nc);online=0;wait(!video[24]);snapshot();expected="TEMP ----.--C --";state_expected="--";expected_colour=24'hffe0a0;
  check_chars(expected,state_expected);scan_header("offline_pixels.txt");
  // Legacy route control remains usable, while absent telemetry stays unknown.
  @(negedge nc);online=1;deliver=0;held={36'h4d4150431,154'd0,16'hffff,2'd0,2'd0,2'd0,2'd0,1'b0,1'b0,8'd3};
  manual_packet(held);repeat(5)@(posedge nc);if(!live||t_live)$fatal(1,"legacy compatibility failed");
  held[73:58]=16'h5401;held[57:34]=24'hc00163;held[33:18]=0;manual_packet(held);
  repeat(5)@(posedge nc);if(!t_live||t_data!==24'hc00163)$fatal(1,"sequence wrap failed");
  $display("PASS: %0d sensor/format/state cases; all2881 signed raw temperatures; %0d pixel comparisons including %0d unchanged outside clock/temperature union; 16x16 temperature glyphs and expanded background; removed clock area transparent; actual sender/receiver/mailbox/native font; frame atomicity, backpressure, faults, duplicate/malformed/timeout/reconnect/legacy/wrap",cases,pixels,outside);
  $finish;
 end
 initial begin #(64'd200000000);$fatal(1,"watchdog");end
endmodule
