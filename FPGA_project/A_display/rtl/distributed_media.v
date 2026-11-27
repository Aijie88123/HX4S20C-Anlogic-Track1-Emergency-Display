// Protocol-v5 media service. Packet byte zero is stream_data[7:0].
// Six RGB888 pixels per data packet; metadata, stop-and-wait ACK, serial IDs.
// An image becomes cache-visible only after the SDRAM writer and blanking commit.
module media_image_receiver #(parameter FRAME_PIXELS=307200,IMAGE_ROLES=5,PACK_RGB888=0,IMMUTABLE_CACHE=0)(
 input clk,rst,online,input cache_reset,input packet_valid,input [223:0] packet,
 output reg ack_valid,output reg [223:0] ack_packet,input ack_ready,
 output write_cancel,output reg write_req,input write_ack,write_full,input write_done_toggle,
 output write_en,output [31:0] write_data,
 output frame_commit_valid,input frame_commit_ready,
 output reg [2:0] commit_role,output reg [15:0] commit_width,commit_height,
 output transfer_active,output [8:0] receive_progress,output reg [3:0] remote_fault,output reg remote_fault_recurring,output reg [3:0] remote_revision,output reg [34:0] remote_debug);
 localparam CHUNKS=FRAME_PIXELS/6,LAST_CHUNK=CHUNKS-1;
 localparam IDLE=0,SETUP=1,DATA=2,EMIT=3,FINISH=4,COMMIT=5,RESET_WRITER=6;
 reg [2:0] state;reg [15:0] frame_id,next_chunk,last_id;reg last_valid;reg [2:0] last_role;
 reg [143:0] pixels;reg [2:0] emit_index;reg finish_epoch;
 reg [1:0] pack_phase;reg [23:0] pack_tail;
 reg [IMAGE_ROLES-1:0] complete_roles;reg discard_frame;
 wire emit_step=state==EMIT && (discard_frame || !write_full || (PACK_RGB888 && pack_phase==0));
 reg [4:0] reset_wait;reg [2:0] finish_sync;reg [1:0] ack_sync;
 wire [15:0] received_id=packet[23:8],received_chunk=packet[47:32];
 wire [7:0] flags=packet[31:24];wire [2:0] role=flags[2:0];
 wire metadata=packet[7:0]==4 && flags[7] && flags[5] && !flags[6] && flags[4:3]==0;
 wire [15:0] width=packet[71:56],height=packet[87:72];
 function newer;input [15:0] a,b;reg [15:0] distance;
  begin distance=a-b;newer=distance!=0 && !distance[15];end endfunction
 function [223:0] acknowledgement;input [15:0] id,index;input [7:0] f;
  begin acknowledgement=0;acknowledgement[7:0]=5;acknowledgement[23:8]=id;
   acknowledgement[31:24]=f;acknowledgement[47:32]=index;end endfunction
 assign write_cancel=state==RESET_WRITER || !online;
 assign transfer_active=state!=IDLE;
 // One step is 128 received six-pixel packets; a 640x480 frame has 400.
 assign receive_progress=next_chunk[15:7];
 assign frame_commit_valid=state==COMMIT;
 assign write_en=state==EMIT && !discard_frame && !write_full && (!PACK_RGB888 || pack_phase!=0);
 assign write_data=!PACK_RGB888?{pixels[23:0],8'd0}:
  pack_phase==1?{pixels[7:0],pack_tail}:
  pack_phase==2?{pixels[15:0],pack_tail[15:0]}:{pixels[23:0],pack_tail[7:0]};
 // Cached-frame ownership follows the display reset, not the Ethernet PLL.
 // Losing/restarting the link can never make a complete visible slot writable.
 always @(posedge clk or posedge cache_reset)
  if(cache_reset)complete_roles<=0;
  else if(state==COMMIT && frame_commit_ready)complete_roles[commit_role]<=1;
 always @(posedge clk or posedge rst)
  if(rst)begin finish_sync<=0;ack_sync<=0;end
  else begin finish_sync<={finish_sync[1:0],write_done_toggle};ack_sync<={ack_sync[0],write_ack};end
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;frame_id<=0;next_chunk<=0;last_id<=0;last_valid<=0;last_role<=0;
   discard_frame<=0;
   pixels<=0;emit_index<=0;pack_phase<=0;pack_tail<=0;finish_epoch<=0;write_req<=0;reset_wait<=0;
   ack_valid<=0;ack_packet<=0;commit_role<=0;commit_width<=0;commit_height<=0;
   remote_fault<=0;remote_fault_recurring<=0;remote_revision<=0;remote_debug<=0;
  end else begin
   if(ack_valid && ack_ready)ack_valid<=0;
   if(!online)begin state<=IDLE;write_req<=0;ack_valid<=0;end
   else begin
    case(state)
     RESET_WRITER:if(reset_wait==31)begin state<=SETUP;write_req<=1;finish_epoch<=finish_sync[2];end else reset_wait<=reset_wait+1'b1;
     SETUP:if(ack_sync[1])begin
      write_req<=0;state<=DATA;ack_valid<=1;
      ack_packet<=acknowledgement(frame_id,16'hfffe,8'h20|commit_role);
     end
     EMIT:if(emit_step)begin
      if(PACK_RGB888)begin
       pack_phase<=pack_phase+1'b1;
       case(pack_phase)0:pack_tail<=pixels[23:0];1:pack_tail<={8'd0,pixels[23:8]};
        2:pack_tail<={16'd0,pixels[23:16]};default:pack_tail<=0;endcase
      end
      pixels<=pixels>>24;
      if(emit_index==5)begin
       emit_index<=0;next_chunk<=next_chunk+1'b1;
       if(next_chunk==LAST_CHUNK)state<=discard_frame?COMMIT:FINISH;
       else begin state<=DATA;ack_valid<=1;ack_packet<=acknowledgement(frame_id,next_chunk,{5'd0,commit_role});end
      end else emit_index<=emit_index+1'b1;
     end
     FINISH:if(finish_sync[2]!=finish_epoch)state<=COMMIT;
     COMMIT:if(frame_commit_ready)begin
      state<=IDLE;last_valid<=1;last_id<=frame_id;last_role<=commit_role;
      ack_valid<=1;ack_packet<=acknowledgement(frame_id,LAST_CHUNK,8'h40|commit_role);
     end
    endcase
    if(packet_valid && packet[7:0]==6)begin
     remote_fault<=packet[51:48];remote_fault_recurring<=packet[52];remote_revision<=packet[67:64];remote_debug<=packet[106:72];
     if(flags[7] || (state==IDLE && !last_valid))begin
      ack_valid<=1;ack_packet<=acknowledgement(state!=IDLE?frame_id:(last_valid?last_id:16'hffff),16'hffff,8'h80);
     end
    end
    if(packet_valid && metadata && role<IMAGE_ROLES && width>0 && width<=4095 && height>0 && height<=4095)begin
     if(state!=IDLE && received_id==frame_id && role==commit_role)begin
      if(state!=SETUP && state!=RESET_WRITER)begin ack_valid<=1;ack_packet<=acknowledgement(frame_id,16'hfffe,8'h20|commit_role);end
     end else if((!last_valid || newer(received_id,last_id)) && (state==IDLE || newer(received_id,frame_id)))begin
      discard_frame<=IMMUTABLE_CACHE && complete_roles[role];
      state<=IMMUTABLE_CACHE && complete_roles[role]?DATA:RESET_WRITER;
      if(IMMUTABLE_CACHE && complete_roles[role])begin
       ack_valid<=1;ack_packet<=acknowledgement(received_id,16'hfffe,8'h20|role);
      end
      pack_phase<=0;pack_tail<=0;reset_wait<=0;frame_id<=received_id;next_chunk<=0;commit_role<=role;
      commit_width<=width;commit_height<=height;finish_epoch<=finish_sync[2];write_req<=0;
     end
    end else if(packet_valid && packet[7:0]==4 && !flags[7] && !flags[5] && flags[4:3]==0)begin
     if(state==DATA && received_id==frame_id && role==commit_role && received_chunk<CHUNKS && flags[6]==(received_chunk==LAST_CHUNK))begin
      if(received_chunk==next_chunk)begin pixels<=packet[199:56];emit_index<=0;state<=EMIT;end
      else if(next_chunk!=0 && received_chunk==next_chunk-1'b1)begin
       ack_valid<=1;ack_packet<=acknowledgement(frame_id,received_chunk,{5'd0,commit_role});
      end
     end else if(state==IDLE && last_valid && received_id==last_id && role==last_role && received_chunk==LAST_CHUNK && flags[6])begin
      ack_valid<=1;ack_packet<=acknowledgement(last_id,LAST_CHUNK,8'h40|last_role);
     end
    end
   end
  end
endmodule

module media_image_sender #(parameter FRAME_PIXELS=307200,RETRY_CYCLES=5000000,IMAGE_ROLES=5,EMERGENCY_PRIORITY=0,STATUS_REVISION=0,DIAGNOSTICS=0)(
 input clk,rst,online,input [IMAGE_ROLES-1:0] available,input [IMAGE_ROLES*32-1:0] source_sizes,
 input [3:0] source_fault,input source_fault_recurring,input priority_emergency,input [34:0] source_debug,
 input packet_valid,input [223:0] packet,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 output read_busy,output read_req,input read_ack,read_empty,input [31:0] read_data,output read_en,
 output reg [2:0] read_role);
 localparam CHUNKS=FRAME_PIXELS/6,LAST_CHUNK=CHUNKS-1;
 localparam HELLO_SEND=0,HELLO_WAIT=1,CHOOSE=2,META_SEND=3,META_WAIT=4,
  REQUEST=5,POP=6,TAKE=7,DATA_SEND=8,DATA_WAIT=9,DRAIN_POP=10,DRAIN_TAKE=11,STATUS_SEND=12;
 reg [3:0] state;reg [223:0] held;reg [15:0] frame_id,chunk;
 reg [143:0] pixels;reg [2:0] fill;reg [19:0] consumed;
 reg [IMAGE_ROLES-1:0] sent;reg [24:0] idle_count;reg [1:0] read_ack_sync;reg [22:0] timeout;reg [2:0] retries;reg reading;
 wire waiting=state==HELLO_WAIT || state==META_WAIT || state==DATA_WAIT;
 wire expired=timeout==RETRY_CYCLES-1;
 wire ack=packet_valid && packet[7:0]==5;
 wire ack_frame=ack && packet[23:8]==frame_id && packet[26:24]==read_role;
 reg [2:0] selected;reg select_valid;
 always @* begin
  selected=2;select_valid=1;
  if(EMERGENCY_PRIORITY && priority_emergency && available[0]&&!sent[0])selected=0;
  else if(EMERGENCY_PRIORITY && priority_emergency && available[1]&&!sent[1])selected=1;
  else if(EMERGENCY_PRIORITY && priority_emergency)select_valid=0;
  else if(IMAGE_ROLES>=6)begin
   if(available[2]&&!sent[2])selected=2;
   else if(available[3]&&!sent[3])selected=3;
   else if(available[4]&&!sent[4])selected=4;
   else if(available[5]&&!sent[5])selected=5;
   else if(IMAGE_ROLES==8 && available[6]&&!sent[6])selected=6;
   else if(IMAGE_ROLES==8 && available[7]&&!sent[7])selected=7;
   else if(available[0]&&!sent[0])selected=0;
   else if(available[1]&&!sent[1])selected=1;
   else select_valid=0;
  end else begin
  selected=2;select_valid=1;
  if(available[2]&&!sent[2])selected=2;
  else if(available[0]&&!sent[0])selected=0;
  else if(available[3]&&!sent[3])selected=3;
  else if(available[4]&&!sent[4])selected=4;
  else if(IMAGE_ROLES==6 && available[5]&&!sent[5])selected=5;
  else if(available[1]&&!sent[1])selected=1;
  else select_valid=0;
  end
 end
 function [223:0] hello_packet;input [3:0] fault;input recurrence;input [IMAGE_ROLES-1:0] mask;
  begin hello_packet=0;hello_packet[7:0]=6;hello_packet[31:24]=8'h80;
   hello_packet[51:48]=fault;hello_packet[52]=recurrence;hello_packet[56 +: IMAGE_ROLES]=mask;hello_packet[67:64]=STATUS_REVISION;if(DIAGNOSTICS)hello_packet[106:72]=source_debug;end endfunction
 assign stream_valid=online && (state==HELLO_SEND || state==META_SEND || state==DATA_SEND || state==STATUS_SEND);
 assign stream_data=held;
 assign read_busy=reading || state==REQUEST;
 assign read_req=state==REQUEST;
 assign read_en=(state==POP || state==DRAIN_POP) && !read_empty;
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=HELLO_SEND;held<=0;frame_id<=0;chunk<=0;pixels<=0;fill<=0;
   consumed<=0;sent<=0;idle_count<=0;read_ack_sync<=0;timeout<=0;retries<=0;reading<=0;read_role<=2;
  end else begin
   read_ack_sync<={read_ack_sync[0],read_ack};
   if(state==CHOOSE && !select_valid)idle_count<=idle_count+1'b1;else idle_count<=0;
   if(waiting)begin if(!expired)timeout<=timeout+1'b1;end else timeout<=0;
   case(state)
    HELLO_SEND:begin
     held<=hello_packet(source_fault,source_fault_recurring,available);
     if(stream_ready && held[7:0]==6)state<=HELLO_WAIT;
    end
    HELLO_WAIT:if(ack && packet[31] && packet[47:32]==16'hffff)begin
     frame_id<=packet[23:8]+1'b1;sent<=0;retries<=0;state<=CHOOSE;
    end else if(expired)state<=HELLO_SEND;
    CHOOSE:if(ack && packet[31] && packet[47:32]==16'hffff)begin
     frame_id<=packet[23:8]+1'b1;sent<=0;
    end else if(select_valid)begin
     read_role<=selected;held<=0;held[7:0]<=4;held[23:8]<=frame_id;
     held[31:24]<=8'ha0|selected;held[47:32]<=16'hfffe;
     held[87:56]<=source_sizes[selected*32 +: 32];state<=META_SEND;retries<=0;
    end else if(idle_count==RETRY_CYCLES-1)begin held<=hello_packet(source_fault,source_fault_recurring,available);held[31:24]<=0;state<=STATUS_SEND;end
    STATUS_SEND:if(stream_ready)state<=CHOOSE;
    META_SEND:if(stream_ready)state<=META_WAIT;
    META_WAIT:if(ack_frame && packet[29] && packet[47:32]==16'hfffe)begin
     state<=REQUEST;consumed<=0;fill<=0;chunk<=0;retries<=0;
    end else if(expired)begin
     if(retries==4)begin state<=HELLO_SEND;retries<=0;end
     else begin retries<=retries+1'b1;state<=META_SEND;end
    end
    REQUEST:if(read_ack_sync[1])begin reading<=1;state<=POP;end
    POP:if(!read_empty)state<=TAKE;
    TAKE:begin
     pixels[fill*24 +: 24]<=read_data[31:8];consumed<=consumed+1'b1;
     if(fill==5)begin
      held<=0;held[7:0]<=4;held[23:8]<=frame_id;
      held[31:24]<=(chunk==LAST_CHUNK?8'h40:8'h00)|read_role;
      held[47:32]<=chunk;held[175:56]<=pixels[119:0];held[199:176]<=read_data[31:8];
      fill<=0;state<=DATA_SEND;
     end else begin fill<=fill+1'b1;state<=POP;end
    end
    DATA_SEND:if(stream_ready)state<=DATA_WAIT;
    DATA_WAIT:if(ack_frame && !packet[31] && !packet[29] && packet[47:32]==chunk)begin
     retries<=0;
     if(chunk==LAST_CHUNK)begin sent[read_role]<=1;frame_id<=frame_id+1'b1;reading<=0;state<=CHOOSE;end
     else begin chunk<=chunk+1'b1;state<=POP;end
    end else if(expired)begin
     if(retries==4)begin
      retries<=0;if(consumed<FRAME_PIXELS)state<=DRAIN_POP;else begin reading<=0;state<=HELLO_SEND;end
     end else begin retries<=retries+1'b1;state<=DATA_SEND;end
    end
    DRAIN_POP:if(consumed>=FRAME_PIXELS)begin reading<=0;sent<=0;state<=HELLO_SEND;end
     else if(!read_empty)state<=DRAIN_TAKE;
    DRAIN_TAKE:begin consumed<=consumed+1'b1;state<=DRAIN_POP;end
   endcase
   if(!online)begin
    timeout<=0;retries<=0;
    // Finish any issued RAM read before restarting its FIFO. Offline drain must
    // still run its POP/TAKE states; an in-flight request remains until ACK.
    if(state==REQUEST)begin
     if(read_ack_sync[1])begin reading<=1;state<=DRAIN_POP;end
     else state<=REQUEST;
    end else if(reading && consumed<FRAME_PIXELS)begin
     if(state==POP && !read_empty)state<=DRAIN_TAKE;
     else if(state!=DRAIN_POP && state!=DRAIN_TAKE)state<=DRAIN_POP;
    end else begin state<=HELLO_SEND;sent<=0;reading<=0;held<=hello_packet(source_fault,source_fault_recurring,available);end
   end
   if(reading && !available[read_role] && state!=DRAIN_POP && state!=DRAIN_TAKE)begin
    if(consumed<FRAME_PIXELS)state<=state==POP && !read_empty?DRAIN_TAKE:DRAIN_POP;else begin reading<=0;state<=HELLO_SEND;end
   end
  end
endmodule

module media_ack_cdc(input src_clk,dst_clk,rst,input src_valid,input [127:0] src_data,output src_ready,
 output dst_valid,output reg [127:0] dst_data,input dst_ready);
 reg [127:0] held;reg request,acknowledge;reg [1:0] ack_sync;reg [2:0] req_sync;
 assign src_ready=request==ack_sync[1];
 assign dst_valid=req_sync[2]!=acknowledge;
 always @(posedge src_clk or posedge rst)
  if(rst)begin held<=0;request<=0;ack_sync<=0;end
  else begin ack_sync<={ack_sync[0],acknowledge};if(src_valid && src_ready)begin held<=src_data;request<=~request;end end
 // The held bus is stable for three destination clocks before valid rises.
 // It is safe to sample combinationally while the request remains outstanding.
 always @* dst_data=held;
 always @(posedge dst_clk or posedge rst)
  if(rst)begin req_sync<=0;acknowledge<=0;end
  else begin req_sync<={req_sync[1:0],request};if(dst_valid && dst_ready)acknowledge<=req_sync[2];end
endmodule

// A completes one image per request. Metadata stays held until the returned
// blanking acknowledgement crosses back; no pulse crosses unsynchronized.
module media_commit_cdc(input src_clk,dst_clk,rst,input src_valid,output src_ready,
 output dst_valid,input dst_ready);
 reg [2:0] valid_sync;reg acknowledged;reg [1:0] ack_sync;
 assign dst_valid=valid_sync[2] && !acknowledged;
 assign src_ready=ack_sync[1];
 always @(posedge dst_clk or posedge rst)
  if(rst)begin valid_sync<=0;acknowledged<=0;end
  else begin valid_sync<={valid_sync[1:0],src_valid};
   if(!valid_sync[2])acknowledged<=0;else if(dst_valid && dst_ready)acknowledged<=1;end
 always @(posedge src_clk or posedge rst)
  if(rst)ack_sync<=0;else ack_sync<={ack_sync[0],acknowledged};
endmodule

// Lossless four RGB888 pixels in three 32-bit words. No color bits are dropped.
// The upstream FIFO and downstream scanout both return data one clock after pop.
module rgb888_frame_unpack #(parameter FAST_WORD_READ=0,RGB444_SUPPORT=0)(
 input clk,rst,restart,input word_empty,input [31:0] word_data,output word_read,
 input pixel_read,output pixel_empty,output reg [31:0] pixel_data,input fast_mode,input rgb444);
 reg take;reg [1:0] word_index,valid;reg [2:0] pixel_index;
 reg write_bank,read_bank;reg [95:0] group0,group1;
 wire compact=RGB444_SUPPORT && rgb444;
 wire [23:0] front=read_bank?group1[23:0]:group0[23:0];
 wire [11:0] compact_pixel=pixel_index[0]?front[23:12]:front[11:0];
 wire [23:0] expanded={compact_pixel[11:8],compact_pixel[11:8],compact_pixel[7:4],compact_pixel[7:4],compact_pixel[3:0],compact_pixel[3:0]};
 // Geometry needs two full RGB888 rows per output line. Pipeline word
 // fetches only in that mode; prevent a pending third word from spilling
 // into an occupied next group. Normal mode is the exact parent protocol.
 assign word_read=(FAST_WORD_READ && fast_mode ?
  (!valid[write_bank] && (!take || word_index!=2 || !valid[!write_bank])) :
  (!take && !valid[write_bank])) && !word_empty && !restart && !rst;
 assign pixel_empty=!valid[read_bank] || restart || rst;
 always @(posedge clk or posedge rst)
  if(rst)begin take<=0;word_index<=0;pixel_index<=0;valid<=0;write_bank<=0;read_bank<=0;group0<=0;group1<=0;pixel_data<=0;end
  else if(restart)begin take<=0;word_index<=0;pixel_index<=0;valid<=0;write_bank<=0;read_bank<=0;group0<=0;group1<=0;end
  else begin
   take<=word_read;
   if(take)begin
    if(!write_bank)case(word_index)0:group0[31:0]<=word_data;1:group0[63:32]<=word_data;2:group0[95:64]<=word_data;endcase
    else case(word_index)0:group1[31:0]<=word_data;1:group1[63:32]<=word_data;2:group1[95:64]<=word_data;endcase
    if(word_index==2)begin word_index<=0;valid[write_bank]<=1;write_bank<=~write_bank;end
    else word_index<=word_index+1'b1;
   end
   if(pixel_read && !pixel_empty)begin
    pixel_data<={compact?expanded:front,8'd0};
    // Two compact pixels share the same 24-bit slice. Keep the original
    // 24-bit shift wiring, rather than adding a wide variable shifter.
    if(!compact || pixel_index[0])begin
     if(!read_bank)group0<=group0>>24;else group1<=group1>>24;
    end
    if(pixel_index==(compact?7:3))begin pixel_index<=0;valid[read_bank]<=0;read_bank<=~read_bank;end
    else pixel_index<=pixel_index+1'b1;
   end
  end
endmodule
