// IMAGE_ROLES complete frame roles plus one distinct staging slot.
// Commit during the start of VS, before scanout's end-of-VS RAM read request.
module a_media_cached_control #(parameter CLK_FREQ_HZ=100000000,FADE_MS=160,NORMAL_PERIOD_MS=3000,EMER_DWELL_MS=2000,IMAGE_ROLES=5,EMER_SEQUENCE=0,EMER_WAIT_MS=5000,STRICT_PRELUDE=0,STRICT_ORDER=0,NORMAL_ANIMATION=0,PRIME_PAUSED_ANIMATION=0,FIXED_SLOTS=0)(
 input clk,rst,key_next,key_auto,emergency,vsync,input [8:0] remote_phase,input animation_visible,
 input incoming_complete,input [2:0] incoming_role,input [15:0] incoming_w,incoming_h,
 output incoming_commit_ready,output reg [2:0] staging_slot,display_slot,
 output reg display_valid,output reg [2:0] page_index,
 output reg [15:0] disp_src_w,disp_src_h,output reg disp_src_toggle,disp_audio_emergency,
 output load_nearly_done,load_visual_active,output auto_play_en_out,
 output [4:0] carousel_feedback,output [1:0] interval_selection,
 output reg brightness_step_toggle,contrast_step_toggle,
 output reg [1:0] map_view_mode,output [IMAGE_ROLES-1:0] cached_roles,output [3:0] state_code,output emergency_map_ready,output normal_animation,output normal_animation_ready);
 reg [2:0] slot[0:IMAGE_ROLES-1];reg [IMAGE_ROLES*32-1:0] sizes;reg [IMAGE_ROLES-1:0] valid;
 reg [1:0] emergency_stage;reg animation_latched;
 reg [1:0] animation_visible_sync;
 localparam EW=$clog2(FADE_MS+1)>0?$clog2(FADE_MS+1):1;
 reg [EW-1:0] emergency_fade_wait;
 wire emergency_fade_complete=!FIXED_SLOTS || emergency_fade_wait>=FADE_MS;
 reg [2:0] vs_sync,em_sync;reg previous_emergency,mode_pending;
 wire blank_start=vs_sync[2]&&!vs_sync[1];
 // vs_sync[1] rises first; detect that rise rather than the falling edge.
 wire commit_edge=vs_sync[1]&&!vs_sync[2];
 assign normal_animation=NORMAL_ANIMATION && animation_latched && !em_sync[2];
 wire emer=em_sync[2];wire mode_change=emer!=previous_emergency;
 assign emergency_map_ready=!EMER_SEQUENCE || (emer && emergency_stage==2);

 wire next_press,auto_press,next_long,auto_long;
 key_short_long #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(6),.HOLD_MS(1400),.REPEAT_MS(300))
  u_key_next(.clk(clk),.rst(rst),.button_in(key_next),.short_pulse(next_press),.long_step(next_long));
 key_short_long #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(6),.HOLD_MS(1400),.REPEAT_MS(300))
  u_key_auto(.clk(clk),.rst(rst),.button_in(key_auto),.short_pulse(auto_press),.long_step(auto_long));
 // S2 is free after the emergency pictures. Short releases select limited
 // 3D yaw modes: automatic sweep, left, centre, right. Long presses retain
 // the original brightness adjustment and never also change the camera.
 always @(posedge clk or posedge rst)
  if(rst)map_view_mode<=0;
  else if(emer && emergency_map_ready && next_press)map_view_mode<=map_view_mode+1'b1;
 reg auto_play;reg [2:0] saved_normal;reg saved_animation;reg manual_pending;reg [7:0] manual_elapsed;
 localparam DIV=CLK_FREQ_HZ/1000;
 localparam DW=$clog2(DIV)>0?$clog2(DIV):1;
 reg [DW-1:0] divider;reg [13:0] elapsed;
 // Millisecond counters are slow state. Register their comparisons before
 // the requested-role mux/reset enables; this breaks the elapsed->compare->
 // role selection->timer CE path without changing the configured periods.
 reg ordinary_due,ordinary_fade_due,emergency_due,emergency_fade_due,emergency_wait_due;
 always @(posedge clk or posedge rst)
  if(rst)begin ordinary_due<=0;ordinary_fade_due<=0;emergency_due<=0;emergency_fade_due<=0;emergency_wait_due<=0;end
  else begin
   ordinary_due<=elapsed>=NORMAL_PERIOD_MS;ordinary_fade_due<=elapsed>=NORMAL_PERIOD_MS-FADE_MS;
   emergency_due<=elapsed>=EMER_DWELL_MS;emergency_fade_due<=elapsed>=EMER_DWELL_MS-FADE_MS;
   emergency_wait_due<=elapsed>=EMER_WAIT_MS;
  end
 wire millisecond=divider==DIV-1;
 wire remote_online=remote_phase[8];
 wire remote_current=remote_online&&remote_phase[5]&&remote_phase[0]==disp_src_toggle;
 // Automatic playback ends at the animation; explicit browsing may wrap.
 localparam MANUAL_ANIMATION = NORMAL_ANIMATION && STRICT_ORDER;
 localparam FAST_MANUAL = MANUAL_ANIMATION && IMAGE_ROLES!=8;
 localparam ANIMATION_PAGE=IMAGE_ROLES==8?7:4;
 reg [2:0] ordinary_next,ordinary_first,manual_next,requested;
 reg request_change;
 always @* begin
  ordinary_first=STRICT_ORDER?2:valid[2]?2:valid[3]?3:valid[4]?4:(IMAGE_ROLES-1);
  if(STRICT_ORDER)begin
   if(IMAGE_ROLES==8)ordinary_next=page_index>=2 && page_index<7?page_index+1'b1:3'd2;
   else case(page_index)2:ordinary_next=3;3:ordinary_next=4;4:ordinary_next=NORMAL_ANIMATION?4:IMAGE_ROLES==6?5:2;default:ordinary_next=2;endcase
  end else case(page_index)
   2:ordinary_next=valid[3]?3:valid[4]?4:(IMAGE_ROLES==6 && valid[5])?5:2;
   3:ordinary_next=valid[4]?4:(IMAGE_ROLES==6 && valid[5])?5:valid[2]?2:3;
   4:ordinary_next=(IMAGE_ROLES==6 && valid[5])?5:valid[2]?2:valid[3]?3:4;
   default:ordinary_next=valid[2]?2:valid[3]?3:valid[4]?4:page_index;
  endcase
  if(NORMAL_ANIMATION && page_index==ANIMATION_PAGE)ordinary_next=ANIMATION_PAGE;
  manual_next=ordinary_next;
  if(MANUAL_ANIMATION && page_index==ANIMATION_PAGE && animation_latched)manual_next=2;
  requested=page_index;request_change=0;
  if(!display_valid && (STRICT_ORDER?valid[2]:|valid[IMAGE_ROLES-1:2]))begin requested=ordinary_first;request_change=1;end
  if(emer && EMER_SEQUENCE)begin
   if(emergency_stage==0)begin
    if(FIXED_SLOTS && page_index==0 && !mode_pending && valid[1] && emergency_due && emergency_fade_complete)begin requested=1;request_change=1;end
    else if(valid[0] && (page_index!=0 || mode_pending))begin requested=0;request_change=1;end
    else if(!STRICT_PRELUDE && !valid[0] && valid[1] && (page_index!=1 || mode_pending))begin requested=1;request_change=1;end
   end else if(emergency_stage==1 && valid[1] && page_index!=1)begin requested=1;request_change=1;end
  end else if(emer)begin
   if(mode_pending || page_index>=2)begin
    if(valid[0])begin requested=0;request_change=1;end
    else if(valid[1])begin requested=1;request_change=1;end
   end else if((next_press || emergency_due) && valid[0]&&valid[1])begin
    requested=page_index==0?1:0;request_change=1;
   end
  end else begin
   if((mode_pending || page_index<2) && |valid[IMAGE_ROLES-1:2])begin requested=valid[saved_normal]?saved_normal:ordinary_first;request_change=1;end
   else if(page_index>=2)begin
    if(manual_pending && !auto_press && manual_next!=page_index && valid[manual_next] &&
       (FAST_MANUAL || manual_elapsed>=FADE_MS))begin
     requested=manual_next;request_change=1;
    end else if(!manual_pending && ordinary_next!=page_index && valid[ordinary_next] &&
       auto_play && (remote_current?remote_phase[2]:!remote_online && ordinary_due))begin
     requested=ordinary_next;request_change=1;
    end
   end
  end
 end
 wire ready_next=display_valid && !emer && ordinary_next!=page_index && valid[ordinary_next];
 wire animation_prelude=NORMAL_ANIMATION && display_valid && !emer && page_index==ANIMATION_PAGE && !animation_latched;
 wire manual_ready=display_valid && !emer && valid[manual_next] && (manual_next!=page_index || animation_prelude);
 wire fade=(!FAST_MANUAL && manual_ready && manual_pending) ||
  ((ready_next || animation_prelude) && auto_play && (remote_current?remote_phase[1]:!remote_online && ordinary_fade_due)) ||
  (normal_animation && !animation_visible_sync[1]) ||
  (emer && display_valid && valid[0]&&valid[1] && emergency_fade_due &&
   (!EMER_SEQUENCE || (emergency_stage==0 && page_index==0)) && (!FIXED_SLOTS || emergency_fade_wait!=0)) ||
  (FIXED_SLOTS && emer && display_valid && page_index==1 && emergency_stage>=1 &&
   emergency_fade_due && emergency_fade_wait!=0 && !animation_visible_sync[1]);
 assign load_nearly_done=fade;assign load_visual_active=fade;
 assign normal_animation_ready=normal_animation && elapsed>=FADE_MS;
 assign auto_play_en_out=auto_play;
 wire carousel_ready=ready_next || (NORMAL_ANIMATION && display_valid && !emer && page_index==ANIMATION_PAGE && !animation_latched);
 // A paused first visit still needs a complete animation frame. Reuse the
 // existing run bit until the video domain actually selects that complete frame.
 // This does not change the user's PLAY/PAUSE state or add a protocol field.
 always @(posedge clk or posedge rst)
  if(rst)animation_visible_sync<=0;
  else animation_visible_sync<={animation_visible_sync[0],animation_visible};
 wire prepare_first=PRIME_PAUSED_ANIMATION && normal_animation && !animation_visible_sync[1];
 assign carousel_feedback={carousel_ready,carousel_ready,auto_play || prepare_first,display_valid,disp_src_toggle};
 assign interval_selection=remote_online?remote_phase[4:3]:0;
 assign incoming_commit_ready=commit_edge && incoming_complete;
 assign cached_roles=valid;
 assign state_code=display_valid?4'd7:4'd2;
 wire incoming_new=incoming_complete && (!FIXED_SLOTS || !valid[incoming_role]);
 integer i;reg [2:0] selected_slot;reg [31:0] selected_size;
 always @(posedge clk or posedge rst)
  if(rst)begin
   valid<=0;sizes<=0;staging_slot<=FIXED_SLOTS?0:IMAGE_ROLES;display_slot<=2;display_valid<=0;page_index<=2;
   disp_src_w<=0;disp_src_h<=0;disp_src_toggle<=0;disp_audio_emergency<=0;
   vs_sync<=0;em_sync<=0;previous_emergency<=0;mode_pending<=0;auto_play<=1;saved_normal<=2;saved_animation<=0;
   manual_pending<=0;manual_elapsed<=0;divider<=0;elapsed<=0;emergency_stage<=0;animation_latched<=0;emergency_fade_wait<=0;
   brightness_step_toggle<=0;contrast_step_toggle<=0;
   for(i=0;i<IMAGE_ROLES;i=i+1)slot[i]<=i;
  end else begin
   vs_sync<={vs_sync[1:0],vsync};em_sync<={em_sync[1:0],emergency};
   previous_emergency<=emer;
   if(next_long)brightness_step_toggle<=~brightness_step_toggle;
   if(auto_long)contrast_step_toggle<=~contrast_step_toggle;
   if(millisecond)begin
    divider<=0;
    if(display_valid && (emer || auto_play || (normal_animation && !animation_visible_sync[1])) && elapsed<10000)elapsed<=elapsed+1'b1;
    if(manual_pending && valid[ordinary_next] && manual_elapsed<FADE_MS)manual_elapsed<=manual_elapsed+1'b1;
   end else divider<=divider+1'b1;
   // A slow 06 arrival must still receive the whole fade-out window. Do
   // not advance merely because the 05 dwell elapsed while 06 was absent.
   if(!FIXED_SLOTS || !emer || mode_change)emergency_fade_wait<=0;
   else if(millisecond && display_valid && emergency_fade_due &&
      ((emergency_stage==0 && page_index==0 && valid[1] && !mode_pending) ||
       (emergency_stage>=1 && page_index==1)) && !emergency_fade_complete)
    emergency_fade_wait<=emergency_fade_wait+1'b1;
   if(auto_press && !emer && display_valid)begin auto_play<=~auto_play;elapsed<=0;manual_pending<=0;end
   if(next_press && !emer && display_valid && (MANUAL_ANIMATION || ordinary_next!=page_index))begin manual_pending<=1;manual_elapsed<=0;end
   if(commit_edge && NORMAL_ANIMATION && !animation_latched && !emer && page_index==ANIMATION_PAGE && display_valid && !mode_pending &&
      (!MANUAL_ANIMATION && next_press || !manual_pending && auto_play &&
       (remote_current?remote_phase[2]:!remote_online && ordinary_due)))begin animation_latched<=1;elapsed<=FADE_MS;disp_src_toggle<=~disp_src_toggle;end
   if(mode_change)begin mode_pending<=1;elapsed<=0;manual_pending<=0;emergency_stage<=0;if(emer && page_index>=2)begin saved_normal<=page_index;saved_animation<=animation_latched;end end
   if(EMER_SEQUENCE && emer && next_press && emergency_stage!=2)elapsed<=EMER_DWELL_MS;
   if(commit_edge)begin
    // Manual requests use complete local frames at VS; no TF/network reload,
    // fade timer or round-trip dependency. Starting animation is a distinct step.
    if(MANUAL_ANIMATION && manual_pending && !auto_press && !emer && !mode_change &&
       !mode_pending && page_index==ANIMATION_PAGE && !animation_latched && (FAST_MANUAL || manual_elapsed>=FADE_MS))begin
     animation_latched<=1;manual_pending<=0;elapsed<=FADE_MS;
     disp_src_toggle<=~disp_src_toggle;
    end
    if(EMER_SEQUENCE && emer && !mode_change)begin
     if(emergency_stage==0)begin
      if((request_change && requested==1) || (page_index==0 && !mode_pending && emergency_due && (!FIXED_SLOTS || valid[1]) && emergency_fade_complete) ||
        (!STRICT_PRELUDE && !valid[0] && !valid[1] && emergency_wait_due))begin emergency_stage<=1;elapsed<=0;emergency_fade_wait<=0;end
     end else if(emergency_stage==1)begin
      if((page_index==1 && emergency_due && emergency_fade_complete) || (!STRICT_PRELUDE && !valid[1] && emergency_wait_due))begin
       emergency_stage<=2;mode_pending<=0;if(!FIXED_SLOTS)elapsed<=0;
      end
     end
    end
    // One permutation swap maintains distinct complete roles and a free slot.
    if(incoming_new && incoming_role<IMAGE_ROLES)begin
     if(!FIXED_SLOTS)begin slot[incoming_role]<=staging_slot;staging_slot<=slot[incoming_role];end
     valid[incoming_role]<=1;
     sizes[incoming_role*32 +:32]<={incoming_h,incoming_w};
    end
    if(request_change || (incoming_new && incoming_role==page_index) || mode_pending)begin
     selected_slot=slot[requested];selected_size=sizes[requested*32 +:32];
     if(incoming_new && incoming_role==requested)begin selected_slot=FIXED_SLOTS?incoming_role:staging_slot;selected_size={incoming_h,incoming_w};end
     if(valid[requested] || (incoming_new && incoming_role==requested))begin
      display_slot<=selected_slot;page_index<=requested;display_valid<=1;
      if(MANUAL_ANIMATION && !emer)begin
       if(requested!=ANIMATION_PAGE)animation_latched<=0;
       else if(mode_pending)animation_latched<=saved_animation;
      end
      disp_src_w<=selected_size[15:0];disp_src_h<=selected_size[31:16];
      disp_src_toggle<=~disp_src_toggle;disp_audio_emergency<=emer;
      elapsed<=0;manual_pending<=0;manual_elapsed<=0;mode_pending<=0;
     end
    end
   end
  end
endmodule

