`timescale 1ns/1ps
module tb_fat_geometry;
 reg clk=0,rst=1,scan=0,start=0;always #5 clk=~clk;
 wire wr,ready,done,found,complete,req,pv;wire [31:0] addr,handle;wire [2:0] slot;wire [23:0] rgb;
 reg [7:0] din=0;reg dv=0,ending=0;reg [31:0] load_handle=0;
 bmp_read #(.RELIABLE_MEDIA(1)) dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(scan),.scan_start_sector(32'd0),
 .scan_max_sector(32'hffffffff),.scan_target_count(3'd5),.scan_done(done),.scan_found_valid(found),
 .scan_found_sector(handle),.scan_found_slot(slot),.scan_found_total(),.load_start(start),.load_abort(1'b0),
 .load_complete(complete),.load_sector(load_handle),.sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),
 .bmp_height(16'd480),.src_w(),.src_h(),.pixel_start(),.load_nearly_done(),.write_req(wr),.write_req_ack(wr),
 .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(din),.sd_sec_read_data_valid(dv),
 .sd_sec_read_end(ending),.bmp_data_wr_en(pv),.bmp_data(rgb));
 integer spc=1,layout=0,bpb=1,fat=2,data_base=514;
 reg [7:0] headers[0:269],names[0:54];
 function integer width_for(input integer s);width_for=s==3?800:s==4?1280:640;endfunction
 function [7:0] card_byte(input integer lba,input integer k);
  integer c,cs,s,step,n,entry,p,position,value,offset;reg [31:0] v;
  begin
   card_byte=0;
   if(lba==0 && layout!=2)begin
    if(layout==0 || layout==3)begin
     if(k==450)card_byte=layout==3?7:12;
     if(k>=454 && k<458)card_byte=32'd1>>(8*(k-454));
    end else begin
     if(k==450)card_byte=7;
     if(k>=454 && k<458)card_byte=32'd128>>(8*(k-454));
     if(k==466)card_byte=12;
     if(k>=470 && k<474)card_byte=32'd4096>>(8*(k-470));
     if(k==498)card_byte=11;
     if(k>=502 && k<506)card_byte=32'd8192>>(8*(k-502));
    end
   end
   if(lba==bpb)begin
    if(k==11)card_byte=0;if(k==12)card_byte=2;
    if(k==13)card_byte=spc;if(k==14)card_byte=1;if(k==16)card_byte=1;
    if(k==37)card_byte=2;if(k==44)card_byte=2;
   end else if(lba>=fat && lba<fat+512)begin
    c=(lba-fat)*128+k/4;v=0;
    if(c==2)v=200;if(c==200)v=300;if(c==300)v=32'h0fffffff;
    s=c%20;step=c/20-1;
    if(s<5 && step>=0 && step<8)begin
     n=(54+width_for(s)*3+511)/512;
     v=(step+1)*spc>=n?32'h0fffffff:c+20;
    end
    card_byte=v>>(8*(k%4));
   end else if(lba>=data_base)begin
    c=(lba-data_base)/spc+2;cs=(lba-data_base)%spc;
    if(c==2 || c==200)begin if(k%32==0)card_byte=8'he5;end
    else if(c==300 && cs==0)begin
     entry=k/32;p=k%32;s=4-entry;
     if(entry<5)begin
      if(p<11)card_byte=names[s*11+p];
      if(p==11)card_byte=8'h20;
      if(p==26)card_byte=20+s;
      v=54+width_for(s)*3;if(p>=28)card_byte=v>>(8*(p-28));
     end
    end else begin
     s=c%20;step=c/20-1;
     if(s<5 && step>=0 && step<8)begin
      position=(step*spc+cs)*512+k;
      if(position<54)card_byte=headers[s*54+position];
      else begin offset=position-54;p=offset/3;
       if(p<width_for(s))case(offset%3)
        0:card_byte=(p+s)&255;1:card_byte=0;2:card_byte=(p^s)&255;
       endcase
      end
     end
    end
   end
  end
 endfunction
 integer read_lba=0,idx=0;reg active=0,drop=0;
 always @(posedge clk)begin
  dv<=0;ending<=0;
  if(rst)begin active<=0;drop<=0;end
  else if(active)begin
   if(idx<512)begin din<=card_byte(read_lba,idx);dv<=1;idx<=idx+1;end
   else begin active<=0;drop<=1;ending<=1;end
  end else if(drop)begin if(!req)drop<=0;end
  else if(req)begin active<=1;idx<=0;read_lba<=addr;end
 end
 integer pixels=0,item=0,checks=0,completes=0;reg [4:0] seen=0;reg checking=0;
 always @(posedge clk)begin
  #1;
  if(found)begin
   if(handle!==32'(20+slot) || seen[slot])$fatal(1,"geometry handle/duplicate");seen[slot]=1;
  end
  if(complete)completes=completes+1;
  if(checking && pv)begin
   if(rgb!=={8'(pixels^item),8'd0,8'(pixels+item)})$fatal(1,"SPC pixel mismatch spc=%0d layout=%0d pixel=%0d",spc,layout,pixels);
   pixels=pixels+1;checks=checks+1;
  end
 end
 integer i,j,z,w,len,prior,bound;reg [87:0] name;
 initial begin
  for(i=0;i<270;i=i+1)headers[i]=0;
  for(i=0;i<5;i=i+1)begin
   case(i)0:name="00ALARM BMP";1:name="01EVAC  BMP";2:name="02INFO  BMP";3:name="03INFO  BMP";4:name="04INFO  BMP";endcase
   for(j=0;j<11;j=j+1)names[i*11+j]=name>>(8*(10-j));
   w=width_for(i);len=54+w*3;
   headers[i*54]=66;headers[i*54+1]=77;headers[i*54+10]=54;headers[i*54+14]=40;
   headers[i*54+22]=1;headers[i*54+26]=1;headers[i*54+28]=24;
   for(j=0;j<4;j=j+1)begin headers[i*54+2+j]=len>>(j*8);headers[i*54+18+j]=w>>(j*8);end
  end
  for(z=0;z<9;z=z+1)begin
   spc=1<<(z%8);layout=z==8?3:z%3;bpb=(layout==0 || layout==3)?1:layout==1?4096:0;fat=bpb+1;data_base=fat+512;
   rst=1;checking=0;repeat(5)@(negedge clk);seen=0;rst=0;scan=1;@(negedge clk);scan=0;
   bound=0;while(!done && bound<1000000)begin @(negedge clk);bound=bound+1;end
   if(!done || seen!=31)$fatal(1,"geometry scan spc=%0d layout=%0d seen=%b",spc,layout,seen);
   for(i=0;i<5;i=i+1)begin
    item=i;pixels=0;prior=completes;checking=1;load_handle=20+i;start=1;@(negedge clk);start=0;
    bound=0;while(!ready && bound<100000)begin @(negedge clk);bound=bound+1;end
    repeat(2)@(negedge clk);checking=0;
    if(!ready || completes!=prior+1 || pixels!=width_for(i))$fatal(1,"geometry load spc=%0d slot=%0d",spc,i);
   end
  end
  $display("PASS: all FAT32 sectors-per-cluster 1/2/4/8/16/32/64/128; noncontiguous directory/file chains; first FAT partition priority over earlier non-FAT and later FAT, superfloppy and first-nonempty fallback; %0d exact source pixels",checks);$finish;
 end
endmodule
