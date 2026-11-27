`timescale 1ns/1ps
module tb_reliable_media;
 reg clk=0,rst=1,scan=0,start=0,abort_load=0;
 always #5 clk=~clk;
 wire ready,scan_done,found,complete,req,write_req,pixel_start,pixel_valid;
 wire [31:0] address,handle;wire [2:0] slot,total;wire [15:0] w,h;wire [23:0] rgb;
 reg [31:0] load_handle=0;reg [7:0] byte_data=0;reg byte_valid=0,sector_end=0;
 bmp_read #(.RELIABLE_MEDIA(1)) dut(.clk(clk),.rst(rst),.ready(ready),.load_nearly_done(),
  .scan_start(scan),.scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(3'd5),
  .scan_done(scan_done),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_total(total),.scan_found_slot(slot),
  .load_start(start),.load_abort(abort_load),.load_complete(complete),.load_sector(load_handle),.sd_init_done(1'b1),
  .state_code(),.bmp_width(16'd640),.bmp_height(16'd480),.src_w(w),.src_h(h),.pixel_start(pixel_start),
  .write_req(write_req),.write_req_ack(write_req),.sd_sec_read(req),.sd_sec_read_addr(address),
  .sd_sec_read_data(byte_data),.sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sector_end),
  .bmp_data_wr_en(pixel_valid),.bmp_data(rgb));
 reg [7:0] disk[0:33811967];reg [31:0] first[0:4],second[0:4];
 integer bad_mode=0,read_index=0,read_lba=0,pace=0;
 reg active_read=0,wait_drop=0;
 function [7:0] card_byte(input integer lba,input integer idx);
  integer absolute_byte,c,loc;reg [31:0] replacement;
  begin
   absolute_byte=lba*512+idx;card_byte=disk[absolute_byte];
   if(^card_byte===1'bx)card_byte=0;
   c=first[2];loc=2+c/128;
   replacement=bad_mode==1?32'h0fffffff:bad_mode==2?c:bad_mode==4?32'h0ffffff7:0;
   if((bad_mode==1 || bad_mode==2 || bad_mode==4) && lba==loc && idx/4==c%128)
    card_byte=replacement>>(8*(idx%4));
   c=second[2];loc=2+c/128;
   if(bad_mode==3 && lba==loc && idx/4==c%128)card_byte=first[2]>>(8*(idx%4));
   if(bad_mode==6 && lba==514+first[0]-2 && idx==26)card_byte=2;
   if(lba==514+first[0]-2)begin
    if(bad_mode==9 && idx==25)card_byte=8'hff;
    if(bad_mode==10 && idx==21)card_byte=1;
    if(bad_mode==11 && idx==28)card_byte=32;
    if(bad_mode==12 && idx==32)card_byte=1;
    if(bad_mode==13 && idx==10)card_byte=20;
    if(bad_mode==14 && idx==2)card_byte=disk[lba*512+2]-1'b1;
    if(bad_mode==15 && idx==19)card_byte=8'h10;
    if(bad_mode==16 && idx==29)card_byte=1;
    if(bad_mode==17 && idx==27)card_byte=1;
    if(bad_mode==18 && idx==0)card_byte="X";
    if(bad_mode==19 && idx==14)card_byte=39;
    if(bad_mode==20 && idx>=14 && idx<18)card_byte=8'hff;
   end
   if(bad_mode==7 && lba==2 && idx/4==2)card_byte=32'd2>>(8*(idx%4));
   if(bad_mode==8 && lba==3 && idx/4==72)card_byte=32'd2>>(8*(idx%4));
  end
 endfunction
 always @(posedge clk)begin
  byte_valid<=0;sector_end<=0;
  if(rst)begin active_read<=0;wait_drop<=0;read_index<=0;pace<=0;end
  else if(active_read)begin
   if(pace==1)begin
    pace<=0;
    if(read_index<512)begin
     byte_data<=card_byte(read_lba,read_index);byte_valid<=1;read_index<=read_index+1;end
    else begin sector_end<=1;active_read<=0;wait_drop<=1;end
   end else pace<=pace+1;
  end else if(wait_drop)begin if(!req)wait_drop<=0;end
  else if(req)begin
   read_lba<=address;read_index<=(bad_mode==5 && address>=2 && address<514)?512:0;
   active_read<=1;pace<=0;
  end
 end
 integer expected_slot=0,pixels=0,completed=0,x,y,checks=0;reg [4:0] seen=0;reg checking=0;
 reg [23:0] expected;
 always @(posedge clk)begin
  #1;
  if(found)begin
   if(slot>4 || handle!==first[slot] || seen[slot])$fatal(1,"named slot/order/duplicate mismatch");
   seen[slot]=1;
  end
  if(complete)completed=completed+1;
  if(checking && pixel_valid)begin
   x=pixels%(expected_slot==4?427:640);y=pixels/(expected_slot==4?427:640);
   expected={8'(x^expected_slot),8'(y),8'(x+y+expected_slot)};
   if(rgb!==expected)$fatal(1,"fragmented RGB or padding mismatch slot=%0d pixel=%0d actual=%h expected=%h",expected_slot,pixels,rgb,expected);
   pixels=pixels+1;checks=checks+1;
  end
 end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task rescan(input integer mode);
  integer bound;
  begin
   rst=1;checking=0;clocks(5);seen=0;bad_mode=mode;rst=0;scan=1;clocks(1);scan=0;bound=0;
   while(!scan_done && bound<60000)begin clocks(1);bound=bound+1;end
   if(!scan_done)$fatal(1,"root scan did not terminate mode=%0d",mode);
  end
 endtask
 task load_slot(input integer item,input bit success);
  integer bound,prior;
  begin
   expected_slot=item;pixels=0;prior=completed;checking=1;load_handle=first[item];start=1;clocks(1);start=0;
   bound=0;
   while(!ready && bound<12000000)begin clocks(1);bound=bound+1;end
   clocks(2);checking=0;
   if(!ready)$fatal(1,"file load timeout mode=%0d",bad_mode);
   if(success && (completed!=prior+1 || pixels!=(item==4?427*321:640*480)))$fatal(1,"incomplete accepted file mode=%0d slot=%0d pixels=%0d",bad_mode,item,pixels);
   if(!success && completed!=prior)$fatal(1,"corrupt chain was committed mode=%0d",bad_mode);
  end
 endtask
 initial begin
  $readmemh("media_vectors/disk.hex",disk);$readmemh("media_vectors/starts.hex",first);$readmemh("media_vectors/seconds.hex",second);
  rescan(0);if(seen!=31 || total!=5)$fatal(1,"fragmented root scan missed named files");
  for(integer j=0;j<5;j=j+1)load_slot(j,1);
  for(integer mode=1;mode<=5;mode=mode+1)begin bad_mode=mode;load_slot(2,0);end
  rescan(6);if(seen!=5'b11110 || total!=4)$fatal(1,"invalid planes accepted");
  rescan(7);if(seen!=0)$fatal(1,"root self-cycle leaked files");
  rescan(8);if(seen!=0)$fatal(1,"root two-node cycle leaked files");
  for(integer mode=9;mode<=20;mode=mode+1)begin
   rescan(mode);if(seen!=5'b11110 || total!=4)$fatal(1,"unsafe BMP header accepted mode=%0d",mode);
  end
  $display("PASS: three-cluster fragmented FAT32 directory; shuffled filename roles/duplicate rejection; %0d exact RGB pixels across nonadjacent file clusters and BMP padding; premature EOC, self/two-node cycles, bad cluster, empty FAT transaction, invalid signature/planes/bit depth/compression/dimension/offset/payload bounds and bounded root-cycle exit",checks);$finish;
 end
 initial begin #800000000;$fatal(1,"reliable media timeout");end
endmodule

