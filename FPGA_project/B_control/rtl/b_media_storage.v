// B owns mounting, fragmented FAT32/BMP parsing, normalization and source cache.
module b_media_storage #(parameter CLK_FREQ_HZ=50000000,REMOTE_TF=0,IMAGE_ROLES=5,NUMBERED_SIX=0,PREV_PLAYLIST=0,PACK_SOURCE=0,
 parameter EMERGENCY_PRIORITY=0,SCAN_RETRY_MS=2000,BAD_RETRY_MS=10000,INIT_TIMEOUT_MS=6000,FAST_NORMALIZE=1,ANIMATION_CACHE=0,PARTICLE_PAGE=0)(
 input clk,rst_n,net_clk,net_rst,
 input sd_miso,output sd_ncs,sd_dclk,sd_mosi,
 input online,packet_valid,input [223:0] packet,output tf_stream_valid,output [223:0] tf_stream_data,input tf_stream_ready,
 input read_req,read_en,input [2:0] read_role,input read_map,input priority_emergency,input [6:0] animation_frame,input animation_dense,
 input map_write_req,map_write_en,map_write_cancel,input [31:0] map_write_data,input map_small,
 output map_write_ack,map_write_full,map_write_done_toggle,
 output render_clk,render_rst,
 output read_ack,read_empty,output [31:0] read_data,
 output [IMAGE_ROLES-1:0] available,output [IMAGE_ROLES*32-1:0] source_sizes,
 output [3:0] source_fault,output source_fault_recurring,output [34:0] source_debug);
 wire small_frame=PARTICLE_PAGE && map_small;
 localparam IMAGE_WORDS=PACK_SOURCE?230400:307200;
 localparam [20:0] MAP_BASE=IMAGE_ROLES*IMAGE_WORDS;
 wire [20:0] animation_base=21'd1536000+animation_frame*(animation_dense?21'd3584:21'd5632);
 wire sd_clk,mem_clk,mem_phase,locked;
 wire media_rst=~rst_n || ~locked;
 assign render_clk=sd_clk;assign render_rst=media_rst;
 sys_pll sys_pll_m0(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_phase),.extlock(locked));
 wire mem_rst;memory_startup_reset u_memory_startup_reset(.clk(mem_clk),.async_rst(media_rst),.rst(mem_rst));
 wire initialized,refresh,busy,app_rd,rd_valid,app_wr;wire [20:0] rd_address,wr_address;
 wire [31:0] ram_data,wr_data;wire [3:0] wr_mask;
 reg [15:0] sd_reset_count;
 wire sd_rst=media_rst || sd_reset_count!=0;
 wire sd_ready,sec_req,sec_end,byte_valid;wire [31:0] sector_address;wire [7:0] byte_data;
 wire [15:0] source_w,source_h;
 wire normalize_active;
 reg normalize_fast;
 always @(posedge sd_clk or posedge sd_rst)
  if(sd_rst)normalize_fast<=0;
  else normalize_fast<=FAST_NORMALIZE && normalize_active && source_w>=320 && source_h>=240;
 generate if(REMOTE_TF)begin: remote_tf
  assign sd_ncs=1;assign sd_dclk=0;assign sd_mosi=1;
  remote_sd_sector_bridge #(.ENABLE_FAST_DELIVERY(1)) u_bridge(.sd_clk(sd_clk),.net_clk(net_clk),.rst(sd_rst||net_rst),.online(online),
   .fast_delivery(normalize_fast),
   .sd_sec_read(sec_req),.sd_sec_read_addr(sector_address),.sd_init_done(sd_ready),
   .sd_sec_read_data(byte_data),.sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sec_end),
   .packet_valid(packet_valid),.packet(packet),.stream_valid(tf_stream_valid),.stream_data(tf_stream_data),.stream_ready(tf_stream_ready));
 end else begin: local_tf
  assign tf_stream_valid=0;assign tf_stream_data=0;
 sd_card_top #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.SPI_HIGH_SPEED_DIV(0)) sd_card_top_m0(.clk(sd_clk),.rst(sd_rst),.sd_init_done(sd_ready),
  .sd_sec_read(sec_req),.sd_sec_read_addr(sector_address),.sd_sec_read_data(byte_data),
  .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sec_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end(),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));
 end endgenerate
 reg scan_start,load_start,load_abort;wire parser_ready,scan_done,found,source_complete;wire [3:0] scan_error_code;
 wire [31:0] parser_debug;wire [4:0] parser_last_state;reg [34:0] failed_debug;
 wire [31:0] handle;wire [2:0] found_role;
 wire source_sof,source_valid,writer_req;wire [23:0] source_pixel;
 reg [31:0] handles[0:IMAGE_ROLES-1];reg [IMAGE_ROLES-1:0] found_mask,cache_mask,failed_mask;
 reg [IMAGE_ROLES*32-1:0] sizes;reg [2:0] loading_role;reg [15:0] loading_w,loading_h;
 wire [31:0] loading_handle=handles[loading_role];
 wire writer_ack,writer_finish,writer_full;wire scaled_valid,scaled_overflow;wire [23:0] scaled_pixel;
 bmp_read #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.RELIABLE_MEDIA(1),.NUMBERED_SIX(NUMBERED_SIX),.PREV_PLAYLIST(PREV_PLAYLIST),.STALL_TIMEOUT_MS(1500)) bmp_read_m0(
  .clk(sd_clk),.rst(sd_rst),.ready(parser_ready),.load_nearly_done(),
  .scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'hffffffff),.scan_target_count(IMAGE_ROLES[3:0]),
  .scan_done(scan_done),.scan_error_code(scan_error_code),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_slot(found_role),.scan_found_total(),
  .load_start(load_start),.load_abort(load_abort),.load_complete(source_complete),.load_debug(parser_debug),.load_last_state(parser_last_state),.load_sector(loading_handle),
  .sd_init_done(sd_ready),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
  .src_w(source_w),.src_h(source_h),.pixel_start(source_sof),.write_req(writer_req),.write_req_ack(writer_ack),
  .sd_sec_read(sec_req),.sd_sec_read_addr(sector_address),.sd_sec_read_data(byte_data),
  .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sec_end),.bmp_data_wr_en(source_valid),.bmp_data(source_pixel));
 bmp_write_scaler #(.ANTIALIAS(1)) u_bmp_write_scaler(.clk(sd_clk),.rst(sd_rst),.src_sof(source_sof),
  .src_w(source_w[11:0]),.src_h(source_h[11:0]),.src_valid(source_valid),.src_pixel(source_pixel),
  .dst_valid(scaled_valid),.dst_pixel(scaled_pixel),.overflow(scaled_overflow));
 function [20:0] frame_base;input [3:0] role;
  begin frame_base=role*IMAGE_WORDS;end
 endfunction
 reg [1:0] pack_phase;reg [23:0] pack_tail;
 wire packed_write=scaled_valid && (!PACK_SOURCE || pack_phase!=0);
 wire [31:0] packed_word=!PACK_SOURCE?{scaled_pixel,8'd0}:
  pack_phase==1?{scaled_pixel[7:0],pack_tail}:
  pack_phase==2?{scaled_pixel[15:0],pack_tail[15:0]}:{scaled_pixel,pack_tail[7:0]};
 always @(posedge sd_clk or posedge sd_rst)
  if(sd_rst)begin pack_phase<=0;pack_tail<=0;end
  else if(source_sof)begin pack_phase<=0;pack_tail<=0;end
  else if(scaled_valid)begin
   pack_phase<=pack_phase+1'b1;
   case(pack_phase)0:pack_tail<=scaled_pixel;1:pack_tail<={8'd0,scaled_pixel[23:8]};
    2:pack_tail<={16'd0,scaled_pixel[23:16]};default:pack_tail<=0;endcase
  end
 wire raw_read_en,raw_read_empty;wire [31:0] raw_read_data;
 wire map_read=IMAGE_ROLES==8?read_map:read_role==IMAGE_ROLES;
 // In the eight-image build the caller marks map reads separately.
 // A writer owns the FIFO until real RAM completion or its own cancellation.
 reg writer_owned,writer_map;reg [2:0] finish_all_sync;
 reg finish_all_toggle,finish_map_toggle;
 wire raw_ack,raw_full,raw_finish;
 wire cancel=writer_owned && (writer_map?map_write_cancel:sd_rst);
 assign map_write_ack=raw_ack && writer_owned && writer_map;
 // raw_ack is produced by frame_fifo_write on mem_clk (125MHz).
 // Keep that crossing out of the parser's state/counter enables on sd_clk.
 // Two settled destination samples also reject a one-sample ACK transient.
 reg [2:0] writer_ack_sync;
 always @(posedge sd_clk or posedge sd_rst)
  if(sd_rst)writer_ack_sync<=0;
  else writer_ack_sync<={writer_ack_sync[1:0],raw_ack};
 assign writer_ack=writer_ack_sync[2] && writer_ack_sync[1] && writer_owned && !writer_map;
 assign writer_full=raw_full && writer_owned && !writer_map;
 assign map_write_full=raw_full && writer_owned && writer_map;
 assign map_write_done_toggle=finish_map_toggle;
 always @(posedge mem_clk or posedge mem_rst)
  if(mem_rst)begin finish_all_toggle<=0;finish_map_toggle<=0;end
  else if(raw_finish)begin finish_all_toggle<=~finish_all_toggle;if(writer_map)finish_map_toggle<=~finish_map_toggle;end
 always @(posedge sd_clk or posedge media_rst)
  if(media_rst)begin writer_owned<=0;writer_map<=0;finish_all_sync<=0;end
  else begin
   finish_all_sync<={finish_all_sync[1:0],finish_all_toggle};
   if(writer_owned)begin if(cancel || finish_all_sync[2]!=finish_all_sync[1])writer_owned<=0;end
   else if(writer_req && !sd_rst)begin writer_owned<=1;writer_map<=0;end
   else if(map_write_req)begin writer_owned<=1;writer_map<=1;end
  end
 wire unpack_empty,unpack_read;wire [31:0] unpack_pixel;
 rgb888_frame_unpack u_unpack(.clk(net_clk),.rst(media_rst||net_rst),.restart(read_req || !PACK_SOURCE || map_read),
  .word_empty(raw_read_empty),.word_data(raw_read_data),.word_read(unpack_read),
  .pixel_read(read_en && !map_read),.pixel_empty(unpack_empty),.pixel_data(unpack_pixel));
 assign read_empty=PACK_SOURCE && !map_read?unpack_empty:raw_read_empty;
 assign read_data=PACK_SOURCE && !map_read?unpack_pixel:raw_read_data;
 assign raw_read_en=PACK_SOURCE && !map_read?unpack_read:read_en;
 frame_read_write #(.FRAME_WIDTH(PACK_SOURCE?480:640),.ENABLE_WRITE_CANCEL(1),.DYNAMIC_WRITE_FLIP(1),.WRITE_V_FLIP(1)) u_frames(.rst(mem_rst),.mem_clk(mem_clk),
  .Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(app_rd),.App_rd_addr(rd_address),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(ram_data),
  .read_clk(net_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
  .read_addr_0(ANIMATION_CACHE && read_role==7?animation_base:map_read?MAP_BASE:frame_base({1'b0,read_role})),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(2'd0),.read_len(ANIMATION_CACHE && read_role==7?(animation_dense?21'd3584:21'd5632):map_read?(small_frame?21'd28928:21'd115200):IMAGE_WORDS),.read_en(raw_read_en),.read_data(raw_read_data),.read_empty(raw_read_empty),
  .App_wr_en(app_wr),.App_wr_addr(wr_address),.App_wr_din(wr_data),.App_wr_dm(wr_mask),
  .write_clk(sd_clk),.write_req(writer_owned && (writer_map?map_write_req:writer_req)),.write_req_ack(raw_ack),.write_finish(raw_finish),
  .write_addr_0(writer_map?MAP_BASE:frame_base(loading_role)),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(writer_map?(small_frame?21'd28928:21'd115200):IMAGE_WORDS),.write_en(writer_owned && (writer_map?map_write_en:packed_write)),
  .write_data(writer_map?map_write_data:packed_word),.write_full(raw_full),.write_cancel(cancel),.write_flip(!writer_map));
 assign writer_finish=raw_finish && writer_owned && !writer_map;
 sdram U3(.Clk(mem_clk),.Clk_sft(mem_phase),.Rst(mem_rst),.Sdr_init_done(initialized),
  .Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_wr_en(app_wr),.App_wr_addr(wr_address),
  .App_wr_dm(wr_mask),.App_wr_din(wr_data),.App_rd_en(app_rd),.App_rd_addr(rd_address),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(ram_data));
 reg finish_toggle;reg [2:0] finish_sync;reg [1:0] init_sync;
 always @(posedge mem_clk or posedge mem_rst)
  if(mem_rst)finish_toggle<=0;else if(writer_finish)finish_toggle<=~finish_toggle;
 always @(posedge sd_clk or posedge media_rst)
  if(media_rst)begin finish_sync<=0;init_sync<=0;end
  else begin finish_sync<={finish_sync[1:0],finish_toggle};init_sync<={init_sync[0],initialized};end
 // Failed scans are terminal parser results, not terminal storage results.
 // Reuse one bounded counter for initialization and retry backoff. Complete
 // SDRAM frames remain available throughout a partial scan or reconnect.
 localparam WAIT_CARD=0,SCAN=1,SELECT=2,START=3,LOAD=4,RETRY_WAIT=5;
 localparam SCAN_RETRY_TICKS=(CLK_FREQ_HZ/1000)*SCAN_RETRY_MS;
 localparam BAD_RETRY_TICKS=(CLK_FREQ_HZ/1000)*BAD_RETRY_MS;
 localparam INIT_TIMEOUT_TICKS=(CLK_FREQ_HZ/1000)*INIT_TIMEOUT_MS;
 localparam MAX_RETRY_TICKS=BAD_RETRY_TICKS>SCAN_RETRY_TICKS?
  (BAD_RETRY_TICKS>INIT_TIMEOUT_TICKS?BAD_RETRY_TICKS:INIT_TIMEOUT_TICKS):
  (SCAN_RETRY_TICKS>INIT_TIMEOUT_TICKS?SCAN_RETRY_TICKS:INIT_TIMEOUT_TICKS);
 localparam RW=$clog2(MAX_RETRY_TICKS+1)>0?$clog2(MAX_RETRY_TICKS+1):1;
 reg [RW-1:0] recovery_count;reg bad_backoff;
 wire initialization_timeout=recovery_count==INIT_TIMEOUT_TICKS-1;
 wire retry_expired=recovery_count==(bad_backoff?BAD_RETRY_TICKS-1:SCAN_RETRY_TICKS-1);
 wire emergency_priority;
 generate if(EMERGENCY_PRIORITY)begin: priority_sync
  reg [1:0] synchronized;
  always @(posedge sd_clk or posedge media_rst)
   if(media_rst)synchronized<=0;else synchronized<={synchronized[0],priority_emergency};
  assign emergency_priority=synchronized[1];
 end else begin assign emergency_priority=0;end endgenerate
 reg [2:0] state;reg started,source_seen,finish_epoch;
 assign normalize_active=state==LOAD && started;
 reg [26:0] stalled;reg [1:0] retries;reg [3:0] fault,fault_count;
 reg [2:0] selected;reg select_valid;
 always @* begin
  selected=2;select_valid=1;
  if(emergency_priority && found_mask[0]&&!cache_mask[0]&&!failed_mask[0])selected=0;
  else if(emergency_priority && found_mask[1]&&!cache_mask[1]&&!failed_mask[1])selected=1;
  else if(EMERGENCY_PRIORITY && emergency_priority)select_valid=0;
  else if(IMAGE_ROLES>=6)begin
   if(found_mask[2]&&!cache_mask[2]&&!failed_mask[2])selected=2;
   else if(found_mask[3]&&!cache_mask[3]&&!failed_mask[3])selected=3;
   else if(found_mask[4]&&!cache_mask[4]&&!failed_mask[4])selected=4;
   else if(found_mask[5]&&!cache_mask[5]&&!failed_mask[5])selected=5;
   else if(IMAGE_ROLES==8 && found_mask[6]&&!cache_mask[6]&&!failed_mask[6])selected=6;
   else if(IMAGE_ROLES==8 && found_mask[7]&&!cache_mask[7]&&!failed_mask[7])selected=7;
   else if(found_mask[0]&&!cache_mask[0]&&!failed_mask[0])selected=0;
   else if(found_mask[1]&&!cache_mask[1]&&!failed_mask[1])selected=1;
   else select_valid=0;
  end else begin
  selected=2;select_valid=1;
  if(found_mask[2]&&!cache_mask[2]&&!failed_mask[2])selected=2;
  else if(found_mask[0]&&!cache_mask[0]&&!failed_mask[0])selected=0;
  else if(found_mask[3]&&!cache_mask[3]&&!failed_mask[3])selected=3;
  else if(found_mask[4]&&!cache_mask[4]&&!failed_mask[4])selected=4;
  else if(IMAGE_ROLES==6 && found_mask[5]&&!cache_mask[5]&&!failed_mask[5])selected=5;
  else if(found_mask[1]&&!cache_mask[1]&&!failed_mask[1])selected=1;
  else select_valid=0;
  end
 end
 wire progress=byte_valid || sec_end || source_valid || scaled_valid;
 // A real abort leaves the parser idle. A short idle indication during an
 // active transaction must not reset the entire mount/load chain.
 reg [1:0] idle_return_count;
 always @(posedge sd_clk or posedge media_rst)
  if(media_rst)idle_return_count<=0;
  else if(state!=LOAD || !started || !parser_ready || source_seen || source_complete)idle_return_count<=0;
  else if(idle_return_count!=3)idle_return_count<=idle_return_count+1'b1;
 wire failed_source=started && parser_ready && idle_return_count==3 && !source_seen && !source_complete;
 wire overflow=scaled_overflow || (scaled_valid && writer_full);
 wire timed_out=stalled==2*CLK_FREQ_HZ-1;
 integer i;
 always @(posedge sd_clk or posedge media_rst)
  if(media_rst)begin
   state<=WAIT_CARD;scan_start<=0;load_start<=0;load_abort<=0;sd_reset_count<=0;
   found_mask<=0;cache_mask<=0;failed_mask<=0;sizes<=0;loading_role<=2;loading_w<=0;loading_h<=0;
   started<=0;source_seen<=0;finish_epoch<=0;stalled<=0;retries<=0;fault<=0;fault_count<=0;
   recovery_count<=0;bad_backoff<=0;failed_debug<=0;
   for(i=0;i<IMAGE_ROLES;i=i+1)handles[i]<=0;
  end else begin
   scan_start<=0;load_start<=0;load_abort<=0;
   if(sd_reset_count!=0)sd_reset_count<=sd_reset_count-1'b1;
   if((state==WAIT_CARD && !sd_rst && (!REMOTE_TF || online)) || state==RETRY_WAIT)
    recovery_count<=recovery_count+1'b1;
   else recovery_count<=0;
   if(found)begin handles[found_role]<=handle;found_mask[found_role]<=1;end
   if(source_sof)begin loading_w<=source_w;loading_h<=source_h;end
   if(state!=SCAN && state!=LOAD || progress)stalled<=0;
   else if(!timed_out)stalled<=stalled+1'b1;
   case(state)
    WAIT_CARD:if(!sd_rst && sd_ready && init_sync[1] && parser_ready)begin
     found_mask<=0;scan_start<=1;state<=SCAN;recovery_count<=0;
    end else if(!sd_rst && (!REMOTE_TF || online) && initialization_timeout)begin
     fault<=5;if(fault_count!=15)fault_count<=fault_count+1'b1;
     bad_backoff<=0;recovery_count<=0;state<=RETRY_WAIT;
    end
    SCAN:if(scan_done && !found)begin
     state<=SELECT;
     if(found_mask==0)begin
      fault<=scan_error_code!=0?scan_error_code:7;if(fault_count!=15)fault_count<=fault_count+1'b1;
      bad_backoff<=0;recovery_count<=0;state<=RETRY_WAIT;
     end
    end else if(timed_out)begin
     fault<=1;if(fault_count!=15)fault_count<=fault_count+1'b1;
     load_abort<=1;bad_backoff<=0;recovery_count<=0;state<=RETRY_WAIT;
    end
    SELECT:if(select_valid)begin loading_role<=selected;state<=START;end
     else if(EMERGENCY_PRIORITY && emergency_priority && cache_mask[0] && cache_mask[1])begin
      // Prepared emergency stills leave the shared SDRAM writer/read port
      // and Ethernet bandwidth to actual map rendering. Resume on clear.
      fault<=0;
     end else if(!(&cache_mask))begin
      bad_backoff<=|failed_mask;recovery_count<=0;state<=RETRY_WAIT;
     end else fault<=0;
    RETRY_WAIT:if(retry_expired)begin
     // A bad source is retried in a new bounded round, rather than blacklisted
     // until power-cycle. No periodic scan runs once all frames are cached.
     failed_mask<=0;retries<=0;sd_reset_count<=16'hffff;
     recovery_count<=0;state<=WAIT_CARD;
    end
    START:if(parser_ready && !sd_rst)begin
     load_start<=1;source_seen<=0;started<=0;finish_epoch<=finish_sync[2];state<=LOAD;
    end
    LOAD:begin
     if(!parser_ready)started<=1;
     if(source_complete)source_seen<=1;
     if(source_seen && finish_sync[2]!=finish_epoch)begin
      cache_mask[loading_role]<=1;sizes[loading_role*32 +:32]<={loading_h,loading_w};
      state<=SELECT;retries<=0;fault<=0;
     end else if(failed_source || overflow || timed_out)begin
      // FE0..FFF with zero bytes records the last active pre-pixel state.
      failed_debug<={loading_role,parser_debug[19:0]==0?{7'h7f,parser_last_state}:parser_debug[31:20],parser_debug[19:0]};
      fault<=overflow?4:timed_out?1:!sd_ready?14:scan_error_code!=0?scan_error_code:2;
      if(fault_count!=15)fault_count<=fault_count+1'b1;
      if(retries==2)begin failed_mask[loading_role]<=1;retries<=0;end else retries<=retries+1'b1;
      load_abort<=1;sd_reset_count<=16'hffff;state<=WAIT_CARD;
     end
    end
   endcase
  end
 localparam INFO_WIDTH=IMAGE_ROLES*33+40;
 wire [INFO_WIDTH-1:0] delivered;
 ethernet_mailbox #(.WIDTH(INFO_WIDTH)) u_cache_info(.src_clk(sd_clk),.src_rst(media_rst || net_rst),.src_valid(1'b1),
  .src_data({fault_count>=2,failed_debug,fault,cache_mask,sizes}),.src_ready(),
  .dst_clk(net_clk),.dst_rst(media_rst || net_rst),.dst_valid(),.dst_data(delivered));
 assign source_debug=delivered[IMAGE_ROLES*33+4 +:35];
 assign source_sizes=delivered[IMAGE_ROLES*32-1:0];assign available=delivered[IMAGE_ROLES*32 +: IMAGE_ROLES];
 assign source_fault=delivered[IMAGE_ROLES*33 +:4];assign source_fault_recurring=delivered[INFO_WIDTH-1];
endmodule
