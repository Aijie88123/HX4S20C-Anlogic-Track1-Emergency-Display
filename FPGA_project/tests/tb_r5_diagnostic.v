`timescale 1ns/1ps
module tb_r5_diagnostic #(parameter PREPIXEL=0);
 reg clk=0,net=0,rst_n=0;always #10 clk=~clk;always #20 net=~net;
 wire sv,busy;wire [223:0] stream;wire [3:0] nibble;wire received;wire [223:0] packet;
 localparam [34:0] SNAP=PREPIXEL?{3'd1,12'hfe2,20'd0}:{3'd2,12'd479,20'd921600};
 media_image_sender #(.IMAGE_ROLES(6),.STATUS_REVISION(6),.DIAGNOSTICS(1)) sender(.clk(net),.rst(!rst_n),.online(1'b1),.available(6'd0),.source_sizes(192'd0),
 .source_fault(4'hc),.source_fault_recurring(1'b1),.priority_emergency(1'b0),.source_debug(SNAP),.packet_valid(1'b0),.packet(224'd0),
 .stream_valid(sv),.stream_data(stream),.stream_ready(!busy),.read_busy(),.read_req(),.read_ack(1'b0),.read_empty(1'b1),.read_data(32'd0),.read_en(),.read_role());
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MEDIA(1),.RAW_TF(1),.RAW_TF_VERSION(9)) tx(.clk(net),.rst(!rst_n),.start(sv&&!busy),.message(21'd0),.extension(8'd0),.stream_data(stream),.busy(busy),.nibble(nibble));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MEDIA(1),.RAW_TF(1),.RAW_TF_VERSION(9)) rx(.clk(net),.rst(!rst_n),.nibble(nibble),.valid(busy),.error(1'b0),.packet_valid(received),.stream_data(packet),.message(),.extension());
 wire [3:0] load_fault,revision_sync;wire load_fault_recurring;wire [34:0] media_debug,debug_clk;
 media_image_receiver #(.IMAGE_ROLES(6)) receiver(.clk(net),.rst(!rst_n),.online(1'b1),.packet_valid(received),.packet(packet),.ack_ready(1'b1),
 .write_ack(1'b0),.write_full(1'b0),.write_done_toggle(1'b0),.frame_commit_ready(1'b0),
 .remote_fault(load_fault),.remote_fault_recurring(load_fault_recurring),.remote_revision(revision_sync),.remote_debug(media_debug));
 ethernet_mailbox #(.WIDTH(35)) cdc(.src_clk(net),.src_rst(!rst_n),.src_valid(1'b1),.src_data(media_debug),.src_ready(),.dst_clk(clk),.dst_rst(!rst_n),.dst_valid(),.dst_data(debug_clk));
 wire [6:0] seg_data_event=7'h7f,revision_segments=7'h7f,seg_data_sw=7'h7f,seg_data_fault=7'h7f,seg_data_0=7'h7f;
 wire [5:0] seg_sel;wire [7:0] seg_data;
    // Fault pages: normal status -> b + five hex file-byte digits ->
    // d + file number + 0 + three hex completed-row digits. One second each.
    reg [25:0] debug_tick;reg [1:0] debug_page;reg [3:0] fault_meta,fault_sync;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin debug_tick<=0;debug_page<=0;fault_meta<=0;fault_sync<=0;end
      else begin
        fault_meta<=load_fault;fault_sync<=fault_meta;
        if(fault_sync==0 || revision_sync<5)begin debug_tick<=0;debug_page<=0;end
        else if(debug_tick==49999999)begin debug_tick<=0;debug_page<=debug_page==2?0:debug_page+1'b1;end
        else debug_tick<=debug_tick+1'b1;
      end
    wire [3:0] debug_file=debug_clk[34:32]==0?5:debug_clk[34:32]==1?6:
      debug_clk[34:32]==2?1:debug_clk[34:32]==3?2:debug_clk[34:32]==4?3:4;
    wire debug_predata=revision_sync>=6 && debug_clk[19:0]==0 && debug_clk[31:25]==7'h7f;
    wire [23:0] debug_nibbles=debug_page==1?{4'hb,debug_clk[19:0]}:
      debug_predata?{4'he,debug_file,8'd0,3'd0,debug_clk[24:20]}:{4'hd,debug_file,4'd0,debug_clk[31:20]};
    wire [41:0] debug_segments;
    genvar dbg;
    generate for(dbg=0;dbg<6;dbg=dbg+1)begin: fault_hex
      seg_decoder u_hex(.bin_data(debug_nibbles[(5-dbg)*4 +:4]),.seg_data(debug_segments[dbg*7 +:7]));
    end endgenerate
    seg_scan seg_scan_m0 (
        .clk(clk),.rst_n(rst_n),.seg_sel(seg_sel),.seg_data(seg_data),
        .seg_data_0({1'b1,debug_page==0?seg_data_event:debug_segments[0 +:7]}),
        .seg_data_1({1'b1,debug_page==0?revision_segments:debug_segments[7 +:7]}),
        .seg_data_2({1'b1,debug_page==0?7'b100_0110:debug_segments[14 +:7]}),
        .seg_data_3({1'b1,debug_page==0?seg_data_sw:debug_segments[21 +:7]}),
        .seg_data_4({debug_page==0 && load_fault_recurring?1'b0:1'b1,debug_page==0?seg_data_fault:debug_segments[28 +:7]}),
        .seg_data_5({1'b1,debug_page==0?seg_data_0:debug_segments[35 +:7]})
    );



 task next_page;begin @(negedge clk);debug_tick=49999999;@(posedge clk);#1;end endtask
 initial begin
 repeat(10)@(negedge net);rst_n=1;wait(debug_clk==SNAP);repeat(8)@(negedge clk);
 if(load_fault!=12 || revision_sync!=6 || !load_fault_recurring)$fatal(1,"status/fault/revision lost on v9 MAC");
 next_page();if(debug_page!=1 || debug_nibbles!==(PREPIXEL?24'hb00000:24'hbe1000))$fatal(1,"byte page expected bE1000 got=%h",debug_nibbles);
 next_page();if(debug_page!=2 || debug_nibbles!==(PREPIXEL?24'he60002:24'hd101df))$fatal(1,"row/file page expected d101dF got=%h",debug_nibbles);
 next_page();if(debug_page!=0)$fatal(1,"normal status page not restored");
 if(PREPIXEL)$display("PASS: R6 pre-pixel snapshot displays b00000 and E60002 via actual v9 MAC/FCS, status receiver and A page RTL");
 $display("PASS: production status sender -> v9 Ethernet TX/RX+FCS -> A status receiver -> bundled CDC -> actual A fault-page RTL: snapshot921600 bytes/479 rows/file01 displays bE1000 and d101dF, normal page returns; payload does not add packets");$finish;
 end
 initial begin #1000000;$fatal(1,"diagnostic status timeout");end
endmodule
