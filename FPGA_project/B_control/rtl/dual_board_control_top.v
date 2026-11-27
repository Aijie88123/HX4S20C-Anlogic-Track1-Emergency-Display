// B reports debounced-in-A zoom, barrier mode and echoed actual emergency.
// This small immutable snapshot replaces its route solver/walking pipeline.
module b_map_control_sender #(parameter UPDATE_CYCLES=500000,ENABLE_TEMPERATURE=0)(
 input clk,rst,online,input [2:0] actual_state,input [1:0] switches,barrier_mode,
 input [23:0] temperature_status,
 input stream_ready,output stream_valid,output [223:0] stream_data);
 localparam CW=$clog2(UPDATE_CYCLES)>0?$clog2(UPDATE_CYCLES):1;
 reg [CW-1:0] timer;reg pending,have_sent;reg [15:0] control_sequence;
 reg [1:0] sw_meta,sw_sync;reg [6:0] previous_controls;reg [223:0] held;
 wire [1:0] zoom=sw_sync==3?2'd0:sw_sync;
 wire [6:0] controls={actual_state,barrier_mode,zoom};
 // Reserved extension: 5401 marker, flags, signed 1/16C. Held for backpressure.
 wire [153:0] telemetry=ENABLE_TEMPERATURE?{114'd0,16'h5401,temperature_status}:154'd0;
 assign stream_valid=online&&pending;assign stream_data=held;
 always @(posedge clk or posedge rst)
  if(rst)begin timer<=0;pending<=0;have_sent<=0;control_sequence<=0;sw_meta<=0;sw_sync<=0;previous_controls<=0;held<=0;end
  else begin
   sw_meta<=switches;sw_sync<=sw_meta;
   if(!online)begin timer<=0;pending<=0;have_sent<=0;control_sequence<=0;end
   else begin
    if(timer<UPDATE_CYCLES-1)timer<=timer+1'b1;
    if(pending&&stream_ready)pending<=0;
    if(!pending && (!have_sent || timer==UPDATE_CYCLES-1 || controls!=previous_controls))begin
     held<={36'h4d4150431,telemetry,control_sequence,barrier_mode,2'd0,zoom,actual_state[2:1],actual_state[0],1'b0,8'd3};
     previous_controls<=controls;control_sequence<=control_sequence+1'b1;have_sent<=1;pending<=1;timer<=0;
    end
   end
  end
endmodule

