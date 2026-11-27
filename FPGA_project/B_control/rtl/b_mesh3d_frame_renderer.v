// Complete 3D frame ownership from immutable geometry through actual SDRAM
// completion and the final A display ACK. Network cancellation is external.
module b_mesh3d_frame_renderer(
 input clk,rst,enabled,input [1:0] current_event,
 input mesh_valid,input [7:0] mesh_count,input [15:0] mesh_id,input [12:0] mesh_meta,
 output reg release_toggle,output [10:0] geometry_address,input [15:0] geometry_data,
 input [8:0] phase,output busy,
 output write_req,input write_ack,write_full,write_done_toggle,
 output write_en,output [31:0] write_data,output write_cancel,
 output frame_valid,output [1:0] frame_event,input frame_consumed);
 localparam IDLE=0,REQUEST=1,RENDER=2,WAIT_RAM=3,HOLD=4;
 reg [2:0] state;reg [2:0] finish_sync;reg [1:0] ack_sync,consumed_sync;
 reg finish_epoch,have_last;reg [15:0] last_id;reg [7:0] count;reg [12:0] meta;
 reg start;wire renderer_busy,renderer_done,word_valid;wire [31:0] word_data;
 assign busy=state!=IDLE;assign write_req=state==REQUEST;assign write_cancel=1'b0;
 assign write_en=state==RENDER && word_valid && !write_full;assign write_data=word_data;
 assign frame_valid=state==HOLD;assign frame_event=meta[1:0];
 b_mesh3d_tile_renderer u_tiles(.clk(clk),.rst(rst),.start(start),.abort(1'b0),.triangle_count(count),.frame_meta(meta),.phase(phase),
  .busy(renderer_busy),.done(renderer_done),.geometry_address(geometry_address),.geometry_data(geometry_data),
  .word_valid(word_valid),.word_data(word_data),.word_ready(state==RENDER && !write_full));
 always @(posedge clk or posedge rst)
  if(rst)begin state<=IDLE;release_toggle<=0;finish_sync<=0;ack_sync<=0;consumed_sync<=0;finish_epoch<=0;have_last<=0;last_id<=0;count<=0;meta<=0;start<=0;end
  else begin
   start<=0;finish_sync<={finish_sync[1:0],write_done_toggle};ack_sync<={ack_sync[0],write_ack};consumed_sync<={consumed_sync[0],frame_consumed};
   case(state)
    IDLE:if(enabled && mesh_valid && (!have_last || mesh_id!=last_id))begin
     last_id<=mesh_id;have_last<=1;
     if(mesh_count==0 || mesh_count>128 || mesh_meta[1:0]!=current_event)release_toggle<=~release_toggle;
     else begin count<=mesh_count;meta<=mesh_meta;finish_epoch<=finish_sync[2];state<=REQUEST;end
    end
    REQUEST:if(ack_sync[1])begin start<=1;state<=RENDER;end
    RENDER:if(renderer_done)begin release_toggle<=~release_toggle;state<=WAIT_RAM;end
    WAIT_RAM:if(finish_sync[2]!=finish_epoch)state<=HOLD;
    HOLD:if(consumed_sync[1])state<=IDLE;
    default:state<=IDLE;
   endcase
  end
endmodule

// The particle renderer and the 3D renderer share the existing B map buffer.
// An owner is not changed until A has acknowledged the complete frame.
module b_dual_scene_renderer #(parameter CLK_HZ=50000000)(
 input clk,rst,connected,enabled,particle_mode,animation_run,
 input scene_valid,input [187:0] scene,
 input mesh_valid,input [7:0] mesh_count,input [15:0] mesh_id,input [12:0] mesh_meta,
 output release_toggle,output [10:0] geometry_address,input [15:0] geometry_data,
 output frame_animation,output [8:0] motion_phase,
 output write_req,input write_ack,write_full,write_done_toggle,
 output write_en,output [31:0] write_data,output write_cancel,
 output frame_valid,output [1:0] frame_event,input frame_consumed);
 reg locked,owner,retiring;reg [5:0] quiet;reg [1:0] consumed_sync;
 reg [1:0] event_type;
 wire local_rst=rst || !connected;
 wire p_req,p_en,p_cancel,p_valid,p_busy,m_req,m_en,m_cancel,m_valid,m_busy;
 wire [31:0] p_data,m_data;wire [1:0] p_event,m_event;
 wire selected_busy=owner?m_busy:p_busy;wire selected_valid=owner?m_valid:p_valid;
 wire worker_enable=locked && !retiring && !local_rst && (selected_busy || (enabled && owner!=particle_mode));
 b_map_frame_renderer #(.CLK_HZ(CLK_HZ),.PARTICLE_PAGE(1),.ONLY_PARTICLES(1)) u_particles(
  .clk(clk),.rst(local_rst),.enabled(worker_enable&&!owner),.particle_mode(particle_mode),.animation_run(animation_run),
  .scene_valid(scene_valid),.scene(scene),.frame_animation(),.motion_phase(motion_phase),.busy(p_busy),
  .write_req(p_req),.write_ack(write_ack&&!owner),.write_full(write_full),.write_done_toggle(write_done_toggle),
  .write_en(p_en),.write_data(p_data),.write_cancel(p_cancel),.frame_valid(p_valid),.frame_event(p_event),.frame_consumed(frame_consumed&&!owner));
 b_mesh3d_frame_renderer u_mesh(.clk(clk),.rst(local_rst),.enabled(worker_enable&&owner),.current_event(event_type),
  .mesh_valid(mesh_valid),.mesh_count(mesh_count),.mesh_id(mesh_id),.mesh_meta(mesh_meta),.release_toggle(release_toggle),
  .geometry_address(geometry_address),.geometry_data(geometry_data),.phase(motion_phase),.busy(m_busy),
  .write_req(m_req),.write_ack(write_ack&&owner),.write_full(write_full),.write_done_toggle(write_done_toggle),
  .write_en(m_en),.write_data(m_data),.write_cancel(m_cancel),.frame_valid(m_valid),.frame_event(m_event),.frame_consumed(frame_consumed&&owner));
 assign write_req=locked && (owner?m_req:p_req);assign write_en=locked && (owner?m_en:p_en);
 assign write_data=owner?m_data:p_data;
 assign write_cancel=local_rst || (quiet!=0 && !locked) || (locked && (owner?m_cancel:p_cancel));
 assign frame_valid=locked && selected_valid && !local_rst;
 assign frame_event=owner?m_event:p_event;assign frame_animation=!owner;
 always @(posedge clk or posedge rst)
  if(rst)begin locked<=0;owner<=0;retiring<=0;quiet<=32;consumed_sync<=0;event_type<=0;end
  else begin
   consumed_sync<={consumed_sync[0],frame_consumed};if(scene_valid)event_type<=scene[11:10];
   if(!connected)begin locked<=0;retiring<=0;quiet<=32;end
   else if(!locked)begin
    if(quiet!=0)quiet<=quiet-1'b1;
    else if(enabled)begin locked<=1;owner<=!particle_mode;retiring<=0;end
   end else if(retiring)begin
    if(!selected_busy)begin locked<=0;retiring<=0;quiet<=8;end
   end else if(selected_valid && consumed_sync[1])retiring<=1;
   else if(!selected_busy && (!enabled || owner==particle_mode))begin locked<=0;quiet<=8;end
  end
endmodule
