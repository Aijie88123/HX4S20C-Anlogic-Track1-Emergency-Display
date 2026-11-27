// B keeps four replayable compressed packets in flight. ACKs are cumulative
// because A validates/enqueues packets strictly in raster-index order. The
// final ACK still means a complete frame has reached the display boundary.
module raster_map_window_sender #(
 parameter PIXELS=230400,RETRY_CYCLES=5000000,DATA_RETRY_CYCLES=50000,
 parameter ALLOW_ANIMATION=0,ANIMATION_PIXELS=PIXELS,NATIVE_VGA=0,WINDOW_LOG2=2,FAST_SOURCE=0
)(input clk,rst,online,frame_valid,input [1:0] frame_event,
 output frame_consumed,input frame_animation,output current_animation,
 input packet_valid,input [223:0] packet,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 output read_req,read_en,read_busy,input read_ack,read_empty,input [31:0] read_data);
 localparam HELLO=0,HELLO_WAIT=1,CHOOSE=2,META=3,META_WAIT=4,ENCODE=5,DRAIN=6,RELEASE=7;
 localparam REQUEST=0,POP=1,TAKE=2,PIXEL=3,FINAL_RUN=4,PUSH=5,DONE=6,DRAIN_POP=7,DRAIN_TAKE=8;
 localparam TX_IDLE=0,TX_FETCH=1,TX_LATCH=2,TX_SEND=3;
 reg [2:0] phase;reg [3:0] state,resume;reg [1:0] tx_state;
 reg [15:0] id,base_index,build_index,send_index,sent_limit,final_index,tx_index;
 reg [1:0] event_q,ack_sync;reg [WINDOW_LOG2+2:0] tx_address;reg [2:0] store_word;reg animation_q,encoding_done,reading;
 reg [223:0] held,control_packet,tx_packet;reg [31:0] ram_q;
 // Seven 32-bit words per slot; publication waits for the final word.
 (* ram_style="bram" *) reg [31:0] replay[0:(1<<(WINDOW_LOG2+3))-1]; /* fehdl force_ram=1, ram_style="bram" */
 reg [31:0] word_q;reg half,have_run;reg [15:0] colour;reg [8:0] length;
 reg [2:0] fill,retries;reg [19:0] words,pixels;
 reg [22:0] timeout,source_timeout,control_timeout;
 reg [31:0] prefetch[0:3];reg [1:0] prefetch_head,prefetch_tail;
 reg [2:0] prefetch_count;reg prefetch_pending;
 wire [15:0] built_count=build_index-base_index;
 wire storing=online && phase==ENCODE && state==PUSH && built_count<(1<<WINDOW_LOG2);
 wire push=storing && store_word==6;
 wire [15:0] ack_distance=packet[47:32]-base_index;
 wire ack=packet_valid && packet[7:0]==8 && packet[23:8]==id && packet[25:24]==event_q;
 wire final_ack=encoding_done && packet[47:32]==final_index;
 wire data_ack=phase==ENCODE && ack && !packet[31] && !packet[29] &&
  ack_distance<(sent_limit-base_index) && packet[30]==final_ack;
 wire tx_pending=(tx_index-base_index)<built_count;
 wire [19:0] frame_pixels=animation_q?ANIMATION_PIXELS:PIXELS;
 wire [3:0] after_pixel=pixels==frame_pixels-1?FINAL_RUN:(half?(FAST_SOURCE && prefetch_count!=0?PIXEL:POP):PIXEL);
 wire wait_source=phase==ENCODE && (state==REQUEST || state==POP && read_empty) || phase==DRAIN && state==DRAIN_POP;
 wire long_ack=encoding_done && base_index==final_index;
 assign current_animation=animation_q;
 assign read_req=phase==ENCODE && state==REQUEST;
 wire fast_read=phase==ENCODE && reading && words<frame_pixels/2 && prefetch_count+{2'd0,prefetch_pending}<4;
 assign read_en=(FAST_SOURCE?fast_read || phase==DRAIN && state==DRAIN_POP:phase==ENCODE && state==POP || phase==DRAIN && state==DRAIN_POP) && !read_empty;
 // Four registered source words decouple the SDRAM/pair-reader latency from
 // the one-pixel-per-cycle RLE loop. Requests count at the physical FIFO edge,
 // so cancellation drains exactly the unread source words, including prefetch.
 wire prefetch_take=FAST_SOURCE && phase==ENCODE && prefetch_count!=0 &&
   (state==POP || state==PIXEL && half && pixels!=frame_pixels-1);
 always @(posedge clk)if(FAST_SOURCE && prefetch_pending)prefetch[prefetch_tail]<=read_data;
 always @(posedge clk or posedge rst)
  if(rst)begin prefetch_head<=0;prefetch_tail<=0;prefetch_count<=0;prefetch_pending<=0;end
  else if(phase!=ENCODE)begin prefetch_head<=0;prefetch_tail<=0;prefetch_count<=0;prefetch_pending<=0;end
  else begin
   prefetch_pending<=FAST_SOURCE && read_en;
   case({prefetch_pending,prefetch_take})2'b10:prefetch_count<=prefetch_count+1'b1;2'b01:prefetch_count<=prefetch_count-1'b1;endcase
   if(prefetch_pending)prefetch_tail<=prefetch_tail+1'b1;
   if(prefetch_take)prefetch_head<=prefetch_head+1'b1;
  end
 assign read_busy=reading || read_req;
 assign frame_consumed=phase==RELEASE;
 assign stream_valid=online && (phase==HELLO || phase==META || phase==ENCODE && tx_state==TX_SEND && tx_pending);
 assign stream_data=phase==HELLO?{176'd0,16'hffff,8'h80,16'd0,8'd7}:phase==META?control_packet:tx_packet;
 always @(posedge clk)begin
  if(storing)replay[{build_index[WINDOW_LOG2-1:0],store_word}]<=held[31:0];
  ram_q<=replay[tx_address];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin
   phase<=HELLO;state<=REQUEST;resume<=POP;tx_state<=TX_IDLE;
   id<=0;base_index<=0;build_index<=0;send_index<=0;sent_limit<=0;final_index<=0;tx_index<=0;
   event_q<=0;ack_sync<=0;tx_address<=0;store_word<=0;animation_q<=0;encoding_done<=0;reading<=0;
   held<=0;control_packet<=0;tx_packet<=0;word_q<=0;half<=0;have_run<=0;colour<=0;length<=0;
   fill<=0;retries<=0;words<=0;pixels<=0;timeout<=0;source_timeout<=0;control_timeout<=0;
  end else begin
   ack_sync<={ack_sync[0],read_ack};
   if(phase==HELLO_WAIT || phase==META_WAIT)control_timeout<=control_timeout+1'b1;else control_timeout<=0;
   if(wait_source)source_timeout<=source_timeout+1'b1;else source_timeout<=0;
   if(phase==ENCODE && sent_limit!=base_index)timeout<=timeout+1'b1;else timeout<=0;
   if(FAST_SOURCE && read_en)words<=words+1'b1;
   case(phase)
    HELLO:if(stream_ready)phase<=HELLO_WAIT;
    HELLO_WAIT:if(packet_valid && packet[7:0]==8 && packet[31] && packet[47:32]==16'hffff)begin
     id<=packet[23:8]+1'b1;phase<=CHOOSE;
    end else if(control_timeout==RETRY_CYCLES-1)phase<=HELLO;
    CHOOSE:if(frame_valid)begin
     control_packet<=0;control_packet[7:0]<=7;control_packet[23:8]<=id;
     control_packet[31:24]<=8'ha0|frame_event|((ALLOW_ANIMATION && frame_animation)?8'h10:0);
     control_packet[47:32]<=16'hfffe;control_packet[71:56]<=ALLOW_ANIMATION && frame_animation && ANIMATION_PIXELS==57856?320:640;control_packet[87:72]<=NATIVE_VGA?480:(ALLOW_ANIMATION && frame_animation && ANIMATION_PIXELS==57856?180:360);
     animation_q<=ALLOW_ANIMATION && frame_animation;event_q<=frame_event;retries<=0;phase<=META;
    end
    META:if(stream_ready)phase<=META_WAIT;
    META_WAIT:if(ack && packet[29] && packet[47:32]==16'hfffe)begin
     phase<=ENCODE;state<=REQUEST;tx_state<=TX_IDLE;store_word<=0;words<=0;pixels<=0;
     base_index<=0;build_index<=0;send_index<=0;sent_limit<=0;final_index<=0;
     fill<=0;have_run<=0;half<=0;held<=0;encoding_done<=0;retries<=0;timeout<=0;
    end else if(control_timeout==RETRY_CYCLES-1)begin
     if(retries==4)phase<=RELEASE;else begin retries<=retries+1'b1;phase<=META;end
    end
    ENCODE:begin
     case(state)
      REQUEST:if(ack_sync[1])begin reading<=1;state<=POP;end
      POP:if(FAST_SOURCE)begin
       if(prefetch_count!=0)begin word_q<=prefetch[prefetch_head];half<=0;state<=PIXEL;end
      end else if(!read_empty)state<=TAKE;
      TAKE:begin word_q<=read_data;words<=words+1'b1;half<=0;state<=PIXEL;end
      PIXEL:begin
       pixels<=pixels+1'b1;word_q<=word_q>>16;half<=~half;state<=after_pixel;
       if(prefetch_take)begin word_q<=prefetch[prefetch_head];half<=0;end
       if(!have_run)begin have_run<=1;colour<=word_q[15:0];length<=1;end
       else if(colour==word_q[15:0] && length<256)length<=length+1'b1;
       else begin
        case(fill)
       3'd0:held[56 +:24]<={length[7:0]-8'd1,colour};
       3'd1:held[80 +:24]<={length[7:0]-8'd1,colour};
       3'd2:held[104 +:24]<={length[7:0]-8'd1,colour};
       3'd3:held[128 +:24]<={length[7:0]-8'd1,colour};
       3'd4:held[152 +:24]<={length[7:0]-8'd1,colour};
       3'd5:held[176 +:24]<={length[7:0]-8'd1,colour};
       3'd6:held[200 +:24]<={length[7:0]-8'd1,colour};
      endcase colour<=word_q[15:0];length<=1;
        if(fill==6)begin
         held[7:0]<=7;held[23:8]<=id;held[31:24]<=event_q|(animation_q?8'h10:0);
         held[47:32]<=build_index;held[55:48]<=7;fill<=0;state<=PUSH;resume<=after_pixel;
        end else fill<=fill+1'b1;
       end
      end
      FINAL_RUN:begin
       case(fill)
       3'd0:held[56 +:24]<={length[7:0]-8'd1,colour};
       3'd1:held[80 +:24]<={length[7:0]-8'd1,colour};
       3'd2:held[104 +:24]<={length[7:0]-8'd1,colour};
       3'd3:held[128 +:24]<={length[7:0]-8'd1,colour};
       3'd4:held[152 +:24]<={length[7:0]-8'd1,colour};
       3'd5:held[176 +:24]<={length[7:0]-8'd1,colour};
       3'd6:held[200 +:24]<={length[7:0]-8'd1,colour};
      endcase held[7:0]<=7;held[23:8]<=id;
       held[31:24]<=8'h40|event_q|(animation_q?8'h10:0);held[47:32]<=build_index;
       held[55:48]<=fill+1'b1;state<=PUSH;resume<=DONE;
      end
      PUSH:if(storing)begin
       held<=held>>32;
       if(push)begin
       store_word<=0;
       if(resume==DONE)begin final_index<=build_index;encoding_done<=1;end
       build_index<=build_index+1'b1;held<=0;fill<=0;state<=resume;
       end else store_word<=store_word+1'b1;
      end
     endcase
     case(tx_state)
      TX_IDLE:if((send_index-base_index)>built_count)send_index<=base_index;
       else if(send_index!=build_index)begin tx_address<={send_index[WINDOW_LOG2-1:0],3'd0};tx_index<=send_index;tx_state<=TX_FETCH;end
      TX_FETCH:tx_state<=TX_LATCH;
      TX_LATCH:begin
       tx_packet<={ram_q,tx_packet[223:32]};
       if(tx_address[2:0]==6)tx_state<=TX_SEND;
       else begin tx_address<=tx_address+1'b1;tx_state<=TX_FETCH;end
      end
      TX_SEND:if(!tx_pending)begin tx_state<=TX_IDLE;send_index<=base_index;end
       else if(stream_ready)begin
        send_index<=tx_index+1'b1;
        if((tx_index-base_index)>=(sent_limit-base_index))sent_limit<=tx_index+1'b1;
        tx_state<=TX_IDLE;
       end
     endcase
     if(data_ack)begin
      base_index<=packet[47:32]+1'b1;timeout<=0;retries<=0;
      if(final_ack)begin reading<=0;phase<=RELEASE;id<=id+1'b1;tx_state<=TX_IDLE;end
     end else if(sent_limit!=base_index && timeout==(long_ack?RETRY_CYCLES:DATA_RETRY_CYCLES)-1)begin
      timeout<=0;tx_state<=TX_IDLE;
      if(retries==4)begin phase<=reading && words<frame_pixels/2?DRAIN:RELEASE;state<=DRAIN_POP;retries<=0;end
      else begin retries<=retries+1'b1;send_index<=base_index;end
     end
     if(wait_source && source_timeout==RETRY_CYCLES-1)begin
      phase<=reading && words<frame_pixels/2?DRAIN:RELEASE;state<=DRAIN_POP;tx_state<=TX_IDLE;source_timeout<=0;
     end
    end
    DRAIN:case(state)
     DRAIN_POP:if(words>=frame_pixels/2 || source_timeout==RETRY_CYCLES-1)begin reading<=0;phase<=RELEASE;end
      else if(!read_empty)state<=DRAIN_TAKE;
     DRAIN_TAKE:begin if(!FAST_SOURCE)words<=words+1'b1;state<=DRAIN_POP;end
    endcase
    RELEASE:begin reading<=0;if(!frame_valid)phase<=HELLO;end
   endcase
   if(!online)begin
    retries<=0;timeout<=0;tx_state<=TX_IDLE;store_word<=0;
    if(reading && words<frame_pixels/2)begin
     phase<=DRAIN;
     if(phase==ENCODE && state==POP && !read_empty)state<=DRAIN_TAKE;
     else if(phase!=DRAIN)state<=DRAIN_POP;
    end else begin reading<=0;phase<=frame_valid?RELEASE:HELLO;end
   end
  end
endmodule

// A validates compressed packets before acknowledging them. A bounded FIFO
// lets the existing pixel decoder run while the next packets cross Ethernet.
module raster_map_window_receiver #(parameter PIXELS=230400,ALLOW_ANIMATION=0,ANIMATION_PIXELS=PIXELS,NATIVE_VGA=0,DECODE_ACK=0,WINDOW_LOG2=2)(
 input clk,rst,online,packet_valid,input [223:0] packet,
 output ack_valid,output [223:0] ack_packet,input ack_ready,
 output write_cancel,write_req,input write_ack,write_full,write_done_toggle,
 output write_en,output [31:0] write_data,output commit_valid,input commit_ready,
 output [1:0] commit_event,output commit_animation);
 reg context_valid;reg [15:0] frame_id,next_index;reg [1:0] event_q;reg animation_q;
 reg [19:0] accepted_pixels;reg [WINDOW_LOG2:0] count;reg [WINDOW_LOG2-1:0] head,tail,rd_address;
 (* ram_style="bram_32k" *) reg [223:0] queue[0:(1<<WINDOW_LOG2)-1]; /* fehdl force_ram=1, ram_style="bram_32k" */
 reg [223:0] ram_q,head_packet,validation_packet;
 reg [1:0] qstate;reg validating;reg [167:0] validation_runs;reg [3:0] validation_left;reg [11:0] validation_sum;
 reg front_valid,have_nonfinal;reg [15:0] nonfinal_index;reg [223:0] front_packet;
 wire inner_valid,inner_ready,inner_idle;wire [223:0] inner_packet;
 wire [7:0] flags=packet[31:24];
 wire hello=packet_valid && packet[7:0]==7 && flags==8'h80 && packet[47:32]==16'hffff;
 wire meta=packet_valid && packet[7:0]==7 && flags[7] && flags[5] && !flags[6] && flags[3:2]==0 &&
  (!flags[4] || ALLOW_ANIMATION) && packet[47:32]==16'hfffe && (NATIVE_VGA?packet[71:56]==640 && packet[87:72]==480:(flags[4] && ANIMATION_PIXELS==57856?packet[71:56]==320 && packet[87:72]==180:packet[71:56]==640 && packet[87:72]==360));
 function newer;input [15:0] a,b;reg [15:0] d;begin d=a-b;newer=d!=0&&!d[15];end endfunction
 wire new_meta=meta && (!context_valid || newer(packet[23:8],frame_id));
 wire body=packet_valid && packet[7:0]==7 && !flags[7] && !flags[5] && flags[3:2]==0 &&
  (!flags[4] || ALLOW_ANIMATION) && packet[55:48]>0 && packet[55:48]<=7 && context_valid &&
  packet[23:8]==frame_id && flags[1:0]==event_q && flags[4]==animation_q;
 wire duplicate=body && (next_index-packet[47:32])!=0 && (next_index-packet[47:32])<=(1<<WINDOW_LOG2);
 wire duplicate_final=duplicate && flags[6] && count==0 && qstate==0;
 wire control=hello || meta || duplicate_final;
 wire feed=qstate==3 && inner_ready && !control;
 wire push=validating && validation_left==0 && count<(1<<WINDOW_LOG2) && accepted_pixels+validation_sum<=(animation_q?ANIMATION_PIXELS:PIXELS) &&
  validation_packet[30]==(accepted_pixels+validation_sum==(animation_q?ANIMATION_PIXELS:PIXELS));
 wire decode_ack,decode_ack_ready;wire [223:0] decode_packet;
 wire control_ack=decode_ack && (decode_packet[31] || decode_packet[29] || decode_packet[30]);
 wire [223:0] inner_input=control?packet:head_packet;
 assign ack_valid=control_ack || front_valid;
 assign ack_packet=control_ack?decode_packet:front_packet;
 assign decode_ack_ready=control_ack?ack_ready:1'b1;
 raster_map_receiver #(.PIXELS(PIXELS),.ALLOW_ANIMATION(ALLOW_ANIMATION),.ANIMATION_PIXELS(ANIMATION_PIXELS),.NATIVE_VGA(NATIVE_VGA)) decoder(
  .clk(clk),.rst(rst),.online(online),.packet_valid(control || feed),.packet(inner_input),
  .ack_valid(decode_ack),.ack_packet(decode_packet),.ack_ready(decode_ack_ready),
  .write_cancel(write_cancel),.write_req(write_req),.write_ack(write_ack),.write_full(write_full),.write_done_toggle(write_done_toggle),
  .write_en(write_en),.write_data(write_data),.commit_valid(commit_valid),.commit_ready(commit_ready),
  .commit_event(commit_event),.commit_animation(commit_animation),.data_ready(inner_ready),.frame_idle(inner_idle));
 function [223:0] response;input [15:0] seq,num;input [7:0] f;
  begin response=0;response[7:0]=8;response[23:8]=seq;response[31:24]=f;response[47:32]=num;end endfunction
 always @(posedge clk)begin
  if(push)queue[tail]<=validation_packet;
  ram_q<=queue[rd_address];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin
   context_valid<=0;frame_id<=0;next_index<=0;event_q<=0;animation_q<=0;accepted_pixels<=0;
   count<=0;head<=0;tail<=0;rd_address<=0;qstate<=0;validating<=0;validation_packet<=0;
   validation_runs<=0;validation_left<=0;validation_sum<=0;head_packet<=0;front_valid<=0;front_packet<=0;have_nonfinal<=0;nonfinal_index<=0;
  end else begin
   if(front_valid && !control_ack && ack_ready)front_valid<=0;
   case({push,feed})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
   case(qstate)
    0:if(count!=0)begin rd_address<=head;qstate<=1;end
    1:qstate<=2;
    2:begin head_packet<=ram_q;qstate<=3;end
    3:if(feed)begin head<=head+1'b1;qstate<=0;end
   endcase
   if(body && !validating)begin
    if(packet[47:32]==next_index)begin
     validation_packet<=packet;validation_runs<=packet[223:56];validation_left<=packet[51:48];validation_sum<=0;validating<=1;
    end else if(duplicate && !flags[6] && have_nonfinal)begin front_valid<=1;front_packet<=response(frame_id,nonfinal_index,{6'd0,event_q});end
   end
   if(validating)begin
    if(validation_left!=0)begin
     validation_sum<=validation_sum+{4'd0,validation_runs[23:16]}+1'b1;
     validation_runs<=validation_runs>>24;validation_left<=validation_left-1'b1;
    end else begin
     validating<=0;
     if(push)begin
      tail<=tail+1'b1;next_index<=next_index+1'b1;accepted_pixels<=accepted_pixels+validation_sum;
      if(!DECODE_ACK && !validation_packet[30])begin have_nonfinal<=1;nonfinal_index<=next_index;front_valid<=1;front_packet<=response(frame_id,next_index,{6'd0,event_q});end
     end
    end
   end
   // Consumed-packet credits bound the entire burst window, including the
   // packet currently expanding into SDRAM; queue capacity cannot be overrun.
   if(DECODE_ACK && decode_ack && !control_ack)begin
    have_nonfinal<=1;nonfinal_index<=decode_packet[47:32];front_valid<=1;front_packet<=decode_packet;
   end
   if(new_meta)begin
    context_valid<=1;frame_id<=packet[23:8];event_q<=flags[1:0];animation_q<=flags[4];next_index<=0;accepted_pixels<=0;
    count<=0;head<=0;tail<=0;qstate<=0;validating<=0;front_valid<=0;have_nonfinal<=0;
   end
   if(!online)begin context_valid<=0;count<=0;head<=0;tail<=0;qstate<=0;validating<=0;front_valid<=0;end
  end
endmodule
