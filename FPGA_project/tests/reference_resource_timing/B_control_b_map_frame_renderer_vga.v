// Native 640x480 2.5D and procedural particles. No low-resolution colour frame
// is magnified here. Scene coordinates are evaluated independently per pixel.
module b_map_frame_renderer_vga #(parameter CLK_HZ=50000000)(
 input clk,rst,enabled,particle_mode,animation_run,scene_valid,input [187:0] scene,
 output frame_animation,output reg [8:0] motion_phase,
 output write_req,input write_ack,write_full,write_done_toggle,
 output write_en,output [31:0] write_data,output write_cancel,
 output frame_valid,output [1:0] frame_event,input frame_consumed);
 localparam IDLE=0,REQUEST=1,WARM=2,RASTER=3,WAIT_RAM=4,HOLD=5,ABORT=6;
 reg [2:0] state;reg [3:0] warm;reg [4:0] abort_wait;reg [21:0] cooldown;
 reg [187:0] pending_scene,active_scene;reg have_scene,animation_q;
 reg [9:0] cx;reg [8:0] cy;reg [4:0] sample_delay;
 reg [2:0] finish_sync;reg [1:0] ack_sync,consumed_sync;reg finish_epoch;
 reg [$clog2(CLK_HZ/60)-1:0] motion_count;
 reg [8:0] frame_phase;
 wire [23:0] rgb;wire [7:0] alpha;wire [15:0] particle;
 wire [11:0] scene_x={1'b0,cx,1'b0};
 wire [11:0] scene_y={3'd0,cy}+{4'd0,cy[8:1]};
 emergency_map_top #(.REMOTE_MAP(1),.RASTER_STEP(2),.RASTER_VGA(1)) u_renderer(
  .clk(clk),.rst(rst),.active(!animation_q && (state==WARM || state==RASTER)),.state(3'd2),
  .event_type(active_scene[11:10]),.remote_live(1'b1),.remote_scene(active_scene),
  .blink_on(frame_phase[5]),.frame_tick(state==WARM && warm<3),.cx(scene_x),.cy(scene_y),.map_rgb(rgb),.map_alpha(alpha));
 b_particle_shader #(.NATIVE_VGA(1)) u_particles(.clk(clk),.x(cx),.y(cy),.phase(frame_phase),.rgb(particle));
 // Phase is held during a frame, so the complete image has one animation epoch.

 wire packed_valid;wire [31:0] packed_data;
 rgb444_packer u_pack(.clk(clk),.rst(rst),.clear(state==REQUEST || state==ABORT || state==IDLE),
  .valid(sample_delay[4]),.rgb565(animation_q?particle:{rgb[23:19],rgb[15:10],rgb[7:3]}),.word_valid(packed_valid),.word_data(packed_data));
 assign frame_animation=animation_q;assign frame_event=active_scene[11:10];
 assign write_req=state==REQUEST;assign write_cancel=rst || state==ABORT;
 assign write_en=packed_valid && !write_full;assign write_data=packed_data;
 assign frame_valid=state==HOLD;
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;warm<=0;abort_wait<=0;cooldown<=0;pending_scene<=0;active_scene<=0;have_scene<=0;animation_q<=0;
   cx<=0;cy<=0;sample_delay<=0;finish_sync<=0;ack_sync<=0;consumed_sync<=0;finish_epoch<=0;motion_count<=0;motion_phase<=0;frame_phase<=0;
  end else begin
   finish_sync<={finish_sync[1:0],write_done_toggle};ack_sync<={ack_sync[0],write_ack};consumed_sync<={consumed_sync[0],frame_consumed};
   sample_delay<={sample_delay[3:0],state==RASTER};
   if(!particle_mode || animation_run)begin
    if(motion_count==CLK_HZ/60-1)begin motion_count<=0;motion_phase<=motion_phase+1'b1;end else motion_count<=motion_count+1'b1;
   end
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(scene_valid)begin pending_scene<=scene;have_scene<=1;end
   case(state)
    IDLE:if(enabled && (particle_mode?animation_run:have_scene) && cooldown==0)begin
     animation_q<=particle_mode;active_scene<=pending_scene;frame_phase<=motion_phase;state<=REQUEST;finish_epoch<=finish_sync[2];
    end
    REQUEST:if(ack_sync[1])begin finish_epoch<=finish_sync[2];state<=WARM;warm<=0;cx<=0;cy<=0;cooldown<=CLK_HZ/30-1;end
    WARM:if(warm==7)state<=RASTER;else warm<=warm+1'b1;
    RASTER:if(cx==639)begin cx<=0;if(cy==479)begin cy<=0;state<=WAIT_RAM;end else cy<=cy+1'b1;end else cx<=cx+1'b1;
    WAIT_RAM:if(finish_sync[2]!=finish_epoch)state<=HOLD;
    HOLD:if(consumed_sync[1])state<=IDLE;
    ABORT:begin sample_delay<=0;if(abort_wait==31)begin state<=IDLE;abort_wait<=0;end else abort_wait<=abort_wait+1'b1;end
   endcase
   if(packed_valid && write_full)begin state<=ABORT;abort_wait<=0;sample_delay<=0;end
  end
endmodule
