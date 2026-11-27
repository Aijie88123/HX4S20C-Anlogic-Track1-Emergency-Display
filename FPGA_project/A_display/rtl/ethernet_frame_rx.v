// Accept only peer MAC, experimental EtherType 88B5, HX/version1, exact length,
// correct FCS and no PHY receive error. Nothing is published before frame end.
module ethernet_frame_rx #(parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0,RAW_TF_VERSION=7,SUBTITLE=0)(
 input clk,rst,input [3:0] nibble,input valid,error,
 output reg packet_valid,output reg [20:0] message,output reg [7:0] extension,output [223:0] stream_data);
 reg [3:0] preamble,low_nibble;
 reg in_frame,half,header_ok;
 reg [6:0] bytes;
 reg [31:0] crc;
 reg [20:0] staged;reg [7:0] staged_extension;
 localparam STREAM_BITS=RAW_TF?224:(BOARD_B?128:224);
 reg [STREAM_BITS-1:0] staged_stream;
 integer stream_byte;
 assign stream_data={{(224-STREAM_BITS){1'b0}},staged_stream};
 wire [7:0] data_byte={nibble,low_nibble};
 reg expected_ok;
 function [31:0] crc4;
 input [31:0] c;input [3:0] d;reg [31:0] t;integer k;
 begin t=c;for(k=0;k<4;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hEDB88320:32'd0);crc4=t;end
 endfunction
 always @* begin
  case(bytes)
   0,1,2,3,4,5:expected_ok=(data_byte==8'hff);
   6:expected_ok=(data_byte==8'h02);7:expected_ok=(data_byte==8'h48);
   8:expected_ok=(data_byte==8'h58);9:expected_ok=(data_byte==8'h34);10:expected_ok=(data_byte==0);
   11:expected_ok=(data_byte==(BOARD_B?8'ha1:8'hb1));
   12:expected_ok=(data_byte==8'h88);13:expected_ok=(data_byte==8'hb5);
   14:expected_ok=(data_byte==8'h48);15:expected_ok=(data_byte==8'h58);16:expected_ok=(data_byte==(RAW_TF?RAW_TF_VERSION:(RASTER?6:(MEDIA?5:(MAP?4:(STREAM?3:(EXTENDED?2:1)))))));
   17:expected_ok=(data_byte[7:3]==0);20,21:expected_ok=(data_byte[7:1]==0);
   22:expected_ok=!EXTENDED || ((BOARD_B && RAW_TF && RAW_TF_VERSION>=9)?!data_byte[7]:((BOARD_B && !(RAW_TF && RAW_TF_VERSION>=8)) ? (data_byte[7:5]==0) : (data_byte[7:6]==0)));
   23:expected_ok=(SUBTITLE && RAW_TF && RAW_TF_VERSION==12 && data_byte==(BOARD_B?19:18)) || (RAW_TF && RAW_TF_VERSION>=10 && data_byte==(BOARD_B?14:15)) || (RAW_TF && RAW_TF_VERSION>=9 && data_byte==(BOARD_B?13:12)) || (RAW_TF && (BOARD_B?data_byte==10:(data_byte==9 || data_byte==11))) || !STREAM || data_byte==0 || data_byte==(BOARD_B?1:2) || (MAP && !BOARD_B && data_byte==3) || (RASTER && data_byte==(BOARD_B?8:7)) || (MEDIA && (BOARD_B?data_byte==5:(data_byte==4 || data_byte==6)));
   24:expected_ok=(SUBTITLE && RAW_TF && RAW_TF_VERSION==12 && (staged_stream[7:0]==18 || staged_stream[7:0]==19) && data_byte==1) || (RAW_TF && RAW_TF_VERSION>=10 && (staged_stream[7:0]==14 || staged_stream[7:0]==15) && data_byte==1) || (RAW_TF && RAW_TF_VERSION>=9 && (staged_stream[7:0]==12 || staged_stream[7:0]==13) && data_byte==1) || (RAW_TF && staged_stream[7:0]>=9 && staged_stream[7:0]<=11) || !STREAM || ((MEDIA && staged_stream[7:0]>=4 && staged_stream[7:0]<=6) || (RASTER && staged_stream[7:0]>=7 && staged_stream[7:0]<=8)) || ((MAP && !BOARD_B && staged_stream[7:0]==3)?(data_byte[7:6]==0 && data_byte[5:4]!=3):(data_byte[7:1]==0));
   default:expected_ok=!STREAM || bytes<23+STREAM_BITS/8 || bytes>=60 || data_byte==0;
  endcase
 end
 always @(posedge clk or posedge rst)
  if(rst)begin packet_valid<=0;message<=0;extension<=0;staged_extension<=0;staged_stream<=0;preamble<=0;low_nibble<=0;in_frame<=0;half<=0;header_ok<=0;bytes<=0;crc<=32'hffffffff;staged<=0;end
  else begin
   packet_valid<=0;
   if(!valid)begin
    if(in_frame && !half && bytes==64 && header_ok && crc==32'hdebb20e3 && !error)begin message<=staged;extension<=staged_extension;packet_valid<=1;end
    preamble<=0;in_frame<=0;half<=0;bytes<=0;header_ok<=1;crc<=32'hffffffff;
   end else if(!in_frame)begin
    if(error)preamble<=0;
    else if(nibble==5)begin if(preamble!=15)preamble<=preamble+1'b1;end
    else if(nibble==13 && preamble==15)begin in_frame<=1;half<=0;bytes<=0;crc<=32'hffffffff;header_ok<=1;staged<=0;staged_extension<=0;staged_stream<=0;end
    else preamble<=0;
   end else begin
    if(error)header_ok<=0;
    crc<=crc4(crc,nibble);half<=~half;
    if(!half)low_nibble<=nibble;
    else begin
     if(!expected_ok || bytes>=64)header_ok<=0;
     if(bytes!=127)bytes<=bytes+1'b1;
     // Decode fixed addresses directly; no wide variable part-select.
     if(STREAM)for(stream_byte=0;stream_byte<STREAM_BITS/8;stream_byte=stream_byte+1)
      if(bytes==23+stream_byte)staged_stream[stream_byte*8 +:8]<=data_byte;
     case(bytes)
      17:staged[2:0]<=data_byte[2:0];18:staged[10:3]<=data_byte;
      19:staged[18:11]<=data_byte;20:staged[19]<=data_byte[0];21:staged[20]<=data_byte[0];
      22:if(EXTENDED)staged_extension<=data_byte;
     endcase
    end
   end
  end
endmodule
