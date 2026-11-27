// B renders an immutable 128x64 particle atlas.  Each texel contains a 5-bit
// reveal phase and a 3-bit glow. A only enlarges/colours/composites the atlas.
// The upload is background, stop-and-wait, idempotent and never gates pictures.
module particle_atlas_sender #(parameter RETRY_CYCLES=250000,MOTION=0,MOTION_PERIOD=416667)(
 input clk,rst,online,enabled,packet_valid,input [223:0] packet,input [8:0] motion_phase,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 output ready);
 localparam BUILD=0,SEND=1,WAIT_ACK=2,FINISHED=3,MOTION_SEND=4;
 reg [2:0] state;reg [8:0] index;reg [3:0] byte_index;
 reg [127:0] payload;reg [22:0] timer;
 wire [12:0] address={index,byte_index};
 function [7:0] render_texel;
 input [12:0] a;
 reg [6:0] px;reg [5:0] py;reg [3:0] tx;reg [2:0] ty,lx,ly,cx,cy,dx,dy;
 reg [7:0] h;reg [3:0] distance;reg [2:0] glow;reg [4:0] phase;
 begin
  px=a[6:0];py=a[12:7];tx=px[6:3];ty=py[5:3];lx=px[2:0];ly=py[2:0];
  h={tx,ty,1'b1}^{ty,tx,1'b0}^{tx[1:0],ty,tx[3:1]}^8'hb5;
  cx=3'd2+{1'b0,h[1:0]};cy=3'd2+{1'b0,h[3:2]};
  dx=lx>cx?lx-cx:cx-lx;dy=ly>cy?ly-cy:cy-ly;
  distance={1'b0,dx}+{1'b0,dy};glow=0;
  // Arcing flow lanes bias the original seeded spark field.  Shift/add
  // trajectory needs no divider, multiplier or extra frame buffer.
  if(h[7:6]!=0)begin
   case(distance)0:glow=7;1:glow=5;2:glow=2;default:glow=0;endcase
  end
  if ((py+((px>70?px-70:70-px)>>1)>=36 && py+((px>70?px-70:70-px)>>1)<=39) ||
      (py+((px>70?px-70:70-px)>>2)>=42 && py+((px>70?px-70:70-px)>>2)<=43))begin
   if(glow<2)glow=2;
   if(lx==cx && glow<6)glow=6;
  end
  phase={h[4:1],h[7]}^5'h13;
  if(phase<2)phase=2;else if(phase>29)phase=29;
  render_texel={phase,glow};
 end endfunction
 function [47:0] row_motion;input [8:0] t;
 integer i;reg [3:0] wave;reg [5:0] offset;
 begin
  row_motion=0;
  for(i=0;i<8;i=i+1)begin
   wave=t[6:3]+i*2;
   offset=t[6:1]+(wave[3]?15-wave:wave);
   row_motion[i*6 +:6]=offset;
  end
 end endfunction
 assign ready=state==FINISHED || state==MOTION_SEND;
 assign stream_valid=online && enabled && (state==SEND || state==MOTION_SEND);
 assign stream_data=state==MOTION_SEND?{119'd0,row_motion(motion_phase),motion_phase,16'd0,16'hffff,8'd1,8'd12}:{48'd0,payload,16'd0,7'd0,index,8'd1,8'd12};
 always @(posedge clk or posedge rst)
  if(rst)begin state<=BUILD;index<=0;byte_index<=0;payload<=0;timer<=0;end
  else if(!online)begin state<=BUILD;index<=0;byte_index<=0;timer<=0;end
  else case(state)
   BUILD:if(enabled)begin
    payload[byte_index*8 +:8]<=render_texel(address);
    if(byte_index==15)begin byte_index<=0;state<=SEND;end else byte_index<=byte_index+1'b1;
   end
   SEND:if(stream_ready && enabled)begin state<=WAIT_ACK;timer<=0;end
   WAIT_ACK:begin
    if(packet_valid && packet[7:0]==13 && packet[15:8]==1 && packet[31:16]=={7'd0,index})begin
     timer<=0;
     if(index==511)state<=FINISHED;else begin index<=index+1'b1;state<=BUILD;end
    end else if(timer==RETRY_CYCLES-1)begin state<=SEND;timer<=0;end
    else timer<=timer+1'b1;
   end
   FINISHED:if(MOTION && enabled)begin
    if(timer==MOTION_PERIOD-1)begin timer<=0;state<=MOTION_SEND;end else timer<=timer+1'b1;
   end
   MOTION_SEND:if(stream_ready && enabled)begin timer<=0;state<=FINISHED;end
   default:state<=FINISHED;
  endcase
endmodule

module particle_atlas_receiver #(parameter MOTION=0)(
 input net_clk,rst,online,packet_valid,input [223:0] packet,
 output reg ack_valid,output [223:0] ack_packet,input ack_ready,
 input video_clk,input [12:0] read_address,output reg [7:0] read_code,
 output ready,output [56:0] motion);
 reg motion_valid;reg [56:0] motion_net;
 ethernet_mailbox #(.WIDTH(57)) u_motion(.src_clk(net_clk),.src_rst(rst),.src_valid(motion_valid),.src_data(motion_net),.src_ready(),
  .dst_clk(video_clk),.dst_rst(rst),.dst_valid(),.dst_data(motion));
 reg [7:0] atlas [0:8191]; /* fehdl force_ram=1, ram_style="bram" */
 reg complete,writing;reg [9:0] next_index;reg [8:0] held_index,ack_index;
 reg [3:0] byte_index;reg [127:0] payload;reg [1:0] complete_sync;
 wire [15:0] incoming_index=packet[31:16];
 assign ack_packet={192'd0,7'd0,ack_index,8'd1,8'd13};
 assign ready=complete_sync[1];
 // Deliberate separate synchronous read/write ports; only a complete atlas
 // is ever enabled by the compositor. No live texture overwrites on retries.
 always @(posedge net_clk)
  if(writing)atlas[{held_index,byte_index}]<=payload[7:0];
 always @(posedge video_clk)read_code<=atlas[read_address];
 always @(posedge video_clk or posedge rst)
  if(rst)complete_sync<=0;else complete_sync<={complete_sync[0],complete};
 always @(posedge net_clk or posedge rst)
  if(rst)begin
   motion_valid<=0;motion_net<=0;complete<=0;writing<=0;next_index<=0;held_index<=0;ack_index<=0;
   byte_index<=0;payload<=0;ack_valid<=0;
  end else begin
   motion_valid<=0;
   if(ack_valid && ack_ready)ack_valid<=0;
   if(!online)begin
    ack_valid<=0;writing<=0;byte_index<=0;
    if(!complete)next_index<=0;
   end else if(writing)begin
    payload<=payload>>8;
    if(byte_index==15)begin
     writing<=0;ack_index<=held_index;ack_valid<=1;
     next_index<={1'b0,held_index}+1'b1;
     if(held_index==511)complete<=1;
    end else byte_index<=byte_index+1'b1;
   end else if(MOTION && packet_valid && packet[7:0]==12 && packet[15:8]==1 && incoming_index==16'hffff && complete)begin
    motion_net<=packet[104:48];motion_valid<=1;
   end else if(packet_valid && packet[7:0]==12 && packet[15:8]==1 && incoming_index<512)begin
    if(complete || incoming_index<next_index)begin ack_index<=incoming_index[8:0];ack_valid<=1;end
    else if(incoming_index==next_index)begin
     held_index<=incoming_index[8:0];payload<=packet[175:48];byte_index<=0;writing<=1;
    end
   end
  end
endmodule
