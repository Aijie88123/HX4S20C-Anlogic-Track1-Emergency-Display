module map_parent_reference #(parameter NORMAL_ANIMATION=0)(
 input clk,rst,vsync,emergency,input [1:0] event_type,
 input complete,input [1:0] incoming_event,output commit_ready,
 input animation_requested,incoming_animation,
 output reg staging_slot,display_slot,map_mode,output reg have_map,output display_animation);
 reg vs_d;reg [1:0] cached_event;reg cached_animation;
 assign display_animation=cached_animation;
 wire edge_up=vsync&&!vs_d;
 assign commit_ready=edge_up && complete;
 always @(posedge clk or posedge rst)
  if(rst)begin vs_d<=0;staging_slot<=0;display_slot<=1;map_mode<=0;have_map<=0;cached_event<=0;cached_animation<=0;end
  else begin
   vs_d<=vsync;
   if(edge_up)begin
    if(complete)begin
     display_slot<=staging_slot;staging_slot<=display_slot;have_map<=1;cached_event<=incoming_event;cached_animation<=NORMAL_ANIMATION && incoming_animation;
     map_mode<=(emergency && !(NORMAL_ANIMATION && incoming_animation) && event_type==incoming_event) ||
      (NORMAL_ANIMATION && !emergency && animation_requested && incoming_animation);
    end else map_mode<=have_map && ((emergency && !cached_animation && event_type==cached_event) ||
      (NORMAL_ANIMATION && !emergency && animation_requested && cached_animation));
   end
  end
endmodule

