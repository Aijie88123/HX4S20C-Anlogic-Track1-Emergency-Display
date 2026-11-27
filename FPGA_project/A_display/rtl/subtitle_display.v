// Inactive-bank upload in net_clk; real dual-clock RAM; atomic metadata and
// frame-boundary commit in video_clk. No pixel bus is sampled across clocks.
module subtitle_display #(parameter SCREEN_W=1280,SCREEN_H=720)(
 input net_clk,net_rst,input packet_valid,input [223:0] packet,
 output ack_valid,output [223:0] ack_packet,input ack_ready,
 input video_clk,video_rst,video_vs,input emergency,
 input [11:0] x_pre,y_pre,output custom_active,custom_pixel,custom_bar);
 function [15:0] crc_byte;input [15:0] c;input [7:0] v;reg [15:0] t;integer k;begin
 t=c^{v,8'd0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_byte=t;end endfunction
 reg [1:0] state;reg uploading,bank_net,upload_bank;reg [7:0] upload_id,expected;
 reg [10:0] upload_width;reg [15:0] digest;reg [127:0] write_shift;reg [10:0] write_address;reg [2:0] write_step;reg crc_half;
 reg reply_pending,last_valid;reg [7:0] reply_status,reply_id,reply_op;
 reg [15:0] reply_index;
 reg [7:0] commit_id;reg commit_clear;
 reg meta_valid;reg [12:0] meta;wire meta_ready,meta_received;wire [12:0] video_meta;
 wire committed;wire [0:0] committed_data;reg committed_pulse;
 wire incoming=packet_valid&&packet[7:0]==18&&packet[15:8]==1&&packet[223:192]==32'h53554231;
 wire [7:0] op=packet[23:16],id=packet[31:24];wire [15:0] index=packet[47:32];
 wire duplicate=last_valid&&id==reply_id&&op==reply_op&&index==reply_index;
 assign ack_valid=reply_pending;
 assign ack_packet={32'h53554231,136'd0,reply_op,reply_index,reply_id,reply_status,8'd1,8'd19};
 task respond;input [7:0] status,rid,rop;input [15:0] idx;begin
 reply_pending<=1;reply_status<=status;reply_id<=rid;reply_op<=rop;reply_index<=idx;
 last_valid<=1;end endtask
 always @(posedge net_clk or posedge net_rst)
 if(net_rst)begin state<=0;uploading<=0;bank_net<=0;upload_bank<=1;upload_id<=0;expected<=0;upload_width<=0;digest<=16'hffff;
 write_shift<=0;write_address<=0;write_step<=0;crc_half<=0;reply_pending<=0;reply_status<=0;reply_id<=0;reply_op<=0;reply_index<=0;
 last_valid<=0;commit_id<=0;commit_clear<=0;meta_valid<=0;meta<=0;end
 else begin
  if(reply_pending&&ack_ready)reply_pending<=0;
  if(meta_valid&&meta_ready)meta_valid<=0;
  if(state==1)begin
   // One CRC byte per net clock; the 16-bit RAM write occurs on the second.
   // No throughput loss at115200baud and half the combinational CRC chain.
   digest<=crc_byte(digest,crc_half?write_shift[15:8]:write_shift[7:0]);crc_half<=~crc_half;
   if(crc_half)begin
    write_shift<=write_shift>>16;write_address<=write_address+1'b1;write_step<=write_step+1'b1;
    if(write_step==7)begin state<=0;expected<=expected+1'b1;respond(0,upload_id,8'd1,{8'd0,expected});end
   end
  end
  if(state==2&&committed)begin state<=0;bank_net<=meta[12];uploading<=0;respond(0,commit_id,commit_clear?8'd3:8'd2,commit_clear?16'd0:16'd128);end
  if(incoming&&!reply_pending)begin
   if(duplicate)begin reply_pending<=1;reply_status<=reply_status;reply_id<=id;reply_op<=op;reply_index<=index;end
   else if(state==0)case(op)
    0:if(index<16||index>1024||index[3:0]!=0)respond(10,id,op,index);
      else begin uploading<=1;upload_bank<=~bank_net;upload_id<=id;upload_width<=index[10:0];expected<=0;digest<=16'hffff;respond(0,id,op,index);end
    1:if(!uploading||id!=upload_id||index!={8'd0,expected}||expected>=128)respond(11,id,op,index);
      else begin state<=1;write_shift<=packet[191:64];write_address<={upload_bank,index[6:0],3'd0};write_step<=0;crc_half<=0;end
    2:if(!uploading||id!=upload_id||expected!=128||index!=128)respond(11,id,op,index);
      else if(digest!=packet[63:48])respond(13,id,op,index);
      else begin state<=2;meta<={upload_bank,1'b1,upload_width};meta_valid<=1;commit_id<=id;commit_clear<=0;end
    3:if(index!=0)respond(10,id,op,index);else begin state<=2;meta<={bank_net,1'b0,11'd0};meta_valid<=1;commit_id<=id;commit_clear<=1;end
    default:respond(10,id,op,index);
   endcase
   // During the bounded RAM write or VS wait a retry is ignored; the original
   // operation will reply once. It never replaces or partially commits a frame.
  end
 end
 ethernet_mailbox #(.WIDTH(13)) metadata(.src_clk(net_clk),.src_rst(net_rst),.src_valid(meta_valid),.src_data(meta),.src_ready(meta_ready),
 .dst_clk(video_clk),.dst_rst(video_rst),.dst_valid(meta_received),.dst_data(video_meta));
 ethernet_mailbox #(.WIDTH(1)) commit_ack(.src_clk(video_clk),.src_rst(video_rst),.src_valid(committed_pulse),.src_data(1'b1),.src_ready(),
 .dst_clk(net_clk),.dst_rst(net_rst),.dst_valid(committed),.dst_data(committed_data));
 reg vs_d,have_pending,active_bank,active_enable,emergency_frame;reg [12:0] pending_meta;
 reg [10:0] active_width;reg [11:0] phase;
 wire frame_start=vs_d&&!video_vs;
 wire [12:0] cycle_end=SCREEN_W+{active_width,1'b0}+13'd64;
 always @(posedge video_clk or posedge video_rst)
 if(video_rst)begin vs_d<=0;have_pending<=0;pending_meta<=0;active_bank<=0;active_enable<=0;active_width<=0;phase<=0;committed_pulse<=0;emergency_frame<=0;end
 else begin
  vs_d<=video_vs;committed_pulse<=0;
  if(meta_received)begin have_pending<=1;pending_meta<=video_meta;end
  if(frame_start)begin
   emergency_frame<=emergency;
   if(have_pending)begin active_bank<=pending_meta[12];active_enable<=pending_meta[11];active_width<=pending_meta[10:0];phase<=SCREEN_W;have_pending<=0;committed_pulse<=1;end
   else if(active_enable)phase<=phase+2>=cycle_end?12'd0:phase+12'd2;
  end
 end
 localparam NORMAL_Y=SCREEN_H-40,EMERGENCY_Y=SCREEN_H-140;
 wire [11:0] top_y=emergency_frame?EMERGENCY_Y:NORMAL_Y;
 wire [12:0] cursor={1'b0,x_pre}+{1'b0,phase};
 wire [12:0] relative_x=cursor-SCREEN_W;wire [11:0] relative_y=y_pre-top_y;
 wire [10:0] read_address={active_bank,relative_y[4:1],relative_x[10:5]};
 wire [15:0] pixels;reg [3:0] bit_select;reg hit_r,bar_r;
 always @(posedge video_clk or posedge video_rst)
 if(video_rst)begin bit_select<=0;hit_r<=0;bar_r<=0;end
 else begin
  bit_select<=relative_x[4:1];
  hit_r<=active_enable&&x_pre<SCREEN_W&&cursor>=SCREEN_W&&cursor<SCREEN_W+{active_width,1'b0}&&y_pre>=top_y&&y_pre<top_y+32;
  bar_r<=active_enable&&x_pre<SCREEN_W&&y_pre>=top_y-4&&y_pre<top_y+36;
 end
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) bitmap(
 .doa(),.dia(write_shift[15:0]),.addra(write_address),.bytea(1'b0),.bytewea(1'b0),.csa(1'b1),.wea(state==1&&crc_half),.clka(net_clk),.rsta(1'b0),.ocea(1'b1),
 .dob(pixels),.dib(16'd0),.addrb(read_address),.byteb(1'b0),.byteweb(1'b0),.csb(1'b1),.web(1'b0),.clkb(video_clk),.rstb(1'b0),.oceb(1'b1));
 assign custom_active=active_enable;
 assign custom_pixel=hit_r&&pixels[15-bit_select];
 assign custom_bar=bar_r;
endmodule