module dual_board_control_top #(parameter ENABLE_MEDIA=1,ENABLE_MESH3D=0,ENABLE_RASTER=1,ENABLE_REMOTE_TF=1,FAST_DEMO=1,UART_BAUD=115200,ENABLE_SUBTITLE=1,ENABLE_SENSOR=1)(
 input clk,rst_n,key_next,key_auto,key_emergency,input [3:0] sw,
 input uart_rx,output uart_tx,
 inout ds18b20_dq,
 input sd_miso,output sd_ncs,sd_dclk,sd_mosi,
 input eth_rx_clk,eth_rx_ctl,input [3:0] eth_rxd,
 output eth_tx_clk,eth_tx_ctl,output [3:0] eth_txd,output eth_mdc,inout eth_mdio,
 output [3:0] led,output reg [5:0] seg_sel,output reg [7:0] seg_data);
 wire net_clk,tx90,locked;wire rst=~rst_n || ~locked;
 ethernet_pll u_ethernet_pll(.refclk(clk),.reset(1'b0),.clk0_out(net_clk),.clk1_out(tx90),.clk2_out(),.extlock(locked));
 wire toggle_event,step_event,clear_event,barrier_step;
 key_remove_shakes #(.CLK_FREQ_HZ(25000000)) s4(.I_clk(net_clk),.I_rst_n(~rst),.I_key_in(key_emergency),.O_key_trig_out(toggle_event));
 map_event_button #(.DEBOUNCE_MS(5)) s2(.clk(net_clk),.rst(rst),.button(key_next),.short_press(step_event),.long_press(barrier_step));
 key_remove_shakes #(.CLK_FREQ_HZ(25000000)) s3(.I_clk(net_clk),.I_rst_n(~rst),.I_key_in(key_auto),.O_key_trig_out(clear_event));
 wire uart_action_valid,uart_action_ready;wire [1:0] uart_action_type,uart_action_value;
 wire signed [15:0] temperature_raw;
 wire temperature_reading_valid,temperature_sample_valid,temperature_fault;
 wire [2:0] temperature_fault_code;
 wire temperature_warning,temperature_alarm,temperature_clear_allowed;
 wire temperature_request_valid,temperature_request_ready,temperature_request_accepted;
 wire [1:0] temperature_request_type,temperature_request_value;
 wire uart_temperature_clear;
 wire temperature_manual_clear=uart_temperature_clear || (clear_event && temperature_alarm && temperature_clear_allowed);
 wire temperature_valid=temperature_reading_valid && !temperature_fault;
 wire [2:0] temperature_report_fault=temperature_fault?(temperature_fault_code==0?3'd7:temperature_fault_code):3'd0;
 generate if(ENABLE_SENSOR)begin: temperature_service
  ds18b20_emergency #(.CLK_HZ(25000000)) u_temperature(.clk(net_clk),.rst(rst),.dq(ds18b20_dq),.manual_clear(temperature_manual_clear),
   .temperature_raw(temperature_raw),.reading_valid(temperature_reading_valid),.sample_valid(temperature_sample_valid),
   .fault_code(temperature_fault_code),.sensor_fault(temperature_fault),.warning_active(temperature_warning),
   .alarm_latched(temperature_alarm),.clear_allowed(temperature_clear_allowed),
   .request_valid(temperature_request_valid),.request_ready(temperature_request_ready),
   .request_type(temperature_request_type),.request_value(temperature_request_value),.request_accepted(temperature_request_accepted),.block_nonbarrier());
 end else begin: no_temperature_service
  assign ds18b20_dq=1'bz;assign temperature_raw=0;assign temperature_reading_valid=0;assign temperature_sample_valid=0;
  assign temperature_fault=1;assign temperature_fault_code=0;assign temperature_warning=0;assign temperature_alarm=0;assign temperature_clear_allowed=0;
  assign temperature_request_valid=0;assign temperature_request_type=0;assign temperature_request_value=0;assign temperature_request_accepted=0;
 end endgenerate
 wire key_clear_allowed=clear_event && !temperature_alarm;
 wire key_toggle_allowed=toggle_event && !temperature_alarm;
 wire key_step_allowed=step_event && !temperature_alarm;
 wire selected_action_valid,all_action_ready;wire [1:0] selected_action_type,selected_action_value;
 wire temperature_selected=temperature_request_valid && !temperature_manual_clear;
 sensor_action_arbiter u_sensor_actions(.sensor_valid(temperature_selected),.sensor_lock(temperature_alarm),
  .sensor_type(temperature_request_type),.sensor_value(temperature_request_value),.sensor_ready(temperature_request_ready),
  .uart_valid(uart_action_valid),.uart_type(uart_action_type),.uart_value(uart_action_value),.uart_ready(uart_action_ready),
  .action_valid(selected_action_valid),.action_type(selected_action_type),.action_value(selected_action_value),.action_ready(all_action_ready));
 wire uart_key_priority=key_clear_allowed||key_toggle_allowed||key_step_allowed||barrier_step;
 reg command_origin_uart;reg command_origin_sensor;
 reg command_armed;reg emergency;reg [1:0] event_type;reg [7:0] command_sequence;
 always @(posedge net_clk or posedge rst)
  if(rst)begin command_origin_uart<=0;command_origin_sensor<=0;end
  else begin
   if(uart_key_priority)command_origin_uart<=0;
   else if(uart_action_valid&&uart_action_ready)command_origin_uart<=1;
   else if(temperature_request_accepted)command_origin_uart<=0;
   if(key_clear_allowed || key_toggle_allowed || (key_step_allowed && emergency))command_origin_sensor<=0;
   else if(selected_action_valid&&all_action_ready&&selected_action_type!=2)command_origin_sensor<=temperature_selected;
  end
 always @(posedge net_clk or posedge rst)
  if(rst)begin command_armed<=0;emergency<=0;event_type<=0;command_sequence<=0;end
  else if(key_clear_allowed)begin command_armed<=1;emergency<=0;event_type<=0;command_sequence<=command_sequence+1'b1;end
  else if(key_toggle_allowed)begin command_armed<=1;emergency<=~emergency;event_type<=0;command_sequence<=command_sequence+1'b1;end
  else if(key_step_allowed && emergency)begin command_armed<=1;event_type<=event_type+1'b1;command_sequence<=command_sequence+1'b1;end
 else if(selected_action_valid&&all_action_ready&&selected_action_type!=2)begin
   command_armed<=1;emergency<=selected_action_type==0;
   event_type<=selected_action_type==0?selected_action_value:2'd0;command_sequence<=command_sequence+1'b1;
  end
 wire [20:0] peer;
 reg [1:0] barrier_mode;
 always @(posedge net_clk or posedge rst)
  if(rst)barrier_mode<=0;else if(key_clear_allowed || key_toggle_allowed || key_step_allowed)barrier_mode<=0;
  else if(selected_action_valid&&all_action_ready)barrier_mode<=selected_action_type==2?selected_action_value:2'd0;
  else if(barrier_step && peer[0])barrier_mode<=barrier_mode+1'b1;
 // Normal S2 releases select the carousel period. Both desired and actual
 // emergency suppress this action, including an unacknowledged S4 command.
 wire period_step=key_step_allowed && !emergency && !peer[0] && !clear_event && !toggle_event;
 wire received,online,configured,link,transmitting;
 wire [7:0] feedback,carousel_phase;
 distributed_carousel_clock #(.PERIOD0_MS(3000),.PERIOD1_MS(5000),.PERIOD2_MS(FAST_DEMO?8000:10000),.STARTUP_PERIOD_MS(FAST_DEMO?3000:0)) u_carousel_clock(.clk(net_clk),.rst(rst),.switches(sw[1:0]),.period_step(period_step),
  .online(online),.feedback(feedback[4:0]),.actual_emergency(peer[0]),.phase(carousel_phase));
 wire [223:0] incoming_stream,outgoing_stream;
 wire [7:0] uart_cached;wire [3:0] uart_source_fault;
 wire [2:0] desired={event_type,emergency};
 wire acknowledged=online && peer[19] && peer[18:11]==command_sequence && peer[2:0]==desired;
 wire [187:0] uart_scene={incoming_stream[211:32],8'd3};
 wire uart_scene_valid=received&&incoming_stream[7:0]==14&&incoming_stream[15:8]==1&&incoming_stream[223:212]==0;
 assign all_action_ready=online&&!uart_key_priority&&!temperature_manual_clear&&(selected_action_type!=2||peer[0]);
 wire legacy_uart_tx,legacy_rx_valid,legacy_rx_error,legacy_tx_valid,legacy_tx_ready,legacy_idle;
 wire [7:0] legacy_rx_data,legacy_tx_data;wire subtitle_valid;wire [223:0] subtitle_packet;
 generate if(ENABLE_SUBTITLE)begin: subtitle_service
  uart_subtitle_bridge #(.BAUD(UART_BAUD)) bridge(.clk(net_clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),.online(online),
  .legacy_rx_valid(legacy_rx_valid),.legacy_rx_data(legacy_rx_data),.legacy_rx_error(legacy_rx_error),.legacy_idle(legacy_idle),
  .legacy_tx_valid(legacy_tx_valid),.legacy_tx_data(legacy_tx_data),.legacy_tx_ready(legacy_tx_ready),
  .stream_valid(subtitle_valid),.stream_data(subtitle_packet),.stream_ready(stream_ready&&!spectrum_valid&&!map_on_wire&&!tf_valid),
  .packet_valid(received),.packet(incoming_stream));
 end else begin
  assign uart_tx=legacy_uart_tx;assign subtitle_valid=0;assign subtitle_packet=0;
  assign legacy_rx_valid=0;assign legacy_rx_error=0;assign legacy_rx_data=0;assign legacy_tx_ready=0;
 end endgenerate
 b_uart_service #(.BAUD(UART_BAUD),.EXTERNAL_UART(ENABLE_SUBTITLE),.ENABLE_SENSOR(ENABLE_SENSOR)) u_uart_service(.clk(net_clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(legacy_uart_tx),
  .external_rx_valid(legacy_rx_valid),.external_rx_error(legacy_rx_error),.external_rx_data(legacy_rx_data),
  .external_tx_valid(legacy_tx_valid),.external_tx_data(legacy_tx_data),.external_tx_ready(legacy_tx_ready),.service_idle(legacy_idle),
  .online(online),.configured(configured),.phy_link(link),.acknowledged(acknowledged),.desired(desired),.actual(peer[2:0]),.origin_uart(command_origin_uart),
  .barrier(barrier_mode),.cached(uart_cached),.source_fault(uart_source_fault),.scene_valid(uart_scene_valid),.scene(uart_scene),
  .sensor_temperature(temperature_raw),.sensor_valid(temperature_valid),.sensor_warning(temperature_warning),.sensor_alarm(temperature_alarm),
  .sensor_clear_allowed(temperature_clear_allowed),.sensor_fault_code(temperature_report_fault),.sensor_origin(command_origin_sensor),
  .sensor_request_accepted(temperature_request_accepted),.sensor_clear(uart_temperature_clear),
  .control_ready(uart_action_ready),.control_blocked(uart_key_priority),.action_valid(uart_action_valid),.action_type(uart_action_type),.action_value(uart_action_value));
 wire stream_valid,stream_ready,spectrum_valid,map_valid;
 wire [223:0] spectrum_packet,map_packet;
 wire tf_valid;wire [223:0] tf_packet;
 wire media_valid,raster_valid;wire [223:0] media_packet,raster_packet;
 wire mesh_ack_valid;wire [223:0] mesh_ack_packet;wire map_on_wire=map_valid;
 wire particle_valid;wire [223:0] particle_packet;wire [8:0] particle_motion;
 particle_atlas_sender #(.MOTION(1)) u_particle_sender(.motion_phase(particle_motion),.clk(net_clk),.rst(rst),.online(online),.enabled(1'b1),
  .packet_valid(received),.packet(incoming_stream),.stream_valid(particle_valid),.stream_data(particle_packet),
  .stream_ready(stream_ready&&!spectrum_valid&&!map_on_wire&&!tf_valid&&!subtitle_valid&&!raster_valid&&!media_valid&&!mesh_ack_valid),.ready());
 assign stream_valid=spectrum_valid || map_on_wire || tf_valid || subtitle_valid || raster_valid || media_valid || mesh_ack_valid || particle_valid;
 assign outgoing_stream=spectrum_valid?spectrum_packet:map_on_wire?map_packet:tf_valid?tf_packet:subtitle_valid?subtitle_packet:raster_valid?raster_packet:media_valid?media_packet:mesh_ack_valid?mesh_ack_packet:particle_packet;
 b_map_control_sender #(.ENABLE_TEMPERATURE(ENABLE_SENSOR)) u_controls(.clk(net_clk),.rst(rst),.online(online),.actual_state(peer[2:0]),
  .switches(sw[3:2]),.barrier_mode(barrier_mode),
  .temperature_status({1'b1,temperature_valid,temperature_warning,temperature_alarm,temperature_clear_allowed,temperature_report_fault,temperature_raw}),
  .stream_ready(stream_ready&&!spectrum_valid),
  .stream_valid(map_valid),.stream_data(map_packet));
 distributed_spectrum_worker #(.HIGH_ACCURACY(1)) u_spectrum_worker(
  .clk(net_clk),.rst(rst),.online(online),.packet_valid(received),.packet(incoming_stream),
  .stream_ready(stream_ready),.stream_valid(spectrum_valid),.stream_data(spectrum_packet),.gap_count());
 generate if(ENABLE_MEDIA)begin: media_service
  wire [7:0] available;wire [255:0] source_sizes;wire [3:0] fault;wire recurrence;
  assign uart_cached=available;assign uart_source_fault=fault;
  wire read_req,read_ack,read_empty,read_en;wire [31:0] read_data;wire [2:0] read_role;
  wire media_req,media_en,media_busy,map_req,map_en,map_busy;
  wire animation_req,animation_en,animation_busy,animation_fault;
  wire anim_ack,anim_empty;wire [31:0] anim_data;
  wire raster_animation;wire frame_available,frame_consumed;wire [1:0] frame_event;reg [6:0] animation_frame;wire animation_dense;
  reg [21:0] animation_clock;reg [3:0] animation_release;reg animation_consumed_d;
  wire animation_enabled=online && !peer[0] && feedback[6];
  wire animation_ready=animation_enabled && feedback[2] && animation_clock==0 && animation_release==0;
  wire [34:0] source_debug;wire [2:0] media_role;reg read_owned;reg [1:0] read_owner;
  always @(posedge net_clk or posedge rst)
   if(rst)begin read_owned<=0;read_owner<=0;end
   else if(read_owned)begin
    if(read_owner==2?!animation_busy:read_owner==1?!map_busy:!media_busy)read_owned<=0;
   end else if(animation_req)begin read_owned<=1;read_owner<=2;end
   else if(map_req)begin read_owned<=1;read_owner<=1;end
   else if(media_req)begin read_owned<=1;read_owner<=0;end
  assign read_req=read_owned && (read_owner==2?animation_req:read_owner==1?map_req:media_req);
  assign read_en=read_owned && (read_owner==2?animation_en:read_owner==1?map_en:media_en);
  assign read_role=read_owner==2?3'd7:read_owner==1?3'd6:media_role;
  always @(posedge net_clk or posedge rst)
   if(rst)begin animation_frame<=0;animation_clock<=0;animation_release<=0;animation_consumed_d<=0;end
   else begin
    animation_consumed_d<=frame_consumed;
    if(animation_clock!=0)animation_clock<=animation_clock-1'b1;
    if(animation_release!=0)animation_release<=animation_release-1'b1;
    if(!animation_enabled && !map_busy && !animation_busy)begin animation_clock<=0;animation_frame<=0;end

    // Start the frame period at the request, not after its network transfer.
    if(map_req && raster_animation && !animation_busy && animation_clock==0)animation_clock<=(animation_dense?1350000:2825000)-1;
    if(frame_consumed && !animation_consumed_d && raster_animation)begin
     animation_frame<=animation_frame==(animation_dense?83:39)?0:animation_frame+1'b1;animation_release<=15;
    end
   end
  wire render_clk,render_rst,map_wr_req,map_wr_en,map_wr_cancel,map_wr_ack,map_wr_full,map_done;
  wire [31:0] map_wr_data;
  wire scene_delivery;wire [188:0] scene_bundle;wire [3:0] frame_info;wire frame_animation;wire [8:0] render_motion;
  b_media_storage #(.REMOTE_TF(ENABLE_REMOTE_TF),.IMAGE_ROLES(8),.NUMBERED_SIX(1),.PREV_PLAYLIST(1),.PACK_SOURCE(1),.EMERGENCY_PRIORITY(1),.ANIMATION_CACHE(0),.PARTICLE_PAGE(1),.FAST_NORMALIZE(0)) u_storage(.clk(clk),.rst_n(rst_n),.net_clk(net_clk),.net_rst(rst),
   .sd_miso(sd_miso),.sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),
   .online(online),.packet_valid(received),.packet(incoming_stream),.tf_stream_valid(tf_valid),.tf_stream_data(tf_packet),
   .tf_stream_ready(stream_ready&&!spectrum_valid&&!map_on_wire),
   .read_req(read_req),.read_en(read_en),.read_role(read_role),.read_map(read_owner==1),.animation_frame(animation_frame),.animation_dense(animation_dense),.read_ack(read_ack),.read_empty(read_empty),.read_data(read_data),
   .available(available),.source_sizes(source_sizes),.priority_emergency(peer[0]),.source_fault(fault),.source_fault_recurring(recurrence),.source_debug(source_debug),
   .render_clk(render_clk),.render_rst(render_rst),.map_write_req(map_wr_req),.map_write_en(map_wr_en),.map_write_data(map_wr_data),
   .map_write_cancel(map_wr_cancel),.map_small(1'b0),.map_write_ack(map_wr_ack),.map_write_full(map_wr_full),.map_write_done_toggle(map_done));
  media_image_sender #(.IMAGE_ROLES(8),.EMERGENCY_PRIORITY(1),.STATUS_REVISION(10),.DIAGNOSTICS(1)) u_sender(.clk(net_clk),.rst(rst),.online(online),.available(available),.source_sizes(source_sizes),.priority_emergency(peer[0]),
   .source_fault(animation_fault?4'hd:fault),.source_fault_recurring(recurrence),.source_debug(source_debug),.packet_valid(received),.packet(incoming_stream),
   .stream_valid(media_valid),.stream_data(media_packet),.stream_ready(stream_ready&&!spectrum_valid&&!map_on_wire&&!tf_valid&&!subtitle_valid&&!raster_valid),
   .read_req(media_req),.read_ack(read_ack&&read_owned&&read_owner==0),.read_empty(read_empty),.read_data(read_data),.read_en(media_en),.read_role(media_role),.read_busy(media_busy));
  if(ENABLE_RASTER)begin: rendered_map
   ethernet_mailbox #(.WIDTH(189)) u_scene_to_renderer(.src_clk(net_clk),.src_rst(rst||render_rst),.src_valid(received && incoming_stream[7:0]==14 && incoming_stream[15:8]==1 && incoming_stream[223:212]==0),
    .src_data({peer[0],incoming_stream[211:32],8'd3}),.src_ready(),.dst_clk(render_clk),.dst_rst(rst||render_rst),.dst_valid(scene_delivery),.dst_data(scene_bundle));
   reg [1:0] active_sync,particle_sync,run_sync,connected_sync;
   always @(posedge render_clk or posedge render_rst)
    if(render_rst)begin active_sync<=0;particle_sync<=0;run_sync<=0;connected_sync<=0;end
    else begin connected_sync<={connected_sync[0],online};active_sync<={active_sync[0],online&&((peer[0]&&feedback[5])||animation_enabled)};particle_sync<={particle_sync[0],animation_enabled};run_sync<={run_sync[0],feedback[2]};end
   assign mesh_ack_valid=0;assign mesh_ack_packet=0;
   b_map_frame_renderer_vga u_frame_renderer(.particle_mode(particle_sync[1]),.animation_run(run_sync[1]),.frame_animation(frame_animation),.motion_phase(render_motion),.clk(render_clk),.rst(render_rst || !connected_sync[1]),.enabled(active_sync[1]),
    .scene_valid(scene_delivery),.scene(scene_bundle[187:0]),.write_req(map_wr_req),.write_ack(map_wr_ack),.write_full(map_wr_full),
    .write_done_toggle(map_done),.write_en(map_wr_en),.write_data(map_wr_data),.write_cancel(map_wr_cancel),
    .frame_valid(frame_available),.frame_event(frame_event),.frame_consumed(frame_consumed));
   ethernet_mailbox #(.WIDTH(4)) u_render_ready(.src_clk(render_clk),.src_rst(rst||render_rst),.src_valid(1'b1),
    .src_data({frame_animation,frame_available,frame_event}),.src_ready(),.dst_clk(net_clk),.dst_rst(rst||render_rst),.dst_valid(),.dst_data(frame_info));
   // Particle and map frames have the same immutable SDRAM owner.
   assign animation_req=0;assign animation_en=0;assign animation_busy=0;assign animation_fault=0;
   assign animation_dense=0;
   ethernet_mailbox #(.WIDTH(9)) u_motion(.src_clk(render_clk),.src_rst(rst||render_rst),.src_valid(1'b1),.src_data(render_motion),.src_ready(),
    .dst_clk(net_clk),.dst_rst(rst||render_rst),.dst_valid(),.dst_data(particle_motion));
   wire native_read_en,native_read_empty;wire [31:0] native_read_data;
   rgb444_pair_reader u_expand(.clk(net_clk),.rst(rst||!online),.start(map_req),
    .raw_ack(read_ack&&read_owned&&read_owner==1),.raw_empty(read_empty || !read_owned || read_owner!=1),.raw_data(read_data),.raw_en(map_en),
    .pair_en(native_read_en),.pair_empty(native_read_empty),.pair_data(native_read_data));
   raster_map_window_sender #(.PIXELS(307200),.ALLOW_ANIMATION(1),.ANIMATION_PIXELS(307200),.NATIVE_VGA(1),.WINDOW_LOG2(4),.FAST_SOURCE(1)) u_raster_sender(.clk(net_clk),.rst(rst),.online(online),.frame_valid(frame_info[2]),.frame_event(frame_info[1:0]),.frame_consumed(frame_consumed),.frame_animation(frame_info[3]),.current_animation(raster_animation),
    .packet_valid(received),.packet(incoming_stream),.stream_valid(raster_valid),.stream_data(raster_packet),.stream_ready(stream_ready&&!spectrum_valid&&!map_on_wire&&!tf_valid&&!subtitle_valid),
    .read_req(map_req),.read_en(native_read_en),.read_busy(map_busy),.read_ack(read_ack&&read_owned&&read_owner==1),.read_empty(native_read_empty),.read_data(native_read_data));
  end else begin
   assign mesh_ack_valid=0;assign mesh_ack_packet=0;
   assign particle_motion=0;assign animation_dense=0;assign animation_req=0;assign animation_en=0;assign animation_busy=0;assign animation_fault=0;assign raster_animation=0;
   assign map_req=0;assign map_en=0;assign map_busy=0;assign raster_valid=0;assign raster_packet=0;
   assign map_wr_req=0;assign map_wr_en=0;assign map_wr_data=0;assign map_wr_cancel=0;
  end
 end else begin: control_reference
  assign uart_cached=0;assign uart_source_fault=4'hf;
  assign mesh_ack_valid=0;assign mesh_ack_packet=0;
  assign particle_motion=0;assign tf_valid=0;assign tf_packet=0;assign raster_valid=0;assign raster_packet=0;assign media_valid=0;assign media_packet=0;assign sd_ncs=1;assign sd_dclk=0;assign sd_mosi=1;
 end endgenerate

 ethernet_command_link #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(ENABLE_MEDIA),.RASTER(ENABLE_RASTER&&ENABLE_MEDIA),.RAW_TF(ENABLE_REMOTE_TF&&ENABLE_MEDIA),.RAW_TF_VERSION(12),.BURST_RASTER(1),.SUBTITLE(ENABLE_SUBTITLE)) u_ethernet_link(
  .clk(net_clk),.tx_clk90(tx90),.rst(rst),.local_state(desired),.local_sequence(command_sequence),.local_command_active(command_armed),.local_extension(carousel_phase),
  .eth_rx_clk(eth_rx_clk),.eth_rx_ctl(eth_rx_ctl),.eth_rxd(eth_rxd),
  .eth_tx_clk(eth_tx_clk),.eth_tx_ctl(eth_tx_ctl),.eth_txd(eth_txd),.eth_mdc(eth_mdc),.eth_mdio(eth_mdio),
  .peer_valid(received),.peer_message(peer),.peer_extension(feedback),.peer_online(online),.phy_configured(configured),.phy_link(link),.tx_active(transmitting),
  .stream_valid(stream_valid),.stream_data(outgoing_stream),.stream_ready(stream_ready),.peer_stream(incoming_stream));

 // The B role marker must remain visible even before the Ethernet PLL locks.
 // Capture PLL telemetry on the reference falling edge, then register it on
 // the rising edge. This leaves a half-cycle for the display-only crossing.
 // neither stage feeds the command or acknowledgement logic.
 wire [5:0] display_status={configured,online,acknowledged,emergency,event_type};
 reg [5:0] status_meta,status_sync;reg [5:0] status_frame;
 reg [12:0] scan_count;
 reg [2:0] scan;
 reg [7:0] selected_segments;
 always @* begin
  case(scan)
   0:selected_segments=8'h83; // lowercase b: unmistakable controller identity
   1:selected_segments=status_frame[5] ? 8'hf9 : 8'hc0; // PHY configured
   2:selected_segments=status_frame[4] ? 8'hf9 : 8'hc0; // A online
   3:selected_segments=status_frame[3] ? 8'hf9 : 8'hc0; // command acknowledged
   4:selected_segments=status_frame[2] ? 8'hf9 : 8'hc0; // desired emergency
   5:case(status_frame[1:0])
      0:selected_segments=8'hc0;1:selected_segments=8'hf9;
      2:selected_segments=8'ha4;3:selected_segments=8'hb0;
     endcase
   default:selected_segments=8'hff;
  endcase
 end
 always @(negedge clk or negedge rst_n)
  if(!rst_n)status_meta<=0;else status_meta<=display_status;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   status_sync<=0;status_frame<=0;
   scan_count<=0;scan<=0;seg_sel<=6'b111111;seg_data<=8'hff;
  end else begin
   status_sync<=status_meta;
   scan_count<=scan_count+1'b1;
   // Freeze telemetry for the entire six-digit scan (~0.98 ms).
   if(scan_count==0 && scan==0)status_frame<=status_sync;
   // Disable all digits before changing segment data, then enable only one.
   // This also removes combinational selection glitches and digit ghosting.
   if(scan_count==13'h1fff)begin
    scan<=scan==5 ? 3'd0 : scan+1'b1;seg_sel<=6'b111111;
   end else if(scan_count==0)begin
    seg_sel<=6'b111111;seg_data<=selected_segments;
   end else if(scan_count==1)begin
    case(scan)
     0:seg_sel<=6'b111110;1:seg_sel<=6'b111101;2:seg_sel<=6'b111011;
     3:seg_sel<=6'b110111;4:seg_sel<=6'b101111;5:seg_sel<=6'b011111;
     default:seg_sel<=6'b111111;
    endcase
   end
  end
 assign led={configured,acknowledged,online,emergency};
endmodule

// B owns the configurable wall-clock and fade deadline. A reports only complete
// frame epoch, valid display, autoplay and prefetch completion. This phase is
// separate from emergency command command_sequence, so carousel packets cannot replay
// a local emergency toggle. A rejects phases belonging to its previous frame.
module distributed_carousel_clock #(
 parameter integer CLK_FREQ_HZ=25000000,
 parameter integer DEBOUNCE_MS=20,FADE_MS=160,
 parameter integer PERIOD0_MS=3000,PERIOD1_MS=5000,PERIOD2_MS=10000,STARTUP_PERIOD_MS=0
)(input clk,rst,input [1:0] switches,input period_step,input online,
 input [4:0] feedback,input actual_emergency,output [7:0] phase);
 localparam integer DIV=CLK_FREQ_HZ/1000;
 localparam integer DW=$clog2(DIV)>0?$clog2(DIV):1;
 reg [DW-1:0] divider;
 wire millisecond=(divider==DIV-1);
 reg [1:0] switch_meta,switch_sync,switch_candidate;
 reg [5:0] debounce;
 reg [1:0] stable_switches,requested,applied;
 reg epoch,active,fade,due;
 reg [13:0] elapsed;
 reg first_cycle;
 wire [13:0] selected_period_ms=applied==1?PERIOD1_MS:applied==2?PERIOD2_MS:PERIOD0_MS;
 wire [13:0] period_ms=first_cycle?STARTUP_PERIOD_MS:selected_period_ms;
 wire [13:0] fade_start=period_ms-FADE_MS;
 wire eligible=online && feedback[1] && feedback[2] && !actual_emergency;
 assign phase={2'd0,active,applied,due,fade,epoch};
 always @(posedge clk or posedge rst)
  if(rst)begin divider<=0;switch_meta<=0;switch_sync<=0;switch_candidate<=0;debounce<=0;stable_switches<=0;requested<=0;end
  else begin
   switch_meta<=switches;switch_sync<=switch_meta;
   // A held switch must not overwrite a button selection on each tick.
   // A newly debounced switch setting has priority over a coincident release.
   if(period_step)requested<=requested==2?2'd0:requested+1'b1;
   if(millisecond)begin
    divider<=0;
    if(switch_sync!=switch_candidate)begin switch_candidate<=switch_sync;debounce<=0;end
    else if(debounce<DEBOUNCE_MS)debounce<=debounce+1'b1;
    else if(stable_switches!=switch_candidate)begin
     stable_switches<=switch_candidate;
     requested<=switch_candidate==3?2'd0:switch_candidate;
    end
   end else divider<=divider+1'b1;
  end
 always @(posedge clk or posedge rst)
  if(rst)begin epoch<=0;active<=0;fade<=0;due<=0;elapsed<=0;applied<=0;first_cycle<=STARTUP_PERIOD_MS!=0;end
  else if(!eligible || !active || epoch!=feedback[0])begin
   if(active && due && epoch!=feedback[0])first_cycle<=0;
   epoch<=feedback[0];active<=eligible;fade<=0;due<=0;elapsed<=0;applied<=requested;
  end else if(requested!=applied && !fade)begin
   applied<=requested;elapsed<=0;fade<=0;due<=0;
  end else if(millisecond && !due)begin
   // Never start darkening while the next buffer is incomplete. Late TF data
   // extends the previous picture rather than shortening its fade window.
   if(elapsed<fade_start-1 || feedback[3])begin
    if(elapsed==fade_start-1)fade<=1;
    if(elapsed>=fade_start && !feedback[4])elapsed<=elapsed;
    else if(elapsed==period_ms-1)begin elapsed<=period_ms;due<=1;end
    else elapsed<=elapsed+1'b1;
   end
  end
endmodule

