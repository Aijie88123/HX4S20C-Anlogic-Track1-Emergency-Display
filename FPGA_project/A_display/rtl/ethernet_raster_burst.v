// Protocol V12: up to four ordinary 224-bit stream envelopes share one FCS.
// The two small byte-RAM banks collect the next batch during transmission.
// Only raster bodies wait for companions; control/TF/PCM envelopes seal early.
module ethernet_raster_burst_tx #(parameter VERSION=12,BATCH_WAIT=256)(
 input clk,rst,online,may_start,control_pending,input [20:0] message,input [7:0] extension,
 input stream_valid,input [223:0] stream_data,output stream_ready,output control_sent,
 output reg busy,output reg [3:0] nibble);
 reg [7:0] memory[0:255];
 reg [7:0] ram_q;
 reg [1:0] sealed;
 reg fill_bank,send_bank,tx_bank,collecting,seal_early,tx_stream;
 reg [2:0] count0,count1,tx_count;
 reg [6:0] fill_address;
 reg [4:0] left;
 reg [8:0] age;
 reg [223:0] shift;
 reg [9:0] position;
 reg [7:0] body_bytes;
 reg [20:0] held_message;
 reg [7:0] held_extension;
 reg [31:0] crc;
 wire [2:0] fill_count=fill_bank?count1:count0;
 wire [2:0] send_count=send_bank?count1:count0;
 wire take=stream_valid && stream_ready;
 wire launch=may_start && (control_pending || sealed[send_bank]);
 assign control_sent=launch && control_pending;
 assign stream_ready=online && !collecting && !sealed[fill_bank];
 wire finish_collect=collecting && left==1;
 wire seal=finish_collect && (fill_count==3 || seal_early) ||
   !collecting && fill_count!=0 && !sealed[fill_bank] && age==BATCH_WAIT-1 && !take;
 wire [7:0] byte_index=(position-16)>>1;
 wire [7:0] next_byte=byte_index+position[0];
 wire [7:0] read_address={tx_bank,7'd0}+(next_byte-25);
 wire [9:0] fcs_start=16+{body_bytes,1'b0};
 reg [7:0] data_byte;
 function [31:0] crc4;
 input [31:0] c;input [3:0] d;reg [31:0] t;integer k;
 begin t=c;for(k=0;k<4;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hEDB88320:0);crc4=t;end
 endfunction
 function [7:0] data_length;input [2:0] n;
 begin case(n)1:data_length=60;2:data_length=81;3:data_length=109;default:data_length=137;endcase end
 endfunction
 always @(posedge clk)begin
  if(collecting)memory[{fill_bank,fill_address}]<=shift[7:0];
  ram_q<=memory[read_address];
 end
 always @*begin
  case(byte_index)
   0,1,2,3,4,5:data_byte=8'hff;
   6:data_byte=2;7:data_byte=8'h48;8:data_byte=8'h58;9:data_byte=8'h34;10:data_byte=0;11:data_byte=8'hb1;
   12:data_byte=8'h88;13:data_byte=8'hb5;14:data_byte=8'h48;15:data_byte=8'h58;16:data_byte=VERSION;
   17:data_byte={5'd0,held_message[2:0]};18:data_byte=held_message[10:3];19:data_byte=held_message[18:11];
   20:data_byte={7'd0,held_message[19]};21:data_byte={7'd0,held_message[20]};22:data_byte=held_extension;
   23:data_byte=tx_stream?16:0;24:data_byte=tx_stream?{5'd0,tx_count}:0;
   default:data_byte=tx_stream && byte_index>=25 && byte_index<25+tx_count*28?ram_q:0;
  endcase
  if(!busy)nibble=0;
  else if(position<15)nibble=5;
  else if(position==15)nibble=13;
  else if(position>=fcs_start)nibble=~crc[3:0];
  else nibble=position[0]?data_byte[7:4]:data_byte[3:0];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin
   sealed<=0;fill_bank<=0;send_bank<=0;tx_bank<=0;collecting<=0;seal_early<=0;tx_stream<=0;
   count0<=0;count1<=0;tx_count<=0;fill_address<=0;left<=0;age<=0;shift<=0;
   busy<=0;position<=0;body_bytes<=60;held_message<=0;held_extension<=0;crc<=32'hffffffff;
  end else begin
   if(!collecting && fill_count!=0 && !sealed[fill_bank])begin if(age<BATCH_WAIT-1)age<=age+1'b1;end
   else age<=0;
   if(take)begin collecting<=1;left<=28;shift<=stream_data;seal_early<=stream_data[7:0]!=7 || stream_data[31];age<=0;end
   if(collecting)begin
    shift<=shift>>8;fill_address<=fill_address+1'b1;left<=left-1'b1;
    if(left==1)begin collecting<=0;if(fill_bank)count1<=count1+1'b1;else count0<=count0+1'b1;end
   end
   if(seal)begin sealed[fill_bank]<=1;fill_bank<=~fill_bank;fill_address<=0;age<=0;end
   if(launch)begin
    busy<=1;position<=0;crc<=32'hffffffff;held_message<=message;held_extension<=extension;
    tx_stream<=!control_pending;tx_bank<=send_bank;tx_count<=send_count;body_bytes<=control_pending?60:data_length(send_count);
   end else if(busy)begin
    if(position>=16 && position<fcs_start)crc<=crc4(crc,nibble);
    else if(position>=fcs_start)crc<=crc>>4;
    if(position==fcs_start+7)begin
     busy<=0;position<=0;
     if(tx_stream)begin sealed[tx_bank]<=0;if(tx_bank)count1<=0;else count0<=0;send_bank<=~send_bank;end
    end else position<=position+1'b1;
   end
   // No partially collected old-session packet is transmitted after link loss.
   if(!online && !busy)begin sealed<=0;fill_bank<=0;send_bank<=0;collecting<=0;count0<=0;count1<=0;fill_address<=0;age<=0;end
  end
endmodule

// Peer B -> A, with CRC-qualified publication and mailbox backpressure.
// Four banks absorb the short-frame burst that can follow a long frame.
// Both ordinary V12 frames and the type-16 batch container enter the same
// bounded bank queue, preserving stream ordering across TF/control/raster.
module ethernet_raster_burst_rx #(parameter VERSION=12)(
 input clk,rst,input [3:0] nibble,input valid,error,output_ready,
 output reg packet_valid,output reg [20:0] message,output reg [7:0] extension,
 output [223:0] stream_data);
 reg [7:0] memory[0:511];reg [7:0] ram_q;
 reg [3:0] ready;
 reg [1:0] write_bank,read_bank;reg in_frame,half,header_ok,can_store,burst;
 reg [3:0] preamble,low_nibble;
 reg [7:0] bytes,body_bytes,kind;
 reg [2:0] chunks,out_chunk,state;reg [2:0] counts[0:3];
 reg [20:0] staged;reg [7:0] ext;reg [20:0] messages[0:3];reg [7:0] extensions[0:3];integer k;
 reg [31:0] crc;
 reg [8:0] read_address;
 reg [4:0] out_byte;
 reg [223:0] shift;
 assign stream_data=shift;
 wire [7:0] data_byte={nibble,low_nibble};
 wire store=in_frame && valid && half && can_store &&
  (burst?bytes>=25 && bytes<25+chunks*28:bytes>=23 && bytes<51);
 wire [8:0] write_address={write_bank,7'd0}+(bytes-(burst?25:23));
 wire [2:0] out_count=counts[read_bank];
 reg expected_ok;
 function [31:0] crc4;
 input [31:0] c;input [3:0] d;reg [31:0] t;integer k;
 begin t=c;for(k=0;k<4;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hEDB88320:0);crc4=t;end
 endfunction
 function [7:0] data_length;input [2:0] n;
 begin case(n)1:data_length=60;2:data_length=81;3:data_length=109;default:data_length=137;endcase end
 endfunction
 always @*begin
  case(bytes)
   0,1,2,3,4,5:expected_ok=data_byte==8'hff;
   6:expected_ok=data_byte==2;7:expected_ok=data_byte==8'h48;8:expected_ok=data_byte==8'h58;
   9:expected_ok=data_byte==8'h34;10:expected_ok=data_byte==0;11:expected_ok=data_byte==8'hb1;
   12:expected_ok=data_byte==8'h88;13:expected_ok=data_byte==8'hb5;14:expected_ok=data_byte==8'h48;
   15:expected_ok=data_byte==8'h58;16:expected_ok=data_byte==VERSION;
   17:expected_ok=data_byte[7:3]==0;20,21:expected_ok=data_byte[7:1]==0;
   22:expected_ok=data_byte[7:6]==0;
   23:expected_ok=data_byte==16 || data_byte==15 || data_byte==12 || data_byte==9 || data_byte==11 ||
       data_byte==0 || data_byte==2 || data_byte==3 || data_byte==4 || data_byte==6 || data_byte==7;
   24:expected_ok=burst?(data_byte>=1 && data_byte<=4):
       kind==15 || kind==12 ? data_byte==1 : kind>=9 && kind<=11 || kind>=4 && kind<=7 ? 1'b1 :
       kind==3 ? data_byte[7:6]==0 && data_byte[5:4]!=3 : data_byte[7:1]==0;
   default:expected_ok=burst?(bytes<25+chunks*28 || bytes>=body_bytes || data_byte==0):
       bytes<51 || bytes>=60 || data_byte==0;
  endcase
 end
 always @(posedge clk)begin
  if(store)memory[write_address]<=data_byte;
  ram_q<=memory[read_address];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin
   ready<=0;write_bank<=0;read_bank<=0;in_frame<=0;half<=0;header_ok<=0;can_store<=0;burst<=0;
   preamble<=0;low_nibble<=0;bytes<=0;body_bytes<=60;kind<=0;chunks<=1;for(k=0;k<4;k=k+1)begin counts[k]<=0;messages[k]<=0;extensions[k]<=0;end
   out_chunk<=0;state<=0;staged<=0;ext<=0;crc<=32'hffffffff;
   read_address<=0;out_byte<=0;shift<=0;packet_valid<=0;message<=0;extension<=0;
  end else begin
   packet_valid<=0;
   if(!valid)begin
    if(in_frame && !half && bytes==body_bytes+4 && header_ok && crc==32'hdebb20e3 && !error && can_store)begin
     ready[write_bank]<=1;
     counts[write_bank]<=chunks;messages[write_bank]<=staged;extensions[write_bank]<=ext;
     write_bank<=write_bank+1'b1;
    end
    preamble<=0;in_frame<=0;half<=0;bytes<=0;header_ok<=1;crc<=32'hffffffff;
   end else if(!in_frame)begin
    if(error)preamble<=0;
    else if(nibble==5)begin if(preamble!=15)preamble<=preamble+1'b1;end
    else if(nibble==13 && preamble==15)begin
     in_frame<=1;half<=0;bytes<=0;crc<=32'hffffffff;header_ok<=1;staged<=0;ext<=0;
     can_store<=!ready[write_bank];burst<=0;chunks<=1;kind<=0;body_bytes<=60;
    end else preamble<=0;
   end else begin
    if(error)header_ok<=0;
    crc<=crc4(crc,nibble);half<=~half;
    if(!half)low_nibble<=nibble;
    else begin
     if(!expected_ok || bytes>=body_bytes+4)header_ok<=0;
     if(bytes!=255)bytes<=bytes+1'b1;
     case(bytes)
      17:staged[2:0]<=data_byte[2:0];18:staged[10:3]<=data_byte;
      19:staged[18:11]<=data_byte;20:staged[19]<=data_byte[0];21:staged[20]<=data_byte[0];22:ext<=data_byte;
      23:begin kind<=data_byte;burst<=data_byte==16;end
      24:if(burst)begin chunks<=data_byte[2:0];body_bytes<=data_length(data_byte[2:0]);end
     endcase
    end
   end
   case(state)
    0:if(ready[read_bank])begin read_address<={read_bank,7'd0};out_byte<=0;out_chunk<=0;state<=1;end
    1:state<=2;
    2:begin
     shift<={ram_q,shift[223:8]};
     if(out_byte==27)state<=3;
     else begin out_byte<=out_byte+1'b1;read_address<=read_address+1'b1;state<=1;end
    end
    3:if(output_ready)begin packet_valid<=1;message<=messages[read_bank];extension<=extensions[read_bank];state<=4;end
    4:begin
     if(out_chunk+1==out_count)begin ready[read_bank]<=0;read_bank<=read_bank+1'b1;state<=0;end
     else begin out_chunk<=out_chunk+1'b1;out_byte<=0;read_address<=read_address+1'b1;state<=1;end
    end
   endcase
  end
endmodule
