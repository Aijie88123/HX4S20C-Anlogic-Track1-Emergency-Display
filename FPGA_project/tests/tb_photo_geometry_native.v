`timescale 1ns/1ps
module tb_photo_geometry_native;
 reg clk=0,rst=1;always #6.666 clk=~clk;
 reg flip=0,back=0;reg [11:0] width=640,left=320;reg [9:0] height=360,top=180;
 reg [16:0] inv_x=4096,inv_y=5461;
 wire req,en,ack,word_read,pixel_empty;wire [31:0] pixel_data;wire [31:0] word_data;
 wire [20:0] base;wire word_empty;wire rawvs;
 reg mem=0,phase=1,net=0,mem_rst=1,preloaded=0;
 always #4 begin mem=~mem;phase=~phase;end
 always #20 net=~net;
 wire init_done,refresh,busy,rv,wr,rr;wire [31:0] rd,wd;wire [20:0] wa,ra;wire [3:0] dm;
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] pins_dm;wire [31:0] dq;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(pins_dm),.dq(dq));
 sdram ram(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(pins_dm),.SDR_DQ(dq),
  .Clk(mem),.Clk_sft(phase),.Rst(mem_rst),.Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 reg wreq=0,wen=0;reg [31:0] data=0;reg [20:0] wbase=460800,wlen=230400;wire wack,wfull,finish;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0),.ENABLE_GEOMETRY_GUARD(1)) frames(.geometry_mode(!rst),
  .rst(mem_rst),.mem_clk(mem),.Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.read_clk(clk),.read_req(req&&!rawvs),.read_req_ack(ack),.read_finish(),
  .read_addr_0(base),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd512),.read_en(word_read),.read_data(word_data),.read_empty(word_empty),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(net),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(wbase),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(wlen),.write_en(wen),.write_data(data),.write_full(wfull),.write_cancel(1'b0),.write_flip(1'b0));
 integer writes=0,refreshes=0;
 always @(posedge sclk)if(init_done && {ras,cas,we}==3'b001)refreshes=refreshes+1;
 always @(posedge sclk)if(preloaded && ({ras,cas,we}==3'b100 || memory.write_left!=0))
  if(({ras,cas,we}==3'b100 ? memory.index : memory.wp)<1843200)$fatal(1,"geometry background write corrupted an immutable photo slot");
 task write_frame;input integer address,words;integer n;
 begin
  @(negedge net);wbase=address;wlen=words;wreq=1;wait(wack);@(negedge net);wreq=0;repeat(16)@(negedge net);
  for(n=0;n<words;n=n+1)begin while(wfull)begin wen=0;@(negedge net);end
   wen=1;data=address<1843200?packed_word(address+n):32'h98124500+n;@(negedge net);
  end
  wen=0;wait(finish);repeat(32)@(negedge net);writes=writes+1;
 end endtask
 initial begin
  repeat(40)@(negedge mem);mem_rst=0;wait(init_done);repeat(200)@(negedge mem);
  write_frame(460800,230400);write_frame(691200,230400);preloaded=1;
 end
 wire hs,vs,de,ready,rawde,frame_start;wire [11:0] rawx,rawy;wire [23:0] rgb;
 rgb888_frame_unpack #(.FAST_WORD_READ(1)) unpack(.clk(clk),.rst(rst),.restart(req),.fast_mode(1'b1),
  .word_empty(word_empty),.word_data(word_data),.word_read(word_read),.pixel_read(en),.pixel_empty(pixel_empty),.pixel_data(pixel_data));
 video_scanout_720p #(.ENABLE_GEOMETRY(1)) dut(.clk(clk),.rst(rst),.read_req(req),.read_req_ack(ack),
  .read_en(en),.read_data(pixel_data),.read_empty(pixel_empty),.hs(hs),.vs(vs),.de(de),.rgb(rgb),.pixel_ready(ready),
  .raw_hs(),.raw_vs(rawvs),.raw_de(rawde),.raw_x(rawx),.raw_y(rawy),.raw_frame_start(frame_start),
  .geometry_active(1'b1),.geometry_flip(flip),.geometry_width(width),.geometry_left(left),
  .geometry_height(height),.geometry_top(top),.geometry_inv_x(inv_x),.geometry_inv_y(inv_y),
  .geometry_old_base(21'd460800),.geometry_new_base(21'd691200),.geometry_back_half(back),.geometry_read_base(base));
 function [23:0] pixel;input integer slot,sx,sy;
  begin pixel={8'h30+slot[7:0]*8'd17,sx[7:0]^slot[7:0],sy[7:0]^{6'd0,sx[9:8]}};end
 endfunction
 function [31:0] packed_word;input integer addr;integer slot,local_word,j,b,pidx;reg [23:0] color;
  begin
   slot=addr/230400;local_word=addr%230400;packed_word=0;
   for(j=0;j<4;j=j+1)begin b=local_word*4+j;pidx=b/3;color=pixel(slot,pidx%640,pidx/640);packed_word[j*8+:8]=color[(b%3)*8+:8];end
  end
 endfunction
 integer x=0,y=0,checks=0,total=0,cases=0,old_pixels=0,new_pixels=0,black_pixels=0;
 integer sx,sy,slot;reg [23:0] expected;reg previous_de=0,previous_vs=0;reg checking=0;
 always @(posedge clk)begin
  #1;
  if(rst)begin x=0;y=0;previous_de=0;previous_vs=0;end
  else begin
   if(vs && !previous_vs)begin x=0;y=0;end
   if(de)begin
    if(!previous_de)x=0;
    if(checking)begin
     sx=x/2;sy=(2*y)/3;slot=2;
     if(flip)begin
      if(width==0 || x<left || x>=left+width)begin expected=0;black_pixels=black_pixels+1;end
      else begin sx=((x-left)*inv_x)>>12;if(sx>639)sx=639;slot=back?3:2;expected=pixel(slot,sx,sy);end
     end else begin
      if(width!=0 && x>=left && x<left+width && y>=top && y<top+height)begin
       sx=((x-left)*inv_x)>>12;sy=((y-top)*inv_y)>>12;
       if(sx>639)sx=639;if(sy>479)sy=479;slot=3;new_pixels=new_pixels+1;
      end else old_pixels=old_pixels+1;
      expected=pixel(slot,sx,sy);
     end
     if(!ready || rgb!==expected)$fatal(1,"geometry pixel mismatch case=%0d flip=%0d back=%0d width=%0d x=%0d y=%0d ready=%b got=%h expected=%h state=%0d count=%0d",cases,flip,back,width,x,y,ready,rgb,expected,dut.geometry_coordinate.u_geometry_reader.state,dut.geometry_coordinate.u_geometry_reader.received);
     checks=checks+1;total=total+1;
    end
    x=x+1;
   end
   if(!de && previous_de)begin
    if(x!=1280)$fatal(1,"geometry raster line length %0d",x);
    y=y+1;
   end
   previous_de=de;previous_vs=vs;
  end
 end
 task scenario;input is_flip;input backface;input integer scale;
 begin
  checking=0;rst=1;repeat(10)@(negedge clk);
  flip=is_flip;back=backface;width=40*scale;height=720*scale/32;left=(1280-width)/2;top=(720-height)/2;
  inv_x=width?640*4096/width:0;inv_y=height?480*4096/height:0;
  checks=0;cases=cases+1;rst=0;checking=1;
  wait(checks==921600);@(negedge clk);checking=0;
  $display("PASS: geometry case %0d flip=%0d back=%0d scale=%0d full720p exact=%0d",cases,flip,back,scale,checks);
 end endtask
 integer phase_case;
 initial begin
  wait(preloaded);
  fork
   begin
    scenario(1,0,16);scenario(1,1,16);scenario(0,0,16);scenario(0,0,32);
    for(phase_case=0;phase_case<=32;phase_case=phase_case+1)scenario(0,0,phase_case);
   end
   begin wait(cases==3);while(cases<37)write_frame(1843200,28928);end
  join
  if(old_pixels==0 || new_pixels==0 || black_pixels==0)$fatal(1,"missing geometry coverage");
  $display("PASS: %0d geometry cases %0d exact RGB/pixel_ready checks; old background=%0d new foreground=%0d flip-mask=%0d; actual encrypted SDRAM and asynchronous FIFO, two seeded full immutable RGB888 images, concurrent dynamic-region writes",cases,total,old_pixels,new_pixels,black_pixels);
  $display("PASS: native geometry SDRAM writes=%0d refreshes=%0d",writes,refreshes);
  $finish;
 end
 initial begin #1000000000;$fatal(1,"geometry timeout cases=%0d checks=%0d",cases,checks);end
endmodule
