// Packed 640x360 RGB565 map to 1280x720; A contains no scene geometry.
// Two source rows are prefetched, each 32-bit word expands to four display pixels.
module map_rgb565_scanout #(parameter SMALL_ANIMATION=0)(
 input clk,rst,enabled,frame_start,input animation,input hs_raw,vs_raw,de_raw,input [11:0] x_raw,y_raw,
 output reg read_req,input read_ack,read_empty,input [31:0] read_data,output read_en,
 output reg hs,vs,de,output reg [23:0] rgb);
 reg [31:0] row0[0:319],row1[0:319];
 reg [8:0] rows_loaded,issued,received;reg loading,write_row,pop_delay;reg [5:0] wait_count;
 wire small_mode=SMALL_ANIMATION && animation;
 wire [8:0] source_y=small_mode?y_raw[9:2]:y_raw[9:1];
 wire [8:0] row_words=small_mode?160:320;
 wire wanted=rows_loaded<(small_mode?180:360) && (de_raw?rows_loaded<(source_y+2):rows_loaded<2);
 assign read_en=enabled && loading && issued<row_words && !read_empty;
 reg [8:0] addr_a;reg [31:0] data0_b,data1_b,word_c;reg [15:0] pixel_d;
 reg bank_a,bank_b,half_a,half_b,half_c;
 reg [3:0] ca,cb,cc,cd;
 wire ready=rows_loaded>source_y;
 always @(posedge clk or posedge rst)
  if(rst)begin read_req<=0;rows_loaded<=0;issued<=0;received<=0;loading<=0;write_row<=0;pop_delay<=0;wait_count<=0;end
  else begin
   pop_delay<=read_en;
   if(frame_start)begin read_req<=enabled;rows_loaded<=0;loading<=0;issued<=0;received<=0;pop_delay<=0;wait_count<=0;end
   else begin
    if(read_req && read_ack)begin read_req<=0;wait_count<=48;end
    else if(wait_count!=0)wait_count<=wait_count-1'b1;
    if(enabled && !loading && wanted && wait_count==0 && !read_req)begin loading<=1;issued<=0;received<=0;write_row<=rows_loaded[0];end
    if(read_en)issued<=issued+1'b1;
    if(pop_delay && enabled)begin
     if(write_row)row1[received]<=read_data;else row0[received]<=read_data;
     if(received==row_words-1)begin loading<=0;rows_loaded<=rows_loaded+1'b1;end else received<=received+1'b1;
    end
   end
  end
 always @(posedge clk)begin
  addr_a<=small_mode?x_raw[11:3]:x_raw[10:2];bank_a<=small_mode?y_raw[2]:y_raw[1];half_a<=small_mode?x_raw[2]:x_raw[1];ca<={hs_raw,vs_raw,de_raw,ready};
  data0_b<=row0[addr_a];data1_b<=row1[addr_a];bank_b<=bank_a;half_b<=half_a;cb<=ca;
  word_c<=bank_b?data1_b:data0_b;half_c<=half_b;cc<=cb;
  pixel_d<=half_c?word_c[31:16]:word_c[15:0];cd<=cc;
 end
 always @(posedge clk or posedge rst)
  if(rst)begin hs<=0;vs<=0;de<=0;rgb<=0;end
  else begin hs<=cd[3];vs<=cd[2];de<=cd[1];rgb<=cd[1]&&cd[0]?{pixel_d[15:11],pixel_d[15:13],pixel_d[10:5],pixel_d[10:9],pixel_d[4:0],pixel_d[4:2]}:24'd0;end
endmodule

module map_received_frame_control #(parameter NORMAL_ANIMATION=0,HOLD_COMPLETE_FRAME=0)(
 input clk,rst,vsync,emergency,input [1:0] event_type,
 input complete,input [1:0] incoming_event,output commit_ready,
 input animation_requested,incoming_animation,input hold_frame,
 output reg staging_slot,display_slot,map_mode,output reg have_map,output display_animation);
 reg vs_d;reg [1:0] cached_event;reg cached_animation;
 assign display_animation=cached_animation;
 wire edge_up=vsync&&!vs_d;
 wire held=HOLD_COMPLETE_FRAME && hold_frame;
 assign commit_ready=edge_up && complete && !held;
 always @(posedge clk or posedge rst)
  if(rst)begin vs_d<=0;staging_slot<=0;display_slot<=1;map_mode<=0;have_map<=0;cached_event<=0;cached_animation<=0;end
  else begin
   vs_d<=vsync;
   if(edge_up)begin
    // Only an already-visible emergency map is protected during S3 updates.
    // Boot, photo loading and normal animation retain the parent behavior.
    if(complete && !held && !(map_mode && emergency && !cached_animation &&
       ((NORMAL_ANIMATION && incoming_animation) || incoming_event!=event_type)))begin
     display_slot<=staging_slot;staging_slot<=display_slot;have_map<=1;cached_event<=incoming_event;cached_animation<=NORMAL_ANIMATION && incoming_animation;
     map_mode<=(emergency && !(NORMAL_ANIMATION && incoming_animation) && event_type==incoming_event) ||
      (NORMAL_ANIMATION && !emergency && animation_requested && incoming_animation);
    end else map_mode<=have_map && ((emergency && !cached_animation && (event_type==cached_event || map_mode)) ||
      (NORMAL_ANIMATION && !emergency && animation_requested && cached_animation));
   end
  end
endmodule

