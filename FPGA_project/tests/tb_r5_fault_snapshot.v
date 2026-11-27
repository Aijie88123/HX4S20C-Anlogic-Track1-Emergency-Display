// Full-display component regression: byte-level physical-SPI surrogate and
// accelerated packet-boundary transport; wire timing/FCS independently tested.
`timescale 1ns/1ps
module tb_r5_fault_snapshot;
 reg clk=0,aclk=0,net=0,video=0,mem=0,rst_n=0,emergency=0;
 always #10 clk=~clk;always #5 aclk=~aclk;always #20 net=~net;always #6.666666 video=~video;always #4 mem=~mem;
 wire tfav,tfbv,iv,iav;wire [223:0] tfap,tfbp,ip,ackp;reg pav=0,pbv=0;reg [223:0] pa=0,pb=0,ahold,bhold;
 integer aflight=0,bflight=0,agap=0,bgap=0;wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 always @(posedge net)begin
  pav<=0;pbv<=0;if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if((tfav||iav)&&ar)begin ahold<=iav?ackp:tfap;aflight<=8;agap<=12;end
  if((tfbv||iv)&&br)begin bhold<=tfbv?tfbp:ip;bflight<=8;bgap<=12;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pbv<=1;pb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pav<=1;pa<=bhold;end end
 end
 a_tf_sector_service #(.SD_CLK_HZ(1000000),.SPI_HIGH_SPEED_DIV(6)) a_reader(.sd_clk(aclk),.net_clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(pav),.packet(pa),.stream_valid(tfav),.stream_data(tfap),.stream_ready(ar&&!iav),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 wire readreq,readen,readack,readempty,readbusy;wire [31:0] readword;wire [2:0] readrole;wire [5:0] available;wire [191:0] sizes;
 wire [34:0] snapshot;wire [3:0] source_fault;wire recurring;
 b_media_storage #(.CLK_FREQ_HZ(50000000),.REMOTE_TF(1),.IMAGE_ROLES(6),.NUMBERED_SIX(1),.EMERGENCY_PRIORITY(1),.FAST_NORMALIZE(0)) b_storage(.clk(clk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.online(1'b1),.packet_valid(pbv),.packet(pb),
  .tf_stream_valid(tfbv),.tf_stream_data(tfbp),.tf_stream_ready(br),
  .read_req(readreq),.read_en(readen),.read_role(readrole),.read_ack(readack),.read_empty(readempty),.read_data(readword),
  .available(available),.source_sizes(sizes),.source_fault(source_fault),.source_fault_recurring(recurring),.source_debug(snapshot),.priority_emergency(emergency),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),
  .map_write_ack(),.map_write_full(),.map_write_done_toggle(),.render_clk(),.render_rst());

 assign iav=0;assign iv=0;assign ackp=0;assign ip=0;assign readreq=0;assign readen=0;assign readrole=0;
 initial begin
 repeat(20)@(negedge net);rst_n=1;
 wait(b_storage.bmp_read_m0.state==4);
 // Deliberately inject early EOF, not a claimed reproduction of the board fault.
 force b_storage.bmp_read_m0.file_len=512;
 wait(b_storage.bmp_read_m0.scan_error_code==12);
 release b_storage.bmp_read_m0.file_len;
 wait(source_fault==12);repeat(10)@(negedge net);
 if(snapshot!=={3'd2,12'd0,20'd512})$fatal(1,"fault snapshot must precede retry reset got=%h",snapshot);
 if(b_storage.sd_reset_count==0)$fatal(1,"snapshot check missed retry-reset interval");
 repeat(100)@(negedge net);
 if(snapshot!=={3'd2,12'd0,20'd512})$fatal(1,"retry reset erased diagnostic snapshot");
 $display("PASS: deliberate early-EOF injection reports C; B captures first512 file bytes/zero full rows/file01 before retry reset, bundled cache-info CDC preserves the complete35-bit snapshot");$finish;
 end
 initial begin #1000000000;$fatal(1,"snapshot test timeout fault=%d state=%d",source_fault,b_storage.bmp_read_m0.state);end
endmodule
