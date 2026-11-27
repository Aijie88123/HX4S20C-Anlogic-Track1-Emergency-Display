`timescale 1ns/1ps
module tb_frame_counter #(parameter FAST=1,JITTER=0);
 localparam MODE=0;reg seen_complete=0;
 reg loading=0,load_start=0,load_abort=0,release_stall=0;wire[3:0] error_code;wire complete;integer pixel_count=0;wire pixel_valid;
 reg clk=0,rst=1,scan_start=0,valid=0,last=0;reg [7:0] value=0;
 always #10 clk=~clk;always @(posedge clk)if(complete)seen_complete=1;
 wire request,ready,scan_done,found;wire [31:0] lba,handle;wire [2:0] role,total;wire [15:0] width,height;
 bmp_read #(.CLK_FREQ_HZ(1000000),.RELIABLE_MEDIA(1),.NUMBERED_SIX(1)) dut(
  .clk(clk),.rst(rst),.ready(ready),.load_nearly_done(),.scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'hffffffff),.scan_target_count(3'd6),
  .scan_done(scan_done),.scan_error_code(error_code),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_slot(role),.scan_found_total(total),
  .load_start(load_start),.load_abort(load_abort),.load_complete(complete),.load_sector(32'd810),.sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
  .src_w(width),.src_h(height),.pixel_start(),.write_req(),.write_req_ack(1'b1),.sd_sec_read(request),.sd_sec_read_addr(lba),
  .sd_sec_read_data(value),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last),.bmp_data_wr_en(pixel_valid),.bmp_data());
 reg [31:0] keys[0:11875];reg [7:0] bytes[0:6080511];integer fd,n;
 initial begin
  $readmemh("real_card_vectors/lbas.hex",keys);
  fd=$fopen("real_card_vectors/sectors.bin","rb");n=$fread(bytes,fd);$fclose(fd);if(n!=6080512)$fatal(1,"FAIL: sparse real card bytes=%d",n);
 end
 function integer lookup(input [31:0] address);
  integer lo,hi,mid;
  begin lo=0;hi=11875;lookup=-1;
   while(lo<=hi)begin mid=(lo+hi)/2;if(keys[mid]==address)begin lookup=mid;lo=hi+1;end else if(keys[mid]<address)lo=mid+1;else hi=mid-1;end
  end
 endfunction
 integer stage=0,index=0,phase=0,sector_index=0,reads=0,byte_period=32;reg [31:0] active_lba;reg [5:0] mask=0;
 always @(posedge clk)begin
  valid<=0;last<=0;
  if(!rst)case(stage)
   0:if(request)begin
    active_lba=lba;sector_index=lookup(lba);if(sector_index<0)$fatal(1,"FAIL: uncaptured LBA=%d state=%d",lba,dut.state);
    index=0;phase=0;stage=1;reads=reads+1;
   end
   1:if(!(loading&&MODE==4&&!release_stall))begin
    if(phase==0)begin byte_period=(loading&&FAST&&width>=320&&height>=240)?8:32; if(JITTER && loading)byte_period=byte_period+(index%5)*3;end
    if(phase==3)begin
     value<=bytes[sector_index*512+index];valid<=1;
     if(loading&&MODE==1&&dut.state==2&&index==0)value<=0;
     if(loading&&(MODE==2||MODE==3)&&dut.state==13&&index>=168&&index<172)begin
      if(MODE==2)value<=0;
      else case(index)168:value<=8'h2a;169:value<=8'h03;default:value<=0;endcase
     end
    end
    if(index==511&&phase==4)begin last<=1;stage=2;end
    else if(phase==byte_period-1)begin phase=0;index=index+1;end else phase=phase+1;
   end
   2:if(!request)stage=0;
  endcase
  if(loading&&pixel_valid)pixel_count=pixel_count+1;
  if(!rst&&found)begin mask[role]=1;$display("TRACE found role=%0d cluster=%0d full header file_len=%0d directory_size=%0d",role,handle,dut.file_len,dut.chk_size);end
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;repeat(8)@(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);repeat(4)@(negedge clk);
  if(mask!=63)$fatal(1,"FAIL load stage did not discover real files");
  loading=1;load_start=1;@(negedge clk);load_start=0;
  wait(!ready);if(MODE==4)begin wait(error_code==3);release_stall=1;end wait(ready);repeat(4)@(negedge clk);
  if(!seen_complete || error_code!=0 || pixel_count!=307200)$fatal(1,"FAIL C guard FAST=%d JITTER=%d code=%d pixels=%d filebytes=%d row=%d rowbyte=%d rem=%d",FAST,JITTER,error_code,pixel_count,dut.bmp_len_cnt,dut.row_cnt,dut.row_byte,dut.sectors_remaining);
  if(dut.bmp_len_cnt!=922112 || dut.row_cnt!=479 || !dut.data_done)$fatal(1,"frame counters unexpectedly reset after complete load bytes=%d rows=%d",dut.bmp_len_cnt,dut.row_cnt);
  $display("PASS: full real01 all307200 pixels complete FAST=%d JITTER=%d",FAST,JITTER);$finish;
 end
 initial begin #2000000000;$fatal(1,"FAIL real card scan timeout state=%d reads=%d",dut.state,reads);end
endmodule
