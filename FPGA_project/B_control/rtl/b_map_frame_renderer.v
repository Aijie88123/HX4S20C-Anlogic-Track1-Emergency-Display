// Evaluate the original scene only at retained even coordinates (640x360).
// One immutable B render buffer is held until A acknowledges its complete frame.
module b_map_frame_renderer #(parameter CLK_HZ=50000000,FRAME_PERIOD=2500000,PARTICLE_PAGE=0,ONLY_PARTICLES=0)(
 input clk,rst,enabled,input particle_mode,animation_run,input scene_valid,input [187:0] scene,
 output frame_animation,output reg [8:0] motion_phase,output busy,
 output write_req,input write_ack,write_full,write_done_toggle,
 output reg write_en,output reg [31:0] write_data,output write_cancel,
 output frame_valid,output [1:0] frame_event,input frame_consumed);
 localparam IDLE=0,REQUEST=1,WARM=2,RASTER=3,WAIT_RAM=4,HOLD=5,ABORT=6,PAD=7;
 reg [2:0] state;reg [3:0] warm;reg [4:0] abort_wait;reg [21:0] cooldown;reg [$clog2(CLK_HZ/2)-1:0] blink_count;
 reg blink_phase,blink_frame;reg [187:0] pending_scene,active_scene;reg have_scene;
 reg [11:0] cx,cy;reg [4:0] sample_delay;reg half;reg [15:0] low;
 reg [2:0] finish_sync;reg finish_epoch;reg [1:0] ack_sync,consumed_sync;
 wire [23:0] rgb;wire [7:0] alpha;
 reg animation_q;reg [$clog2(CLK_HZ/60)-1:0] motion_count;
 wire [15:0] particle_pixel;reg [8:0] frame_phase;
 assign frame_animation=animation_q;
 assign busy=state!=IDLE;
 b_particle_shader u_particles(.clk(clk),.x(cx[8:0]),.y(cy[7:0]),.phase(frame_phase),.rgb(particle_pixel));
 reg [4:0] padding_delay;
 wire [15:0] pixel=animation_q?(padding_delay[4]?16'd0:particle_pixel):{rgb[23:19],rgb[15:10],rgb[7:3]};
 wire sample=state==RASTER || state==PAD;
 assign write_req=state==REQUEST;
 assign write_cancel=state==ABORT;
 assign frame_valid=state==HOLD;assign frame_event=active_scene[11:10];
 generate if(!ONLY_PARTICLES)begin: legacy_map
 emergency_map_top #(.REMOTE_MAP(1),.RASTER_STEP(2)) u_renderer(.clk(clk),.rst(rst),.active(!animation_q && (state==WARM||state==RASTER)),
  .state(3'd2),.event_type(active_scene[11:10]),.remote_live(1'b1),.remote_scene(active_scene),
  .blink_on(blink_frame),.frame_tick(state==WARM && warm<3),.cx(cx),.cy(cy),.map_rgb(rgb),.map_alpha(alpha));
 end else begin: particle_only
  assign rgb=0;assign alpha=0;
 end endgenerate
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;animation_q<=0;motion_phase<=0;motion_count<=0;frame_phase<=0;padding_delay<=0;warm<=0;abort_wait<=0;cooldown<=0;blink_count<=0;blink_phase<=0;blink_frame<=0;
   pending_scene<=0;active_scene<=0;have_scene<=0;cx<=0;cy<=0;sample_delay<=0;half<=0;low<=0;
   finish_sync<=0;finish_epoch<=0;ack_sync<=0;consumed_sync<=0;write_en<=0;write_data<=0;
  end else begin
   if(!PARTICLE_PAGE || !particle_mode || animation_run)begin
    if(motion_count==CLK_HZ/60-1)begin motion_count<=0;motion_phase<=motion_phase+1'b1;end else motion_count<=motion_count+1'b1;
   end
   finish_sync<={finish_sync[1:0],write_done_toggle};ack_sync<={ack_sync[0],write_ack};consumed_sync<={consumed_sync[0],frame_consumed};
   if(scene_valid)begin pending_scene<=scene;have_scene<=1;end
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(blink_count==CLK_HZ/2-1)begin blink_count<=0;blink_phase<=~blink_phase;end else blink_count<=blink_count+1'b1;
   sample_delay<={sample_delay[3:0],sample};padding_delay<={padding_delay[3:0],state==PAD};write_en<=0;
   if(sample_delay[4])begin
    if(!half)low<=pixel;else begin write_en<=1;write_data<={pixel,low};end
    half<=~half;
   end
   case(state)
    IDLE:if(enabled && (ONLY_PARTICLES?animation_run:(PARTICLE_PAGE && particle_mode?animation_run:have_scene)) && cooldown==0)begin
     animation_q<=ONLY_PARTICLES || (PARTICLE_PAGE && particle_mode);frame_phase<=motion_phase;active_scene<=pending_scene;blink_frame<=blink_phase;state<=REQUEST;finish_epoch<=finish_sync[2];half<=0;
    end
    REQUEST:if(ack_sync[1])begin state<=WARM;warm<=0;cx<=0;cy<=0;cooldown<=animation_q?CLK_HZ/30-1:FRAME_PERIOD-1;end
    WARM:if(warm==7)state<=RASTER;else warm<=warm+1'b1;
    RASTER:if(cx==(animation_q?319:1278))begin cx<=0;if(cy==(animation_q?179:718))begin cy<=animation_q?180:0;state<=animation_q?PAD:WAIT_RAM;end else cy<=cy+(animation_q?1:2);end else cx<=cx+(animation_q?1:2);
    // 256 invisible pixels make 28,928 words, exactly 113 SDRAM bursts.
    PAD:if(cx==255)begin cx<=0;cy<=0;state<=WAIT_RAM;end else cx<=cx+1'b1;
    WAIT_RAM:if(finish_sync[2]!=finish_epoch)state<=HOLD;
    HOLD:if(consumed_sync[1])state<=IDLE;
    ABORT:begin write_en<=0;sample_delay<=0;half<=0;if(abort_wait==31)begin state<=IDLE;abort_wait<=0;end else abort_wait<=abort_wait+1'b1;end
   endcase
   if(write_en && write_full)begin state<=ABORT;abort_wait<=0;write_en<=0;sample_delay<=0;end
  end
endmodule
