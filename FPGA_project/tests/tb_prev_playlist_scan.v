`timescale 1ns/1ps
module tb_prev_playlist_scan;
reg clk=0,rst=1,start=0,valid=0,ending=0;
always #5 clk=~clk;
reg [7:0] data=0;
wire req,done,found,ready;
wire [31:0] addr,found_lba;
wire [3:0] total;wire [2:0] slot;
reg [31:0] lbas[0:255],expected[0:7];
reg [7:0] bytes[0:131071];
reg [7:0] seen=0;
integer sectors,expected_count,i,k,selected,position=-1,wait_count=0,found_count=0,requests=0;
reg [1023:0] vector_path;
bmp_read #(.CLK_FREQ_HZ(1000000),.STALL_TIMEOUT_MS(500),.RELIABLE_MEDIA(1),.PREV_PLAYLIST(1)) dut(
 .clk(clk),.rst(rst),.ready(ready),.scan_start(start),.scan_start_sector(32'd0),
 .scan_max_sector(32'd131071),.scan_target_count(4'd8),.scan_done(done),
 .scan_found_valid(found),.scan_found_sector(found_lba),.scan_found_slot(slot),.scan_found_total(total),
 .load_start(1'b0),.load_abort(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
 .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending));
always @(negedge clk)begin
 valid=0;ending=0;
 if(!rst)begin
  if(position>=0)begin
   if(position<512)begin data=bytes[selected*512+position];valid=1;position=position+1;end
   else begin ending=1;position=-1;wait_count=3;end
  end else if(wait_count!=0)wait_count=wait_count-1;
  else if(req)begin
   selected=-1;
   for(k=0;k<sectors;k=k+1)if(lbas[k]==addr)selected=k;
   if(selected<0)$fatal(1,"FAIL: unexpected raw sector request %0d",addr);
   position=0;requests=requests+1;
  end
 end
end
always @(posedge clk)begin
 if(found)begin
  if(slot>7 || seen[slot] || expected[slot]!==found_lba)
   $fatal(1,"FAIL: wrong/duplicate named slot %0d got=%0d expected=%0d",slot,found_lba,expected[slot]);
  seen[slot]<=1;found_count=found_count+1;
 end
end
initial begin
 if(!$value$plusargs("VECTORS=%s",vector_path))$fatal(1,"FAIL: missing vector folder");
 if(!$value$plusargs("SECTORS=%d",sectors))$fatal(1,"FAIL: missing sector count");
 if(!$value$plusargs("COUNT=%d",expected_count))$fatal(1,"FAIL: missing expected count");
 $readmemh({vector_path,"/lbas.hex"},lbas,0,sectors-1);
 $readmemh({vector_path,"/bytes.hex"},bytes,0,sectors*512-1);
 $readmemh({vector_path,"/expected.hex"},expected);
 repeat(5)@(negedge clk);rst=0;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(done);repeat(3)@(negedge clk);
 if(total!=expected_count || found_count!=expected_count)$fatal(1,"FAIL: wrong count got=%0d/%0d expected=%0d",total,found_count,expected_count);
 for(i=0;i<8;i=i+1)if(seen[i]!=(expected[i]!=32'hffffffff))$fatal(1,"FAIL: slot validity differs");
 $display("PASS: real FAT/BMP parser selected exactly %0d named slots from PREV_BMP, ignored root/04/decoys, requests=%0d",found_count,requests);
 $finish;
end
initial begin #10000000;$fatal(1,"FAIL: named directory scan timeout state=%0d count=%0d",dut.state,total);end
endmodule
