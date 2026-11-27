// ANIM01: 240x135/40 frames/113ms; ANIM02: 192x108/84 frames/54ms.
// The first read retains its legacy length until the complete FIFO read drains. No GIF/LZW in the FPGA.
// Carrier slot 5: 40 blocks of 5632 SDRAM words, each burst aligned.
// Per block: 4 header words, 16 RGB888 palette words, 5400 6-index words, padding.
// Expand to the existing 640x360 RGB565 complete-frame transport.
module b_animation_cache #(parameter FRAMES=40,STALL_CYCLES=2500000)(
 input clk,rst,enabled,input [6:0] frame_index,input frame_consumed,
 input raster_req,raster_en,output raster_ack,raster_empty,output [31:0] raster_data,
 output storage_req,storage_en,storage_busy,input storage_ack,storage_empty,input [31:0] storage_data,
 output reg fault,output reg dense_mode);
 localparam IDLE=0,REQUEST=1,POP=2,TAKE=3,READY=4;
 reg [2:0] state;reg [12:0] count;reg [1:0] ack_sync;reg bad_header;
 reg [$clog2(STALL_CYCLES+1)-1:0] stall_count;
 wire memory_wait=state==REQUEST || state==POP || state==TAKE;
 reg [6:0] selected_frame;reg selected_dense,header_dense;reg [12:0] selected_words;
 reg [23:0] indices[0:5399];reg [15:0] palette[0:15];
 reg [23:0] sampled_word;reg [2:0] sampled_nibble;
 reg [12:0] pointer,row_start;reg [2:0] nibble;
 reg [8:0] x,y;reg [2:0] xphase;reg [3:0] yphase;
 wire [3:0] colour_index=(sampled_word>>(sampled_nibble*4));
 wire [15:0] colour=palette[colour_index];
 assign raster_data={colour,colour};
 assign raster_ack=state==READY;
 assign raster_empty=state!=READY;
 assign storage_req=state==REQUEST;
 assign storage_en=state==POP && !storage_empty;
 assign storage_busy=state==REQUEST || state==POP || state==TAKE;
 // Synchronous, single write and single read inference for block RAM.
 always @(posedge clk)begin
  if(state==TAKE && count>=20 && count<(selected_dense?3476:5420))indices[count-20]<=storage_data[31:8];
  if(state==TAKE && count>=4 && count<20)
   palette[count-4]<={storage_data[31:27],storage_data[23:18],storage_data[15:11]};
  if(raster_en && state==READY)begin sampled_word<=indices[pointer];sampled_nibble<=nibble;end
 end
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;count<=0;ack_sync<=0;bad_header<=0;fault<=0;selected_frame<=0;stall_count<=0;dense_mode<=0;selected_dense<=0;header_dense<=0;selected_words<=5632;
   pointer<=0;row_start<=0;nibble<=0;x<=0;y<=0;xphase<=0;yphase<=0;
  end else begin
   ack_sync<={ack_sync[0],storage_ack};
   if(!memory_wait || storage_en || state==TAKE || state==REQUEST && ack_sync[1])stall_count<=0;
   else stall_count<=stall_count+1'b1;
   case(state)
    IDLE:if(enabled && raster_req && !fault)begin
     state<=REQUEST;selected_frame<=frame_index;selected_dense<=dense_mode;selected_words<=dense_mode?3584:5632;header_dense<=dense_mode;count<=0;bad_header<=0;
     pointer<=0;row_start<=0;nibble<=0;x<=0;y<=0;xphase<=0;yphase<=0;
    end
    REQUEST:if(ack_sync[1])state<=POP;
    POP:if(!storage_empty)state<=TAKE;
    TAKE:begin
     case(count)
      0:if(storage_data[31:8]!=24'h414e49)bad_header<=1;
      1:begin header_dense<=storage_data[31:8]==24'h4d3032;
       if(storage_data[31:8]!=24'h4d3031 && storage_data[31:8]!=24'h4d3032)bad_header<=1;end
      2:if(storage_data[31:24]!=selected_frame || storage_data[23:16]!=(header_dense?84:FRAMES) || storage_data[15:8]!=(header_dense?54:113))bad_header<=1;
      3:if(storage_data[31:8]!=(header_dense?24'h0c006c:24'h0f0087))bad_header<=1;
     endcase
     if(count==selected_words-1)begin
      fault<=bad_header;state<=bad_header?IDLE:READY;if(!bad_header)dense_mode<=header_dense;
     end else begin count<=count+1'b1;state<=POP;end
    end
    READY:begin
     if(raster_en)begin
      // floor(x*3/4) over source pairs; floor(y*3/8) over output rows.
      if(x==319)begin
       x<=0;xphase<=0;nibble<=0;y<=y+1'b1;
       if(dense_mode)begin
        if(yphase>=7)begin yphase<=yphase-7;row_start<=row_start+13'd32;pointer<=row_start+13'd32;end
        else begin yphase<=yphase+3;pointer<=row_start;end
       end else begin
        yphase<=(yphase+3)&7;
        if(yphase>=5)begin row_start<=row_start+13'd40;pointer<=row_start+13'd40;end
        else pointer<=row_start;
       end
      end else begin
       x<=x+1'b1;
       if(dense_mode)xphase<=xphase>=2?xphase-2:xphase+3;
       else xphase<=(xphase+3)&3;
       if(dense_mode?xphase>=2:xphase!=0)begin
        if(nibble==5)begin nibble<=0;pointer<=pointer+1'b1;end else nibble<=nibble+1'b1;
       end
      end
     end
     if(frame_consumed)state<=IDLE;
    end
   endcase
   if(memory_wait && stall_count==STALL_CYCLES-1)begin state<=IDLE;fault<=1;stall_count<=0;end
  end
endmodule
