`timescale 1ns/1ps
module tb_animation_sdram #(parameter PROFILE=1);
 localparam FRAMES=PROFILE==2?84:40;wire dense;
 reg clk=0,net=0,rst_n=0;always #10 clk=~clk;always #20 net=~net;
 reg [6:0] frame=0;reg req=0,ren=0,consumed=0;
 wire req_s,ren_s,busy,ack_s,empty_s,ack,empty,fault;wire [31:0] data_s,data;
 b_media_storage #(.CLK_FREQ_HZ(1000000),.REMOTE_TF(1),.IMAGE_ROLES(6),.NUMBERED_SIX(1),.ANIMATION_CACHE(1)) storage(
  .clk(clk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),
  .online(1'b0),.packet_valid(1'b0),.packet(224'd0),.tf_stream_valid(),.tf_stream_data(),.tf_stream_ready(1'b1),
  .read_req(req_s),.read_en(ren_s),.read_role(3'd7),.animation_frame(frame),.animation_dense(dense),.priority_emergency(1'b0),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),.map_write_ack(),.map_write_full(),.map_write_done_toggle(),
  .render_clk(),.render_rst(),.read_ack(ack_s),.read_empty(empty_s),.read_data(data_s),.available(),.source_sizes(),.source_fault(),.source_fault_recurring());
 b_animation_cache decoder(.clk(net),.rst(!rst_n),.enabled(1'b1),.frame_index(frame),.frame_consumed(consumed),
  .raster_req(req),.raster_en(ren),.raster_ack(ack),.raster_empty(empty),.raster_data(data),
  .storage_req(req_s),.storage_en(ren_s),.storage_busy(busy),.storage_ack(ack_s),.storage_empty(empty_s),.storage_data(data_s),.fault(fault),.dense_mode(dense));
 reg [31:0] reference[0:307199];integer n,j,x,y,pixel,idx,base,checked=0;reg [23:0] rgb;reg [15:0] colour;
 initial begin
  $readmemh(PROFILE==2?"../assets/normal_animation_v2/animation_words.hex":"../assets/normal_animation/animation_words.hex",reference);
  repeat(30)@(negedge net);rst_n=1;wait(storage.initialized);repeat(30)@(negedge net);
  $readmemh(PROFILE==2?"../assets/normal_animation_v2/animation_words.hex":"../assets/normal_animation/animation_words.hex",storage.U3.ram,1536000,1843199);
  for(n=0;n<FRAMES+1;n=n+1)begin
   frame=n==FRAMES?0:n;req=1;wait(ack);@(negedge net);req=0;
   for(j=0;j<115200;j=j+1)begin
    if(empty || fault)$fatal(1,"decoder incomplete frame");
    ren=1;@(negedge net);ren=0;
    x=j%320;y=j/320;pixel=PROFILE==2?(y*3/10)*192+x*3/5:(y*3/8)*240+x*3/4;base=frame*(PROFILE==2?3584:5632);
    idx=(reference[base+20+pixel/6]>>(8+4*(pixel%6)))&15;
    rgb=reference[base+4+idx]>>8;colour={rgb[23:19],rgb[15:10],rgb[7:3]};
    if(data!=={colour,colour})$fatal(1,"SDRAM cached animation mismatch n=%d pixel=%d got=%h expected=%h",n,j,data,{colour,colour});
    checked=checked+1;@(negedge net);
   end
   consumed=1;@(negedge net);consumed=0;repeat(20)@(negedge net);
  end
  // Invalid metadata must fail closed, not expose arbitrary cached bytes.
  storage.U3.ram[1536000]=0;frame=0;req=1;wait(fault);@(negedge net);req=0;
  if(ack)$fatal(1,"bad carrier was accepted");
  $display("PASS: actual B frame FIFO and SDRAM addressing, all 40 animation frames plus wrap, %0d independent RGB565 output words, corrupted header fails closed",checked);$finish;
 end
 initial begin #1000000000;$fatal(1,"SDRAM animation timeout state=%d count=%d",decoder.state,decoder.count);end
endmodule
