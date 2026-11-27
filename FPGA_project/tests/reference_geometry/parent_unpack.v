module geometry_parent_unpack(
 input clk,rst,restart,input word_empty,input [31:0] word_data,output word_read,
 input pixel_read,output pixel_empty,output reg [31:0] pixel_data);
 reg take;reg [1:0] word_index,pixel_index,valid;
 reg write_bank,read_bank;reg [95:0] group0,group1;
 assign word_read=!take && !valid[write_bank] && !word_empty && !restart && !rst;
 assign pixel_empty=!valid[read_bank] || restart || rst;
 always @(posedge clk or posedge rst)
  if(rst)begin take<=0;word_index<=0;pixel_index<=0;valid<=0;write_bank<=0;read_bank<=0;group0<=0;group1<=0;pixel_data<=0;end
  else if(restart)begin take<=0;word_index<=0;pixel_index<=0;valid<=0;write_bank<=0;read_bank<=0;group0<=0;group1<=0;end
  else begin
   take<=word_read;
   if(take)begin
    if(!write_bank)case(word_index)0:group0[31:0]<=word_data;1:group0[63:32]<=word_data;2:group0[95:64]<=word_data;endcase
    else case(word_index)0:group1[31:0]<=word_data;1:group1[63:32]<=word_data;2:group1[95:64]<=word_data;endcase
    if(word_index==2)begin word_index<=0;valid[write_bank]<=1;write_bank<=~write_bank;end
    else word_index<=word_index+1'b1;
   end
   if(pixel_read && !pixel_empty)begin
    if(!read_bank)begin pixel_data<={group0[23:0],8'd0};group0<=group0>>24;end
    else begin pixel_data<={group1[23:0],8'd0};group1<=group1>>24;end
    if(pixel_index==3)begin pixel_index<=0;valid[read_bank]<=0;read_bank<=~read_bank;end
    else pixel_index<=pixel_index+1'b1;
   end
  end
endmodule
