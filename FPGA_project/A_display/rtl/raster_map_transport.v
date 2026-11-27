// Protocol-v6 rendered map transport, type 7/8. Seven RGB565 runs per frame.
// Each run is {length_minus_one[7:0], colour[15:0]}; order is raster order.
module raster_map_sender #(parameter PIXELS=230400,RETRY_CYCLES=5000000,ALLOW_ANIMATION=0)(
 input clk,rst,online,frame_valid,input [1:0] frame_event,
 output frame_consumed,input frame_animation,output current_animation,
 input packet_valid,input [223:0] packet,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 output read_req,read_en,read_busy,input read_ack,read_empty,input [31:0] read_data);
 localparam HELLO=0,HELLO_WAIT=1,CHOOSE=2,META=3,META_WAIT=4,REQUEST=5,POP=6,TAKE=7,
  PIXEL=8,FINAL_RUN=9,SEND=10,WAIT_ACK=11,RELEASE=12,DRAIN_POP=13,DRAIN_TAKE=14;
 reg animation_q;assign current_animation=animation_q;
 reg [3:0] state,resume;reg [223:0] held;reg [15:0] id,index;reg [1:0] event_q;
 reg [31:0] word_q;reg half,have_run,reading;reg [15:0] colour;reg [8:0] length;
 reg [2:0] fill;reg [19:0] words,pixels;reg [22:0] timeout;reg [2:0] retries;reg [1:0] ack_sync;
 wire expired=timeout==RETRY_CYCLES-1;
 wire ack=packet_valid && packet[7:0]==8;
 wire matching=ack && packet[23:8]==id && packet[25:24]==event_q;
 wire waiting=state==HELLO_WAIT || state==META_WAIT || state==WAIT_ACK || state==REQUEST || state==POP || state==DRAIN_POP;
 wire [3:0] after_pixel=(pixels==PIXELS-1)?FINAL_RUN:(half?POP:PIXEL);
 assign read_busy=reading || state==REQUEST;
 assign read_req=state==REQUEST;
 assign read_en=(state==POP || state==DRAIN_POP) && !read_empty;
 assign frame_consumed=state==RELEASE;
 assign stream_valid=online && (state==HELLO || state==META || state==SEND);
 assign stream_data=state==HELLO?{176'd0,16'hffff,8'h80,16'd0,8'd7}:held;
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=HELLO;resume<=POP;held<=0;id<=0;index<=0;event_q<=0;word_q<=0;half<=0;
   animation_q<=0;have_run<=0;reading<=0;colour<=0;length<=0;fill<=0;words<=0;pixels<=0;timeout<=0;retries<=0;ack_sync<=0;
  end else begin
   ack_sync<={ack_sync[0],read_ack};
   if(waiting)begin if(!expired)timeout<=timeout+1'b1;end else timeout<=0;
   case(state)
    HELLO:if(stream_ready)state<=HELLO_WAIT;
    HELLO_WAIT:if(ack && packet[31] && packet[47:32]==16'hffff)begin id<=packet[23:8]+1'b1;state<=CHOOSE;end
     else if(expired)state<=HELLO;
    CHOOSE:if(frame_valid)begin
     held<=0;held[7:0]<=7;held[23:8]<=id;held[31:24]<=8'ha0|frame_event|((ALLOW_ANIMATION && frame_animation)?8'h10:0);animation_q<=ALLOW_ANIMATION && frame_animation;
     held[47:32]<=16'hfffe;held[71:56]<=640;held[87:72]<=360;event_q<=frame_event;state<=META;retries<=0;
    end
    META:if(stream_ready)state<=META_WAIT;
    META_WAIT:if(matching && packet[29] && packet[47:32]==16'hfffe)begin
     state<=REQUEST;words<=0;pixels<=0;index<=0;fill<=0;have_run<=0;half<=0;retries<=0;held<=0;
    end else if(expired)begin if(retries==4)state<=RELEASE;else begin retries<=retries+1'b1;state<=META;end end
    REQUEST:if(ack_sync[1])begin reading<=1;state<=POP;end else if(expired)state<=RELEASE;
    POP:if(!read_empty)state<=TAKE;else if(expired)begin reading<=0;state<=RELEASE;end
    TAKE:begin word_q<=read_data;words<=words+1'b1;half<=0;state<=PIXEL;end
    PIXEL:begin
     // A consumed colour is retained as the seed of the next run when full.
     pixels<=pixels+1'b1;word_q<=word_q>>16;half<=~half;state<=after_pixel;
     if(!have_run)begin have_run<=1;colour<=word_q[15:0];length<=1;end
     else if(colour==word_q[15:0] && length<256)length<=length+1'b1;
     else begin
      held[56+fill*24 +:24]<={length[7:0]-8'd1,colour};colour<=word_q[15:0];length<=1;
      if(fill==6)begin
       held[7:0]<=7;held[23:8]<=id;held[31:24]<={6'd0,event_q}|(animation_q?8'h10:0);held[47:32]<=index;held[55:48]<=7;
       fill<=0;state<=SEND;resume<=after_pixel;
      end else fill<=fill+1'b1;
     end
    end
    FINAL_RUN:begin
     held[56+fill*24 +:24]<={length[7:0]-8'd1,colour};held[7:0]<=7;held[23:8]<=id;
     held[31:24]<=8'h40|event_q|(animation_q?8'h10:0);held[47:32]<=index;held[55:48]<=fill+1'b1;
     state<=SEND;resume<=RELEASE;
    end
    SEND:if(stream_ready)state<=WAIT_ACK;
    WAIT_ACK:if(matching && !packet[31] && !packet[29] && packet[47:32]==index && packet[30]==held[30])begin
     held<=0;fill<=0;index<=index+1'b1;retries<=0;state<=resume;
     if(resume==RELEASE)begin reading<=0;id<=id+1'b1;end
    end else if(expired)begin
     if(retries==4)begin retries<=0;state<=words<PIXELS/2?DRAIN_POP:RELEASE;end
     else begin retries<=retries+1'b1;state<=SEND;end
    end
    RELEASE:begin reading<=0;if(!frame_valid)state<=HELLO;end
    DRAIN_POP:if(words>=PIXELS/2 || expired)begin reading<=0;state<=RELEASE;end else if(!read_empty)state<=DRAIN_TAKE;
    DRAIN_TAKE:begin words<=words+1'b1;state<=DRAIN_POP;end
   endcase
   if(!online)begin
    if(state!=DRAIN_POP)timeout<=0;retries<=0;
    if(state==REQUEST)begin reading<=0;state<=frame_valid?RELEASE:HELLO;end
    else if(reading && words<PIXELS/2)begin
     if(state==POP && !read_empty)state<=DRAIN_TAKE;
     else if(state!=DRAIN_POP && state!=DRAIN_TAKE)state<=DRAIN_POP;
    end else begin reading<=0;state<=frame_valid?RELEASE:HELLO;end
   end
  end
endmodule

module raster_map_receiver #(parameter PIXELS=230400,ALLOW_ANIMATION=0,ANIMATION_PIXELS=PIXELS,NATIVE_VGA=0)(
 input clk,rst,online,packet_valid,input [223:0] packet,
 output reg ack_valid,output reg [223:0] ack_packet,input ack_ready,
 output write_cancel,output reg write_req,input write_ack,write_full,write_done_toggle,
 output write_en,output [31:0] write_data,
 output commit_valid,input commit_ready,output reg [1:0] commit_event,output reg commit_animation,
 output reg data_ready,output frame_idle);
 localparam IDLE=0,RESET_WRITER=1,SETUP=2,DATA=3,VALIDATE=4,EMIT=5,FINISH=6,COMMIT=7;
 reg [2:0] state;reg [4:0] reset_wait;reg [15:0] id,next_index,current_index,last_id,last_index;
 reg [1:0] last_event;reg last_valid,last_animation;reg [2:0] done_sync;reg [1:0] ack_sync;reg finish_epoch;
 reg [167:0] runs,validation_runs;reg [3:0] validation_left;reg [2:0] runs_left;
 reg [11:0] sum;reg [19:0] position;reg packet_end;reg [8:0] remain;reg [15:0] colour,low;
 reg half;
 wire [15:0] received_id=packet[23:8],received_index=packet[47:32];wire [7:0] flags=packet[31:24];
 function newer;input [15:0] a,b;reg [15:0] d;begin d=a-b;newer=d!=0&&!d[15];end endfunction
 function [223:0] response;input [15:0] seq,num;input [7:0] f;
  begin response=0;response[7:0]=8;response[23:8]=seq;response[31:24]=f;response[47:32]=num;end endfunction
 assign write_cancel=state==RESET_WRITER || !online;
 wire packed_emit=position[2:0]==2 || position[2:0]==5 || position[2:0]==7;
 reg [27:0] packed_carry;wire [11:0] c444={colour[15:12],colour[10:7],colour[4:1]};
 wire [31:0] packed_word=position[2:0]==2?{c444[7:0],packed_carry[23:0]}:
                            position[2:0]==5?{c444[3:0],packed_carry[27:0]}:{c444,packed_carry[19:0]};
 assign write_en=state==EMIT && remain!=0 && (NATIVE_VGA?packed_emit:half) && !write_full;
 assign write_data=NATIVE_VGA?packed_word:{colour,low};assign commit_valid=state==COMMIT;assign frame_idle=state==IDLE;
 always @(posedge clk or posedge rst)
  if(rst)begin done_sync<=0;ack_sync<=0;end
  else begin done_sync<={done_sync[1:0],write_done_toggle};ack_sync<={ack_sync[0],write_ack};end
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;reset_wait<=0;id<=0;next_index<=0;current_index<=0;last_id<=0;last_index<=0;last_event<=0;last_valid<=0;last_animation<=0;commit_animation<=0;
   write_req<=0;ack_valid<=0;ack_packet<=0;commit_event<=0;finish_epoch<=0;data_ready<=0;
   runs<=0;validation_runs<=0;validation_left<=0;runs_left<=0;sum<=0;position<=0;packet_end<=0;remain<=0;colour<=0;low<=0;half<=0;packed_carry<=0;
  end else begin
   data_ready<=0;
   if(ack_valid&&ack_ready)ack_valid<=0;
   if(!online)begin state<=IDLE;write_req<=0;ack_valid<=0;end
   else begin
    case(state)
     RESET_WRITER:if(reset_wait==31)begin state<=SETUP;write_req<=1;finish_epoch<=done_sync[2];end else reset_wait<=reset_wait+1'b1;
     SETUP:if(ack_sync[1])begin state<=DATA;data_ready<=1;write_req<=0;ack_valid<=1;ack_packet<=response(id,16'hfffe,8'h20|commit_event);end
     DATA:data_ready<=1;
     VALIDATE:if(validation_left!=0)begin
      sum<=sum+{4'd0,validation_runs[23:16]}+1'b1;validation_runs<=validation_runs>>24;validation_left<=validation_left-1'b1;
     end else if(position+sum<=(commit_animation?ANIMATION_PIXELS:PIXELS) && packet_end==(position+sum==(commit_animation?ANIMATION_PIXELS:PIXELS)))begin remain<=0;state<=EMIT;end
     else begin state<=DATA;data_ready<=1;end
     EMIT:if(remain==0)begin
      if(runs_left!=0)begin colour<=runs[15:0];remain<={1'b0,runs[23:16]}+1'b1;runs<=runs>>24;runs_left<=runs_left-1'b1;end
      else begin
       next_index<=next_index+1'b1;
       if(packet_end)state<=FINISH;
       else begin state<=DATA;data_ready<=1;ack_valid<=1;ack_packet<=response(id,current_index,{6'd0,commit_event});end
      end
     end else if(!(NATIVE_VGA?packed_emit:half) || !write_full)begin
      if(NATIVE_VGA)case(position[2:0])
       0:packed_carry<={16'd0,c444};1:packed_carry[23:12]<=c444;
       2:packed_carry<={24'd0,c444[11:8]};3:packed_carry[15:4]<=c444;
       4:packed_carry[27:16]<=c444;5:packed_carry<={20'd0,c444[11:4]};
       6:packed_carry[19:8]<=c444;7:packed_carry<=0;
      endcase
      if(!half)low<=colour;half<=~half;remain<=remain-1'b1;position<=position+1'b1;
     end
     FINISH:if(done_sync[2]!=finish_epoch)state<=COMMIT;
     COMMIT:if(commit_ready)begin
      state<=IDLE;last_valid<=1;last_id<=id;last_index<=current_index;last_event<=commit_event;last_animation<=commit_animation;
      ack_valid<=1;ack_packet<=response(id,current_index,8'h40|commit_event);
     end
    endcase
    if(packet_valid && packet[7:0]==7)begin
     if(flags==8'h80 && received_index==16'hffff)begin
      ack_valid<=1;ack_packet<=response(state!=IDLE?id:(last_valid?last_id:16'hffff),16'hffff,8'h80);
     end else if(flags[7] && flags[5] && !flags[6] && flags[3:2]==0 && (!flags[4] || ALLOW_ANIMATION) && received_index==16'hfffe && (NATIVE_VGA?packet[71:56]==640 && packet[87:72]==480:(flags[4] && ANIMATION_PIXELS==57856?packet[71:56]==320 && packet[87:72]==180:packet[71:56]==640 && packet[87:72]==360)))begin
      if(state!=IDLE && received_id==id && commit_event==flags[1:0] && commit_animation==flags[4])begin
       if(state!=RESET_WRITER && state!=SETUP)begin ack_valid<=1;ack_packet<=response(id,16'hfffe,8'h20|commit_event);end
      end else if((!last_valid||newer(received_id,last_id)) && (state==IDLE||newer(received_id,id)))begin
       state<=RESET_WRITER;data_ready<=0;reset_wait<=0;write_req<=0;id<=received_id;commit_event<=flags[1:0];commit_animation<=flags[4];
       next_index<=0;position<=0;half<=0;
      end
     end else if(!flags[7] && !flags[5] && flags[3:2]==0 && (!flags[4] || ALLOW_ANIMATION) && packet[55:48]>0 && packet[55:48]<=7)begin
      if(state==DATA && received_id==id && flags[1:0]==commit_event && flags[4]==commit_animation)begin
       if(received_index==next_index)begin
        runs<=packet[223:56];validation_runs<=packet[223:56];validation_left<=packet[51:48];
        runs_left<=packet[50:48];sum<=0;current_index<=received_index;packet_end<=flags[6];state<=VALIDATE;data_ready<=0;
       end else if(next_index!=0 && received_index==next_index-1'b1)begin ack_valid<=1;ack_packet<=response(id,received_index,{6'd0,commit_event});end
      end else if(state==IDLE && last_valid && received_id==last_id && received_index==last_index && flags[1:0]==last_event && flags[4]==last_animation && flags[6])begin
       ack_valid<=1;ack_packet<=response(last_id,last_index,8'h40|last_event);
      end
     end
    end
   end
  end
endmodule
