// Fixed 64-byte Ethernet frame, 7-byte preamble, SFD, CRC32/FCS and padding.
// 100M RGMII repeats each nibble on both edges of the 25MHz clock.
module ethernet_frame_tx #(parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0,RAW_TF_VERSION=7)(
 input clk,rst,start,input [20:0] message,input [7:0] extension,input [223:0] stream_data,
 output reg busy,output reg [3:0] nibble);
 reg [7:0] position;
 reg [20:0] held;reg [7:0] held_extension;
 localparam STREAM_BITS=RAW_TF?224:(BOARD_B?224:128);
 reg [STREAM_BITS-1:0] held_stream;
 wire [223:0] stream_bytes={{(224-STREAM_BITS){1'b0}},held_stream};
 reg [31:0] crc;
 wire [6:0] byte_index=(position-8'd16)>>1;
 reg [7:0] data_byte;
 function [31:0] crc4;
 input [31:0] c;input [3:0] d;reg [31:0] t;integer k;
 begin t=c;for(k=0;k<4;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hEDB88320:32'd0);crc4=t;end
 endfunction
 always @* begin
  case(byte_index)
   0,1,2,3,4,5:data_byte=8'hff;
   6:data_byte=8'h02;7:data_byte=8'h48;8:data_byte=8'h58;9:data_byte=8'h34;10:data_byte=0;
   11:data_byte=BOARD_B?8'hb1:8'ha1;
   12:data_byte=8'h88;13:data_byte=8'hb5;
   14:data_byte=8'h48;15:data_byte=8'h58;16:data_byte=RAW_TF?RAW_TF_VERSION:(RASTER?6:(MEDIA?5:(MAP?4:(STREAM?3:(EXTENDED?2:1)))));
   17:data_byte={5'd0,held[2:0]};18:data_byte=held[10:3];
   19:data_byte=held[18:11];20:data_byte={7'd0,held[19]};
   21:data_byte={7'd0,held[20]};
   22:data_byte=EXTENDED?held_extension:8'd0;
   // Constant byte addresses avoid an arithmetic index feeding a wide mux.
   default:begin
    data_byte=0;
    if(STREAM)case(byte_index)
     23:data_byte=stream_bytes[0 +: 8];
     24:data_byte=stream_bytes[8 +: 8];
     25:data_byte=stream_bytes[16 +: 8];
     26:data_byte=stream_bytes[24 +: 8];
     27:data_byte=stream_bytes[32 +: 8];
     28:data_byte=stream_bytes[40 +: 8];
     29:data_byte=stream_bytes[48 +: 8];
     30:data_byte=stream_bytes[56 +: 8];
     31:data_byte=stream_bytes[64 +: 8];
     32:data_byte=stream_bytes[72 +: 8];
     33:data_byte=stream_bytes[80 +: 8];
     34:data_byte=stream_bytes[88 +: 8];
     35:data_byte=stream_bytes[96 +: 8];
     36:data_byte=stream_bytes[104 +: 8];
     37:data_byte=stream_bytes[112 +: 8];
     38:data_byte=stream_bytes[120 +: 8];
     39:if(STREAM_BITS==224)data_byte=stream_bytes[128 +: 8];
     40:if(STREAM_BITS==224)data_byte=stream_bytes[136 +: 8];
     41:if(STREAM_BITS==224)data_byte=stream_bytes[144 +: 8];
     42:if(STREAM_BITS==224)data_byte=stream_bytes[152 +: 8];
     43:if(STREAM_BITS==224)data_byte=stream_bytes[160 +: 8];
     44:if(STREAM_BITS==224)data_byte=stream_bytes[168 +: 8];
     45:if(STREAM_BITS==224)data_byte=stream_bytes[176 +: 8];
     46:if(STREAM_BITS==224)data_byte=stream_bytes[184 +: 8];
     47:if(STREAM_BITS==224)data_byte=stream_bytes[192 +: 8];
     48:if(STREAM_BITS==224)data_byte=stream_bytes[200 +: 8];
     49:if(STREAM_BITS==224)data_byte=stream_bytes[208 +: 8];
     50:if(STREAM_BITS==224)data_byte=stream_bytes[216 +: 8];
     default:data_byte=0;
    endcase
   end
  endcase
  if(!busy)nibble=0;
  else if(position<15)nibble=5;
  else if(position==15)nibble=13;
  else if(position>=136)nibble=~crc[3:0];
  else nibble=position[0]?data_byte[7:4]:data_byte[3:0];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin busy<=0;position<=0;held<=0;held_extension<=0;held_stream<=0;crc<=32'hffffffff;end
  else if(!busy)begin
   if(start)begin busy<=1;position<=0;held<=message;held_extension<=EXTENDED?extension:8'd0;held_stream<=STREAM?stream_data[STREAM_BITS-1:0]:0;crc<=32'hffffffff;end
  end else begin
   if(position>=16 && position<136)crc<=crc4(crc,nibble);
   else if(position>=136)crc<=crc>>4;
   if(position==143)begin busy<=0;position<=0;end else position<=position+1'b1;
  end
endmodule
