// v10 projected-triangle packets. A computes XYZ camera projection; B stores
// an immutable scene, then performs depth-tested pixel rendering locally.
// Packet: kind14, rev1, frame16, triangle8, flags8, colour16, 3*(x12,y12,iz16),
// event2, yaw6, zoom2, no_path1, camera_mode2. Upper reserved bits are zero.
module mesh3d_packet_sender #(parameter RETRY_CYCLES=250000)(
 input clk,rst,online,input triangle_valid,input [223:0] triangle,
 output triangle_ready,input packet_valid,input [223:0] packet,
 output stream_valid,output [223:0] stream_data,input stream_ready);
 localparam IDLE=0,SEND=1,WAIT_ACK=2,RETIRE=3;
 reg [1:0] state;reg [223:0] held;reg [21:0] timer;
 assign triangle_ready=state==RETIRE && triangle_valid && triangle[39:16]==held[39:16];
 assign stream_valid=online && state==SEND;
 assign stream_data=held;
 always @(posedge clk or posedge rst)
  if(rst)begin state<=IDLE;held<=0;timer<=0;end
  else if(!online)begin state<=IDLE;timer<=0;end
  else case(state)
   IDLE:if(triangle_valid)begin held<=triangle;state<=SEND;end
   SEND:if(stream_ready)begin state<=WAIT_ACK;timer<=0;end
   WAIT_ACK:if(packet_valid && packet[7:0]==15 && packet[15:8]==1 && packet[39:16]==held[39:16] && packet[223:40]==0)state<=RETIRE;
    else if(timer==RETRY_CYCLES-1)begin state<=SEND;timer<=0;end else timer<=timer+1'b1;
   RETIRE:state<=IDLE;
   default:state<=IDLE;
  endcase
endmodule

module mesh3d_packet_receiver(
 input net_clk,render_clk,rst,online,packet_valid,input [223:0] packet,
 output reg ack_valid,output [223:0] ack_packet,input ack_ready,
 input [10:0] read_address,output reg [15:0] read_data,
 output mesh_valid,output [7:0] mesh_count,output [15:0] mesh_id,
 output [12:0] mesh_meta,input release_toggle);
 reg [15:0] memory[0:2047]; /* fehdl force_ram=1, ram_style="bram" */
 reg writing,available,have_id;reg [3:0] word_index;
 reg [6:0] held_index;reg [7:0] next_index,count;
 reg [15:0] frame_id,ack_frame;reg [7:0] ack_index;
 reg [223:0] held;reg [12:0] meta;
 reg [2:0] release_sync;reg release_epoch;
 reg [7:0] last_index;reg [15:0] last_frame;reg have_last;reg held_last;
 wire [15:0] incoming_id=packet[31:16];wire [7:0] incoming_index=packet[39:32];
 wire [15:0] id_delta=incoming_id-frame_id;
 wire new_start=incoming_index==0 && !available && !writing && (!have_id || (id_delta!=0 && !id_delta[15]));
 wire same_next=have_id && incoming_id==frame_id && incoming_index==next_index && !available;
 wire duplicate=have_last && incoming_id==last_frame && incoming_index==last_index;
 wire valid_body=packet[7:0]==14 && packet[15:8]==1 && incoming_index<128 && packet[223:197]==0;
 assign ack_packet={184'd0,ack_index,ack_frame,8'd1,8'd15};
 always @(posedge net_clk)if(writing)memory[{held_index,word_index}]<=held[15:0];
 always @(posedge render_clk)read_data<=memory[read_address];
 wire [37:0] delivered;
 ethernet_mailbox #(.WIDTH(38)) u_publish(.src_clk(net_clk),.src_rst(rst),.src_valid(1'b1),
  .src_data({available,count,frame_id,meta}),.src_ready(),.dst_clk(render_clk),.dst_rst(rst),.dst_valid(),.dst_data(delivered));
 assign {mesh_valid,mesh_count,mesh_id,mesh_meta}=delivered;
 always @(posedge net_clk or posedge rst)
  if(rst)begin
   writing<=0;available<=0;have_id<=0;word_index<=0;held_index<=0;next_index<=0;count<=0;
   frame_id<=0;ack_frame<=0;ack_index<=0;held<=0;meta<=0;ack_valid<=0;
   release_sync<=0;release_epoch<=0;last_index<=0;last_frame<=0;have_last<=0;
  end else begin
   release_sync<={release_sync[1:0],release_toggle};
   if(ack_valid && ack_ready)ack_valid<=0;
   if(!online)begin writing<=0;available<=0;have_id<=0;next_index<=0;ack_valid<=0;have_last<=0;release_epoch<=release_sync[2];end
   else begin
    if(release_sync[2]!=release_epoch)begin release_epoch<=release_sync[2];available<=0;have_id<=0;next_index<=0;end
    if(writing)begin
     held<=held>>16;
     if(word_index==13)begin
      writing<=0;last_index<={1'b0,held_index};last_frame<=frame_id;have_last<=1;
      ack_frame<=frame_id;ack_index<={1'b0,held_index};ack_valid<=1;next_index<={1'b0,held_index}+1'b1;
      if(held_last)begin available<=1;count<={1'b0,held_index}+1'b1;end
     end else word_index<=word_index+1'b1;
    end else if(packet_valid && valid_body)begin
     if(duplicate)begin ack_frame<=incoming_id;ack_index<=incoming_index;ack_valid<=1;end
     else if(new_start || same_next)begin
      if(incoming_index==0)begin frame_id<=incoming_id;have_id<=1;meta<=packet[196:184];end
      held<=packet;held_index<=incoming_index[6:0];word_index<=0;writing<=1;
     end
    end
   end
  end
 // Separate latch keeps LAST stable while the payload is serially shifted.
 always @(posedge net_clk or posedge rst)
  if(rst)held_last<=0;
  else if(!writing && packet_valid && valid_body && !duplicate && (new_start||same_next))held_last<=packet[40];
endmodule
