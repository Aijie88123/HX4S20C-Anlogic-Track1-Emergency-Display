`timescale 1ns/1ps
module tb_real_card_diagnostics #(parameter MODE=1);
 localparam FAST=0;reg inject=1;wire [3:0] error_code;
 reg clk=0,rst=1,scan_start=0,valid=0,last=0;reg [7:0] value=0;
 always #10 clk=~clk;
 wire request,ready,scan_done,found;wire [31:0] lba,handle;wire [2:0] role,total;wire [15:0] width,height;
 bmp_read #(.CLK_FREQ_HZ(50000000),.RELIABLE_MEDIA(1),.NUMBERED_SIX(1)) dut(
  .clk(clk),.rst(rst),.ready(ready),.load_nearly_done(),.scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'hffffffff),.scan_target_count(3'd6),
  .scan_done(scan_done),.scan_error_code(error_code),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_slot(role),.scan_found_total(total),
  .load_start(1'b0),.load_abort(1'b0),.load_complete(),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
  .src_w(width),.src_h(height),.pixel_start(),.write_req(),.write_req_ack(1'b1),.sd_sec_read(request),.sd_sec_read_addr(lba),
  .sd_sec_read_data(value),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last),.bmp_data_wr_en(),.bmp_data());
 reg [31:0] keys[0:11872];reg [7:0] bytes[0:6078975];integer fd,n;
 initial begin
  $readmemh("real_card_vectors/lbas.hex",keys);
  fd=$fopen("real_card_vectors/sectors.bin","rb");n=$fread(bytes,fd);$fclose(fd);if(n!=6078976)$fatal(1,"FAIL: sparse real card bytes=%d",n);
 end
 function integer lookup(input [31:0] address);
  integer lo,hi,mid;
  begin lo=0;hi=11872;lookup=-1;
   while(lo<=hi)begin mid=(lo+hi)/2;if(keys[mid]==address)begin lookup=mid;lo=hi+1;end else if(keys[mid]<address)lo=mid+1;else hi=mid-1;end
  end
 endfunction
 integer stage=0,index=0,phase=0,sector_index=0,reads=0,byte_period=32;reg [31:0] active_lba;reg [5:0] mask=0;
 always @(posedge clk)begin
  valid<=0;last<=0;
  if(!rst)case(stage)
   0:if(request)begin
    active_lba=lba;sector_index=lookup(lba);if(sector_index<0)$fatal(1,"FAIL: uncaptured LBA=%d state=%d",lba,dut.state);
    $display("TRACE real card read LBA=%0d parser=%0d resume=%0d",lba,dut.state,dut.resume_entry);
    index=0;phase=0;stage=1;reads=reads+1;
   end
   1:begin
    if(phase==0)byte_period=(FAST&&width>=320&&height>=240)?8:32;
    if(phase==3)begin value<=bytes[sector_index*512+index];valid<=1;
     if(inject)begin
      if(MODE==1&&active_lba==2048&&index==13)value<=0;
      if(MODE==2&&dut.state==10&&index==0)value<=0;
      if(MODE==3&&((active_lba==34816&&(index==9*32||index==10*32||index==14*32||index==15*32))||(active_lba==34817&&(index==7*32||index==8*32))))value<=8'h58;
     end end
    if((index==511||(inject&&MODE==4&&index==100))&&phase==4)begin last<=1;stage=2;end
    else if(phase==byte_period-1)begin phase=0;index=index+1;end else phase=phase+1;
   end
   2:if(!request)stage=0;
  endcase
  if(!rst&&found)begin mask[role]=1;$display("TRACE found role=%0d cluster=%0d full header file_len=%0d directory_size=%0d",role,handle,dut.file_len,dut.chk_size);end
  if(!rst&&dut.state==10&&last)$display("TRACE header end: match=%b read_fail=%b file=%0d directory=%0d w=%0d h=%0d",dut.header_ok_r,dut.read_fail,dut.file_len,dut.chk_size,width,height);
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;repeat(8)@(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);repeat(4)@(negedge clk);
  if(mask!=0||error_code!=(MODE==1?6:MODE==2?8:MODE==4?9:0))$fatal(1,"FAIL fault specificity MODE=%d mask=%b code=%d",MODE,mask,error_code);
  $display("TRACE stage fault MODE=%0d code=%0d (empty directory maps to storage fault7)",MODE,error_code);
  inject=0;mask=0;repeat(8)@(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
  wait(!scan_done);wait(scan_done);repeat(4)@(negedge clk);
  if(mask!=63||error_code!=0)$fatal(1,"FAIL diagnostic recovery MODE=%d mask=%b code=%d",MODE,mask,error_code);
  $display("PASS: MODE=%0d stage-specific error and clean retry discovers all six actual-card headers",MODE);$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL real card scan timeout state=%d reads=%d",dut.state,reads);end
endmodule
