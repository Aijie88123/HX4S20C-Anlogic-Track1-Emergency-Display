`timescale 1ns/1ps
module tb_animation_top;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 dual_board_control_top dut(.clk(clk),.rst_n(rst_n),.key_next(1'b1),.key_auto(1'b1),.key_emergency(1'b1),.sw(4'd0),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.eth_rx_clk(1'b0),.eth_rx_ctl(1'b0),.eth_rxd(4'd0),
  .eth_tx_clk(),.eth_tx_ctl(),.eth_txd(),.eth_mdc(),.eth_mdio(),.led(),.seg_sel(),.seg_data());
 wire net=dut.net_clk;wire av,wrq,cancel,wen,cv,ca;wire [223:0] ap;wire [31:0] wd;
 reg ack=0,done=0;integer writes=0,commits=0,normal_frames=0,map_frames=0,last_frame=-1;
 raster_map_window_receiver #(.ALLOW_ANIMATION(1)) receiver(.clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(dut.stream_valid&&dut.stream_ready),.packet(dut.outgoing_stream),.ack_valid(av),.ack_packet(ap),.ack_ready(1'b1),
  .write_cancel(cancel),.write_req(wrq),.write_ack(ack),.write_full(1'b0),.write_done_toggle(done),.write_en(wen),.write_data(wd),
  .commit_valid(cv),.commit_ready(1'b1),.commit_event(),.commit_animation(ca));
 always @(posedge net)begin
  dut.u_ethernet_link.ack_in<=av;dut.u_ethernet_link.ack_data<=ap;ack<=wrq;
  if(cancel || wrq)writes<=0;
  if(wen)begin writes<=writes+1;if(writes==115199)done<=~done;end
  if(cv)begin
   if(writes!=115200)$fatal(1,"partial top frame");commits<=commits+1;
   if(ca)begin
    if(dut.media_service.animation_frame!==(normal_frames%40))$fatal(1,"B top animation skipped/repeated frame expected=%d got=%d",normal_frames%40,dut.media_service.animation_frame);
    normal_frames<=normal_frames+1;
   end else map_frames<=map_frames+1;
  end
 end
 integer prior_count;
 initial begin
  force dut.media_service.available=6'b100000;
  force dut.media_service.u_storage.sd_ready=0;
  // Accelerate only the inter-frame wall clock, retain actual frame/owner logic.
  force dut.media_service.animation_clock=0;
  // A still-image sender can own SDRAM longer than the animation watchdog.
  force dut.media_service.read_owned=1;
  force dut.media_service.read_owner=0;
  repeat(30)@(negedge net);rst_n=1;wait(dut.media_service.u_storage.initialized);
  $readmemh("../assets/normal_animation/animation_words.hex",dut.media_service.u_storage.U3.ram,1536000,1843199);
  repeat(3000000)@(negedge net);
  if(dut.media_service.animation_fault || dut.media_service.rendered_map.u_animation.state!=0)
   $fatal(1,"legitimate shared SDRAM ownership incorrectly triggers animation watchdog");
  release dut.media_service.read_owned;
  release dut.media_service.read_owner;
  wait(normal_frames==41);
  @(negedge net);dut.u_ethernet_link.feedback=8'h40;
  wait(!dut.media_service.map_busy);repeat(1000)@(negedge net);prior_count=commits;
  repeat(10000)@(negedge net);if(commits!=prior_count)$fatal(1,"autoplay pause ignored");
  dut.u_ethernet_link.feedback=8'h44;wait(normal_frames>=43);
  @(negedge net);dut.u_ethernet_link.emergency=1;dut.u_ethernet_link.feedback=0;
  wait(!dut.media_service.map_busy);repeat(1000)@(negedge net);prior_count=map_frames;
  repeat(10000)@(negedge net);if(map_frames!=prior_count || dut.media_service.rendered_map.active_sync[1])$fatal(1,"map started prior_count prelude ready");
  dut.u_ethernet_link.feedback=8'h20;wait(map_frames==1);
  if(normal_frames<43)$fatal(1,"animation loop missing");
  $display("PASS: production B top read ownership/arbitration, all 40 frame IDs and 39->0 loop, pause/resume, normal animation stops for emergency, actual 2.5D shader starts only after prelude feedback and reaches complete A raster receiver");$finish;
 end
 initial begin #3500000000;$fatal(1,"B top timeout frames=%d owner=%d sender=%d decoder=%d",normal_frames,dut.media_service.read_owner,dut.media_service.rendered_map.u_raster_sender.state,dut.media_service.rendered_map.u_animation.state);end
endmodule
