`timescale 1ns/1ps
module tb_named_media_chain #(parameter MISSING_TWO=0,parameter FAULT_CHECK=0);
 reg clk=0,rst=1,finish_toggle=0,ack=0,emergency=0;
 always #5 clk=~clk;
 wire req,en,valid,hard_recover;wire [31:0] data;wire [2:0] page;
 wire [1:0] wb,db;wire [3:0] fault;wire [15:0] src_w,src_h;
 sd_card_bmp #(.RELIABLE_MEDIA(1),.SD_POWERUP_WAIT_MS(0),.CLK_FREQ_HZ(1000000)) dut(
  .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.emergency(emergency),.remote_phase(9'd0),
  .carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),
  .page_index_out(page),.state_code(),.load_fault(fault),.load_fault_recurring(),.hard_recover(hard_recover),
  .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),
  .disp_src_w(src_w),.disp_src_h(src_h),.disp_src_toggle(),.load_nearly_done(),.load_visual_active(),
  .write_finish_toggle(finish_toggle),.auto_play_en_out(),.write_buf_idx(wb),.disp_buf_idx(db),
  .write_req(req),.write_req_ack(ack),.write_en(en),.write_data(data),.disp_audio_emergency(),
  .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
 integer red_value,blue_value;reg fault_injecting=0;reg [2:0] retained_page;reg [1:0] retained_buffer;integer fault_wait;
 integer pixels=0,item=0,width=640,x,commits=0,cycles=0;reg writer_active=0;reg [2:0] previous=7;
 reg [23:0] expected;reg [4:0] ordinary_seen=0;
 always @(posedge clk)begin
  if(rst)begin ack<=0;writer_active=0;pixels=0;end
  else begin
   ack<=req;
   if(req&&!ack)begin writer_active=1;pixels=0;item=dut.load_idx;width=item==3?800:item==4?1280:640;end
   if(writer_active && en)begin
    x=(pixels%640)*width/640;
    red_value=(x^item)&255;blue_value=(x+item)&255;
    if(width>640 && x!=0)begin red_value=(((x^item)&255)+(((x-1)^item)&255)+1)/2;blue_value=(((x+item)&255)+((x-1+item)&255)+1)/2;end
    expected={8'(red_value),8'd0,8'(blue_value)};
    if(data[31:8]!==expected)$fatal(1,"named media scaler RGB mismatch slot=%0d pixel=%0d actual=%h expected=%h",item,pixels,data[31:8],expected);
    pixels=pixels+1;
    if(pixels==307200)begin finish_toggle<=!finish_toggle;writer_active=0;end
   end
  end
  #1;cycles=cycles+1;
  if(!rst && !fault_injecting && (hard_recover || fault!=0))$fatal(1,"healthy named media triggered recovery");
  if(valid && page!=previous)begin
   if(!emergency && page<2)$fatal(1,"alarm resource displayed in normal mode");
   if(!emergency)ordinary_seen[page]=1;
   previous=page;commits=commits+1;
  end
 end
 initial begin
  dut.sd_card_top_m0.spi_master_m0.missing_slot2=MISSING_TWO;
  repeat(5)@(negedge clk);rst=0;
  wait(ordinary_seen[4:2]==(MISSING_TWO?3'b110:3'b111));@(negedge clk);
  if(dut.img_slots!=(MISSING_TWO?5'b11011:5'b11111) || dut.img_found_count!=5 || src_h!=1)$fatal(1,"named resources or source OSD mismatch");
  wait(dut.alarm_cache_ready);emergency=1;
  repeat(8)@(negedge clk);
  if(page!=0 || db!=2 || !valid)$fatal(1,"named alarm cache did not preempt immediately");
  wait(page==1);@(negedge clk);
  if(src_w!=640 || src_h!=1)$fatal(1,"named evacuation resource mismatch");
  emergency=0;repeat(8)@(negedge clk);
  if(page<2 || !valid)$fatal(1,"emergency return lost complete ordinary cache");
  if(FAULT_CHECK)begin
   wait(dut.load_busy && !dut.source_done_seen);@(negedge clk);
   retained_page=page;retained_buffer=db;fault_injecting=1;
   dut.sd_card_top_m0.spi_master_m0.pause_transport=1;
   fault_wait=0;
   while(fault==0 && fault_wait<2000000)begin @(negedge clk);fault_wait=fault_wait+1;end
   if(fault==0 || !valid || page!=retained_page || db!=retained_buffer)
    $fatal(1,"production registered watchdog failed to retain the last complete frame");
   $display("PASS: production reliable-media scheduler stalls actual SPI during an incomplete load; registered watchdog reports fault while retaining the previous complete displayed buffer and page");$finish;
  end
  $display("PASS: production named-role scheduler, available-slot rotation including missing first ordinary file, with real SPI command/FAT/BMP/scaler chain; shuffled three-cluster directory, fragmented files, ordinary 2/3/4 cycle, all 307200 RGB pixels per frame with independent horizontal reduction-filter expectations, source metadata, instant named alarm cache, named evacuation and complete ordinary return");$finish;
 end
 initial begin #250000000;$fatal(1,"named media chain timeout page=%0d found=%0d state=%0d commits=%0d",page,dut.img_found_count,dut.bmp_read_m0.state,commits);end
endmodule
