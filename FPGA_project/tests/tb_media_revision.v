`timescale 1ns/1ps
module tb_media_revision;
 reg clk=0,rst=1;always #20 clk=~clk;
 wire[1:0] seen;
 genvar v;
 generate for(v=0;v<2;v=v+1)begin: lane
  wire valid,busy,received,ack;wire[223:0] packet,decoded,ack_packet;wire[3:0] nibble,revision,fault;wire recurrence;
  media_image_sender #(.IMAGE_ROLES(6),.STATUS_REVISION(v?2:0)) sender(.clk(clk),.rst(rst),.online(1'b1),
   .available(6'd0),.source_sizes(192'd0),.source_fault(4'd3),.source_fault_recurring(1'b1),.priority_emergency(1'b0),
   .packet_valid(ack),.packet(ack_packet),.stream_valid(valid),.stream_data(packet),.stream_ready(!busy),
   .read_ack(1'b0),.read_empty(1'b1),.read_data(32'd0),.read_req(),.read_en(),.read_role(),.read_busy());
  ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) tx(
   .clk(clk),.rst(rst),.start(valid&&!busy),.message(21'd0),.extension(8'd0),.stream_data(packet),.busy(busy),.nibble(nibble));
  ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) rx(
   .clk(clk),.rst(rst),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(received),.message(),.extension(),.stream_data(decoded));
  media_image_receiver #(.IMAGE_ROLES(6)) receiver(.clk(clk),.rst(rst),.online(1'b1),.packet_valid(received),.packet(decoded),
   .ack_valid(ack),.ack_packet(ack_packet),.ack_ready(1'b1),.write_ack(1'b0),.write_full(1'b0),.write_done_toggle(1'b0),.frame_commit_ready(1'b0),
   .remote_revision(revision),.remote_fault(fault),.remote_fault_recurring(recurrence));
  reg checked=0;assign seen[v]=checked;
  always @(posedge clk)if(!rst&&received&&decoded[7:0]==6)begin
   if(decoded[7:0]!=6||decoded[67:64]!=(v?2:0))$fatal(1,"FAIL: revision metadata not preserved by v8 MAC");
   repeat(2)@(negedge clk);
   if(revision!=(v?2:0)||fault!=3||!recurrence)$fatal(1,"FAIL: revision or load-fault status lost");
   checked=1;
  end
 end endgenerate
 initial begin #1000;rst=0;wait(&seen);$display("PASS: real v8 MAC CRC carries C2 revision and parser-stall fault3; old B revision0 distinguishable; fault/recurrence unchanged");$finish;end
 initial begin #1000000;$fatal(1,"FAIL: media revision timeout");end
endmodule
