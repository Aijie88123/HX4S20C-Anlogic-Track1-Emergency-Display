// Protocol v7. A owns only the physical SPI sector reader; B owns FAT/BMP.
// Type 9: query/read request. Type 10: status or sixteen bytes. Type 11: ACK.
// Read responses echo both the 16-bit transaction and 32-bit LBA. No byte is
// released to the BMP parser until all 32 CRC-checked blocks are present.
module a_tf_sector_service_timed #(
 parameter SD_CLK_HZ=100000000,NET_CLK_HZ=25000000,
 parameter RETRY_CYCLES=NET_CLK_HZ/500,READ_TIMEOUT_CYCLES=SD_CLK_HZ/4,SPI_HIGH_SPEED_DIV=2
)(input net_clk,sd_clk,rst,online,input packet_valid,input [223:0] packet,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 input sd_miso,output sd_ncs,sd_dclk,sd_mosi);
 wire reset=rst||!online;
 (* ram_style="block" *) reg [7:0] sector_bytes[0:511];
 wire sd_ready,byte_valid,sector_end;wire [7:0] byte_data;
 // A-specific physical-reader timing implementation. The B-side bridge below
 // remains identical to common/remote_tf_sector.v and the paired B firmware.
 reg sd_req;reg [31:0] sd_address;reg [15:0] recovery;reg recovery_active;
 sd_card_top #(.CLK_FREQ_HZ(SD_CLK_HZ),.SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV)) sd_card_top_m0(
  .clk(sd_clk),.rst(reset||recovery_active),.sd_init_done(sd_ready),
  .sd_sec_read(sd_req),.sd_sec_read_addr(sd_address),.sd_sec_read_data(byte_data),
  .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sector_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end(),
  .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));
 reg launch;reg [47:0] command;wire command_ready,command_valid;wire [47:0] received_command;
 ethernet_mailbox #(.WIDTH(48)) u_request(.src_clk(net_clk),.src_rst(reset),.src_valid(launch),
  .src_data(command),.src_ready(command_ready),.dst_clk(sd_clk),.dst_rst(reset),.dst_valid(command_valid),.dst_data(received_command));
 localparam WD_W=READ_TIMEOUT_CYCLES>1?$clog2(READ_TIMEOUT_CYCLES):1;
 reg [1:0] sd_state;reg [9:0] count;reg [WD_W-1:0] watchdog;reg watchdog_last;reg [15:0] sd_id;
 reg result_valid,result_ok;wire result_ready,result_net;wire [16:0] result;
 reg release_toggle;reg [2:0] release_sync;reg release_seen;
 ethernet_mailbox #(.WIDTH(17)) u_result(.src_clk(sd_clk),.src_rst(reset),.src_valid(result_valid),
  .src_data({sd_id,result_ok}),.src_ready(result_ready),.dst_clk(net_clk),.dst_rst(reset),.dst_valid(result_net),.dst_data(result));
 always @(posedge sd_clk or posedge reset)
  if(reset)begin sd_state<=0;sd_req<=0;sd_address<=0;sd_id<=0;count<=0;watchdog<=0;
   result_valid<=0;result_ok<=0;recovery<=0;recovery_active<=0;
   watchdog_last<=READ_TIMEOUT_CYCLES<=1;release_sync<=0;release_seen<=0;end
  else begin
   sd_req<=0;release_sync<={release_sync[1:0],release_toggle};
   if(recovery_active)begin
    recovery<=recovery-1'b1;
    if(recovery==16'd1)recovery_active<=0;
   end
   case(sd_state)
    0:if(command_valid)begin sd_address<=received_command[31:0];sd_id<=received_command[47:32];
      count<=0;watchdog<=0;watchdog_last<=READ_TIMEOUT_CYCLES<=1;release_seen<=release_sync[2];
      if(sd_ready&&!recovery_active)begin sd_req<=1;sd_state<=1;end
      else begin result_ok<=0;result_valid<=1;sd_state<=2;end
     end
    1:begin
     if(byte_valid)begin if(count<512)sector_bytes[count[8:0]]<=byte_data;count<=count+1'b1;end
     if(sector_end)begin result_ok<=count==512||(byte_valid&&count==511);result_valid<=1;sd_state<=2;end
     else if(watchdog_last)begin recovery<=16'hffff;recovery_active<=1;result_ok<=0;result_valid<=1;sd_state<=2;end
     else begin
      watchdog<=watchdog+1'b1;
      watchdog_last<=watchdog==READ_TIMEOUT_CYCLES-2;
     end
    end
    2:if(result_valid&&result_ready)begin result_valid<=0;sd_state<=3;end
    3:if(release_sync[2]!=release_seen)sd_state<=0;
   endcase
  end
 reg [1:0] ready_sync,busy_sync;
 always @(posedge net_clk or posedge reset)
  if(reset)begin ready_sync<=0;busy_sync<=0;end
  else begin ready_sync<={ready_sync[0],sd_ready&&!recovery_active};busy_sync<={busy_sync[0],sd_state!=0};end
 localparam IDLE=0,WAIT_SD=1,BUILD=2,SEND=3,ACK=4,STATUS=5;
 reg [2:0] state;reg [15:0] id;reg [31:0] lba,timer;reg [4:0] block;
 reg [4:0] build_byte;reg [7:0] ram_q;reg [8:0] ram_address;reg [223:0] held;
 reg [2:0] attempts;reg pending_read;reg [47:0] pending_command;
 assign stream_valid=state==SEND||state==STATUS;
 assign stream_data=held;
 always @(posedge net_clk)ram_q<=sector_bytes[ram_address];
 wire request=packet_valid&&packet[7:0]==9;
 wire matching_ack=packet_valid&&packet[7:0]==11&&packet[23:8]==id&&packet[31:24]=={3'd0,block};
 always @(posedge net_clk or posedge reset)
  if(reset)begin state<=IDLE;launch<=0;command<=0;id<=0;lba<=0;timer<=0;block<=0;
   build_byte<=0;ram_address<=0;held<=0;attempts<=0;release_toggle<=0;pending_read<=0;pending_command<=0;end
  else begin
   launch<=0;
   if(result_net&&state!=WAIT_SD)release_toggle<=~release_toggle;
   case(state)
    IDLE:if(request)begin
     if(packet[31:24]==0)begin held<=0;held[7:0]<=10;held[23:8]<=packet[23:8];held[31:24]<=8'hff;
      held[39:32]<={6'd0,busy_sync[1],ready_sync[1]};state<=STATUS;pending_read<=0;end
     else if(packet[31:24]==1)begin pending_command<={packet[23:8],packet[63:32]};pending_read<=1;end
    end else if(pending_read&&command_ready&&!busy_sync[1])begin
     id<=pending_command[47:32];lba<=pending_command[31:0];command<=pending_command;
     launch<=1;pending_read<=0;state<=WAIT_SD;
    end
    WAIT_SD:if(result_net)begin
     if(result[16:1]==id&&result[0])begin block<=0;ram_address<=0;build_byte<=0;state<=BUILD;attempts<=0;end
     else begin held<=0;held[7:0]<=10;held[23:8]<=id;held[31:24]<=8'hff;held[39:32]<=8'h04;
      state<=STATUS;release_toggle<=~release_toggle;end
    end
    BUILD:begin
     if(build_byte==0)begin held<=0;held[7:0]<=10;held[23:8]<=id;held[31:24]<={3'd0,block};held[63:32]<=lba;end
     // Two warm-up clocks for a synchronous, dual-clock sector RAM.
     if(build_byte>=2)held[(build_byte-2)*8+64+:8]<=ram_q;
     if(build_byte<16)ram_address<={block,4'd0}+build_byte[3:0];
     if(build_byte==17)begin state<=SEND;timer<=0;end else build_byte<=build_byte+1'b1;
    end
    SEND:if(stream_ready)begin state<=ACK;timer<=0;end
    ACK:if(matching_ack)begin
     if(block==31)begin state<=IDLE;release_toggle<=~release_toggle;end
     else begin block<=block+1'b1;ram_address<={block+5'd1,4'd0};build_byte<=0;state<=BUILD;attempts<=0;end
    end else if(timer==RETRY_CYCLES-1)begin
     timer<=0;if(attempts==4)begin state<=IDLE;release_toggle<=~release_toggle;end
     else begin attempts<=attempts+1'b1;state<=SEND;end
    end else timer<=timer+1'b1;
    STATUS:if(stream_ready)state<=IDLE;
   endcase
   // A restarted B first queries the card. Abort an old published sector,
   // but allow an in-flight physical read to finish and report before release.
   if(request&&packet[31:24]==0&&state!=IDLE&&state!=STATUS)begin
     // A query coincident with the result-mailbox pulse must also release:
     // that result is consumed now and will not pulse again after cancellation.
     if(state!=WAIT_SD||result_net)release_toggle<=~release_toggle;
     state<=IDLE;pending_read<=0;
    end
    // B may have published the sector although its final ACK was lost. A new
    // transaction proves that B finished the old 512-byte publication. Keep
    // that request until the old physical-reader ownership crosses back;
    // launching immediately could overwrite a sector still owned by SD.
    if(request&&packet[31:24]==1&&packet[23:8]!=id&&block==31&&(state==ACK||state==SEND))begin
     release_toggle<=~release_toggle;state<=IDLE;timer<=0;
     pending_command<={packet[23:8],packet[63:32]};pending_read<=1;
   end
  end
endmodule

