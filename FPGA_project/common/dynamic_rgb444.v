// Native VGA dynamic frames: 8 RGB444 pixels occupy exactly three 32-bit words.
// 640*480*12/32=115200 words; none of the eight RGB888 picture slots is reused.
module rgb444_packer(input clk,rst,clear,input valid,input [15:0] rgb565,
 output word_valid,output [31:0] word_data);
 reg [2:0] phase;reg [27:0] carry;
 wire [11:0] c={rgb565[15:12],rgb565[10:7],rgb565[4:1]};
 assign word_valid=valid && (phase==2 || phase==5 || phase==7) && !clear;
 assign word_data=phase==2?{c[7:0],carry[23:0]}:phase==5?{c[3:0],carry}:{c,carry[19:0]};
 always @(posedge clk or posedge rst)
  if(rst)begin phase<=0;carry<=0;end
  else if(clear)begin phase<=0;carry<=0;end
  else if(valid)begin
   phase<=phase+1'b1;
   case(phase)
    0:carry<={16'd0,c};1:carry[23:12]<=c;
    2:carry<={24'd0,c[11:8]};3:carry[15:4]<=c;
    4:carry[27:16]<=c;5:carry<={20'd0,c[11:4]};
    6:carry[19:8]<=c;7:carry<=0;
   endcase
  end
endmodule

// Sequential SDRAM FIFO -> four RGB565 pixel pairs per three physical words.
// Raw read data follows raw_en by one cycle, matching frame_fifo_read.
module rgb444_pair_reader(input clk,rst,start,raw_ack,raw_empty,input [31:0] raw_data,
 output raw_en,input pair_en,output pair_empty,output reg [31:0] pair_data);
 reg active,pop;reg [1:0] got,issued,pair;reg ready;
 reg [95:0] block;
 function [15:0] expand;input [11:0] c;
  begin expand={c[11:8],c[11],c[7:4],c[7:6],c[3:0],c[3]};end
 endfunction
 wire [23:0] pixels=pair==0?block[23:0]:pair==1?block[47:24]:pair==2?block[71:48]:block[95:72];
 wire [31:0] next_pair={expand(pixels[23:12]),expand(pixels[11:0])};
 assign pair_empty=!ready;
 assign raw_en=active && !ready && issued<3 && !raw_empty && !start;
 always @(posedge clk or posedge rst)
  if(rst)begin active<=0;pop<=0;got<=0;issued<=0;pair<=0;ready<=0;block<=0;pair_data<=0;end
  else if(start)begin active<=1;pop<=0;got<=0;issued<=0;pair<=0;ready<=0;end
  else begin
   pop<=raw_en;
   if(raw_en)issued<=issued+1'b1;
   if(pop)begin
    case(got)0:block[31:0]<=raw_data;1:block[63:32]<=raw_data;2:block[95:64]<=raw_data;endcase
    if(got==2)begin ready<=1;pair<=0;end else got<=got+1'b1;
   end
   if(pair_en && ready)begin
    pair_data<=next_pair;
    if(pair==3)begin ready<=0;got<=0;issued<=0;pair<=0;end else pair<=pair+1'b1;
   end
  end
endmodule

// Native 640x480 -> 1280x720. Horizontal 2x, vertical 3:2, preserving the
// existing 16:9 procedural scene framing. Every source row is independently drawn.
module map_rgb444_scanout(input clk,rst,enabled,frame_start,animation,
 input hs_raw,vs_raw,de_raw,input [11:0] x_raw,y_raw,
 output reg read_req,input read_ack,read_empty,input [31:0] read_data,output read_en,
 output reg hs,vs,de,output reg [23:0] rgb);
 reg [31:0] row00[0:79],row01[0:79],row02[0:79];
 reg [31:0] row10[0:79],row11[0:79],row12[0:79];
 reg [8:0] rows_loaded;reg [7:0] issued,received;reg loading,write_row,pop_delay;
 reg [1:0] write_phase;reg [6:0] write_group;reg [5:0] wait_count;
 // floor(y*2/3), exact for all active lines 0..719.
 reg [21:0] sy_product;reg [11:0] x_v;reg hs_v,vs_v,de_v;
 always @(posedge clk)begin sy_product<=y_raw*10'd683;x_v<=x_raw;hs_v<=hs_raw;vs_v<=vs_raw;de_v<=de_raw;end
 wire [8:0] source_y=sy_product[18:10];
 wire wanted=rows_loaded<480 && (de_v?rows_loaded<source_y+2:rows_loaded<2);
 wire ready=rows_loaded>source_y;
 assign read_en=enabled && loading && issued<240 && !read_empty;
 always @(posedge clk or posedge rst)
  if(rst)begin read_req<=0;rows_loaded<=0;issued<=0;received<=0;loading<=0;write_row<=0;pop_delay<=0;wait_count<=0;write_phase<=0;write_group<=0;end
  else begin
   pop_delay<=read_en;
   if(frame_start)begin read_req<=enabled;rows_loaded<=0;loading<=0;issued<=0;received<=0;pop_delay<=0;wait_count<=0;write_phase<=0;write_group<=0;end
   else begin
    if(read_req && read_ack)begin read_req<=0;wait_count<=48;end
    else if(wait_count!=0)wait_count<=wait_count-1'b1;
    if(enabled && !loading && wanted && wait_count==0 && !read_req)begin loading<=1;issued<=0;received<=0;write_row<=rows_loaded[0];write_group<=0;write_phase<=0;end
    if(read_en)issued<=issued+1'b1;
    if(pop_delay && enabled)begin
     if(received==239)begin loading<=0;rows_loaded<=rows_loaded+1'b1;end else received<=received+1'b1;
     if(write_phase==2)begin write_phase<=0;write_group<=write_group+1'b1;end else write_phase<=write_phase+1'b1;
    end
   end
  end
 // RAM write/read processes have no asynchronous reset, preserving BRAM inference.
 reg [6:0] address_a;reg bank_a;reg [2:0] phase_a,phase_b;
 reg [95:0] words_b;reg [3:0] ca,cb,cc;reg [11:0] pixel_c;
 always @(posedge clk)begin
  if(pop_delay && enabled)begin
   if(write_row)case(write_phase)0:row10[write_group]<=read_data;1:row11[write_group]<=read_data;2:row12[write_group]<=read_data;endcase
   else case(write_phase)0:row00[write_group]<=read_data;1:row01[write_group]<=read_data;2:row02[write_group]<=read_data;endcase
  end
  address_a<=x_v[10:4];bank_a<=source_y[0];phase_a<=x_v[3:1];ca<={hs_v,vs_v,de_v,ready};
  words_b<=bank_a?{row12[address_a],row11[address_a],row10[address_a]}:{row02[address_a],row01[address_a],row00[address_a]};
  phase_b<=phase_a;cb<=ca;
  case(phase_b)
   0:pixel_c<=words_b[11:0];1:pixel_c<=words_b[23:12];2:pixel_c<=words_b[35:24];3:pixel_c<=words_b[47:36];
   4:pixel_c<=words_b[59:48];5:pixel_c<=words_b[71:60];6:pixel_c<=words_b[83:72];7:pixel_c<=words_b[95:84];
  endcase
  cc<=cb;
 end
 always @(posedge clk or posedge rst)
  if(rst)begin hs<=0;vs<=0;de<=0;rgb<=0;end
  else begin hs<=cc[3];vs<=cc[2];de<=cc[1];rgb<=cc[1]&&cc[0]?{pixel_c[11:8],pixel_c[11:8],pixel_c[7:4],pixel_c[7:4],pixel_c[3:0],pixel_c[3:0]}:24'd0;end
endmodule
