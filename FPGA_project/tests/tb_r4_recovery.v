`timescale 1ns/1ps
module tb_r4_phy_cache;
 reg clk=0,rst=1;always #20 clk=~clk;
 reg [12:0] count=0;always @(posedge clk)if(count==4999)count<=0;else count<=count+1'b1;
 wire configured,link,mdc;tri1 mdio;wire [2:0] address;
 ethernet_phy_config #(.BOOT_CYCLES(8)) config_phy(.clk(clk),.rst(rst),.poll(count==4999),.mdio(mdio),.mdc(mdc),.configured(configured),.link_100_full(link),.address(address));
 phy_model #(.ADDR(1)) phy(.mdc(mdc),.mdio(mdio),.link_enable(1'b1),.ready());
 reg cache_rst=1;reg enable=0,req=0,storage_ack=0;wire busy,cache_fault;
 b_animation_cache #(.STALL_CYCLES(64)) decoder(.clk(clk),.rst(cache_rst),.enabled(enable),.frame_index(6'd0),.frame_consumed(1'b0),
  .raster_req(req),.raster_en(1'b0),.raster_ack(),.raster_empty(),.raster_data(),
  .storage_req(),.storage_en(),.storage_busy(busy),.storage_ack(storage_ack),.storage_empty(1'b1),.storage_data(32'd0),.fault(cache_fault));
 initial begin
  repeat(8)@(negedge clk);rst=0;cache_rst=0;enable=1;req=1;
  wait(busy);repeat(90)@(negedge clk);
  if(busy || !cache_fault)$fatal(1,"missing ACK must fault and release animation storage owner");
  $display("PASS: absent SDRAM ACK releases animation owner and sets fault within watchdog");
  cache_rst=1;repeat(8)@(negedge clk);cache_rst=0;storage_ack=1;
  wait(decoder.state==2);repeat(90)@(negedge clk);
  if(busy || !cache_fault)$fatal(1,"empty FIFO must fault and release animation storage owner");
  $display("PASS: permanently empty SDRAM FIFO releases animation owner and sets fault");
  wait(configured && link);@(negedge clk);phy.ready=0;phy.gigabit=16'hffff;phy.advertise=0;
  wait(!configured);wait(configured && link);
  if(!phy.ready || phy.gigabit!=0)$fatal(1,"PHY profile not restored");
  $display("PASS: PHY-only reset automatically re-discovers and restores100M/full profile and link");
  $finish;
 end
 initial begin #40000000;$fatal(1,"recovery timeout");end
endmodule

module tb_r4_raster;
 reg clk=0,rst=1,online=1,valid=1,pv=0,read_ack=0;always #20 clk=~clk;
 reg [223:0] packet=0;wire consumed,busy,req;
 raster_map_sender #(.RETRY_CYCLES(64)) sender(.clk(clk),.rst(rst),.online(online),.frame_valid(valid),.frame_event(2'd0),
  .frame_consumed(consumed),.frame_animation(1'b0),.current_animation(),.packet_valid(pv),.packet(packet),
  .stream_valid(),.stream_data(),.stream_ready(1'b1),.read_req(req),.read_en(),.read_busy(busy),.read_ack(read_ack),.read_empty(1'b1),.read_data(32'd0));
 task start_frame;
 begin
  rst=1;online=1;valid=1;pv=0;read_ack=0;repeat(6)@(negedge clk);rst=0;
  wait(sender.state==1);@(negedge clk);packet=0;packet[7:0]=8;packet[23:8]=0;packet[31]=1;packet[47:32]=16'hffff;pv=1;
  @(negedge clk);pv=0;wait(sender.state==4);@(negedge clk);packet=0;packet[7:0]=8;packet[23:8]=1;packet[29]=1;packet[47:32]=16'hfffe;pv=1;
  @(negedge clk);pv=0;wait(req);
 end endtask
 initial begin
  start_frame();online=0;repeat(10)@(negedge clk);
  if(busy || !consumed)$fatal(1,"disconnect with missing ACK holds owner");
  $display("PASS: disconnect during raster REQUEST releases owner without waiting for SDRAM ACK");
  start_frame();read_ack=1;wait(sender.state==6);repeat(90)@(negedge clk);
  if(busy || !consumed)$fatal(1,"online empty FIFO holds owner");
  $display("PASS: online raster FIFO starvation aborts incomplete frame and releases owner");
  start_frame();read_ack=1;wait(sender.state==6);@(negedge clk);online=0;repeat(90)@(negedge clk);
  if(busy || !consumed)$fatal(1,"offline empty FIFO holds owner");
  $display("PASS: offline raster drain also times out and releases owner; no permanent lock");
  $finish;
 end
 initial begin #1000000;$fatal(1,"raster recovery timeout");end
endmodule
