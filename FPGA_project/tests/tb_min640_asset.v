module tb_min640_asset;
 parameter BYTE_PERIOD=4;
 reg clk=0,rst=1,scan=0,load=0,sdready=0,bvalid=0,ending=0;reg [7:0] bdata=0;
 always #5 clk=~clk;
 wire ready,req,done,found,complete,sof,pvalid,scaled,overflow,wrreq;
 wire [31:0] lba,handle;wire [2:0] role;wire [3:0] total;wire [15:0] w,h;
 wire [23:0] rgb,out;reg [31:0] file_handle=0;
 reg [7:0] disk[0:1048575];reg [23:0] expected[0:307199];
 integer fd,n,pos=-1,phase=0,base=0,reads=0,source_pixels=0,dest_pixels=0,pass=0,wait_clocks=0;
 bmp_read #(.CLK_FREQ_HZ(1000000),.STALL_TIMEOUT_MS(1500),.RELIABLE_MEDIA(1),.PREV_PLAYLIST(1)) parser(
 .clk(clk),.rst(rst),.ready(ready),.scan_start(scan),.scan_start_sector(32'd0),.scan_max_sector(32'd2047),.scan_target_count(4'd1),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_slot(role),.scan_found_total(total),
 .load_start(load),.load_abort(1'b0),.load_complete(complete),.load_sector(file_handle),.sd_init_done(sdready),
 .bmp_width(16'd640),.bmp_height(16'd480),.src_w(w),.src_h(h),.pixel_start(sof),.write_req(wrreq),.write_req_ack(wrreq),
 .sd_sec_read(req),.sd_sec_read_addr(lba),.sd_sec_read_data(bdata),.sd_sec_read_data_valid(bvalid),.sd_sec_read_end(ending),
 .bmp_data_wr_en(pvalid),.bmp_data(rgb));
 bmp_write_scaler #(.ANTIALIAS(1)) scaler(.clk(clk),.rst(rst),.src_sof(sof),.src_w(w[11:0]),.src_h(h[11:0]),.src_valid(pvalid),.src_pixel(rgb),
 .dst_valid(scaled),.dst_pixel(out),.overflow(overflow));
 always @(negedge clk)begin
  bvalid=0;ending=0;
  if(rst)begin pos=-1;phase=0;wait_clocks=0;end
  else if(wait_clocks!=0)wait_clocks=wait_clocks-1;
  else if(pos<0)begin
   if(req)begin if(lba>=2048)$fatal(1,"LBA outside fixture");base=lba*512;pos=0;phase=0;reads=reads+1;end
  end else if(pos<512)begin
   if(phase==BYTE_PERIOD-1)begin bdata=disk[base+pos];bvalid=1;pos=pos+1;phase=0;end else phase=phase+1;
  end else begin ending=1;pos=-1;wait_clocks=3+(reads%7);end
 end
 always @(posedge clk)if(!rst)begin
  if(found)begin if(role!=5)$fatal(1,"Incorrect named role");file_handle<=handle;end
  if(pvalid)begin
   if(source_pixels>=307200||rgb!==expected[source_pixels])$fatal(1,"BMP source mismatch pixel=%0d got=%h",source_pixels,rgb);
   source_pixels=source_pixels+1;
  end
  if(scaled)begin
   if(dest_pixels>=307200||out!==expected[dest_pixels])$fatal(1,"Normalized pixel mismatch at %0d got=%h",dest_pixels,out);
   dest_pixels=dest_pixels+1;
  end
  if(overflow)$fatal(1,"Scaler overflow");
 end
 initial begin
  fd=$fopen("min640_vectors/disk.bin","rb");n=$fread(disk,fd);$fclose(fd);if(n!=1048576)$fatal(1,"Fixture bytes");
  $readmemh("min640_vectors/pixels.hex",expected);
  repeat(6)@(negedge clk);rst=0;repeat(101)@(negedge clk);sdready=1;
  repeat(6)@(negedge clk);scan=1;@(negedge clk);scan=0;wait(done);repeat(10)@(negedge clk);
  if(total!=1||file_handle==0||w!=640||h!=480)$fatal(1,"Scan/header failed total=%d size=%dx%d handle=%d",total,w,h,file_handle);
  for(pass=0;pass<2;pass=pass+1)begin
   wait(ready);@(negedge clk);source_pixels=0;dest_pixels=0;load=1;@(negedge clk);load=0;
   wait(complete);repeat(64)@(negedge clk);
   if(source_pixels!=307200||dest_pixels!=307200)$fatal(1,"Incomplete frame source=%d normalized=%d",source_pixels,dest_pixels);
  end
  $display("PASS: exact current 02INFO.BMP 640x480 BI_RGB through real FAT/BMP parser and normalization twice, fragmented FAT chain, %0d-clock byte pacing, 614400 independent source and normalized pixels each, reads=%0d",BYTE_PERIOD,reads);$finish;
 end
 initial begin #2000000000;$fatal(1,"Asset timeout state=%0d reads=%0d pixels=%0d",parser.state,reads,source_pixels);end
endmodule
