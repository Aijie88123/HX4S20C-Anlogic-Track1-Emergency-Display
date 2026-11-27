`timescale 1ns/1ps
// Small road graph matching the actual u/v=80,256,432 campus lanes.
// Nodes 0..8 are junctions, 9=N,10=W,11=E,12=S. Edges 0..11
// join neighbouring junctions; 12..15 join the four exit spurs.
// Serial Dijkstra shares one comparator/adder over all nodes and edges.
module campus_route_solver(
 input clk,rst,start,input [3:0] origin,input [15:0] closed,
 output reg busy,done,no_path,output reg [15:0] route,directions,
 output reg [3:0] destination,path_length,output reg [51:0] reverse_nodes);
 function [3:0] edge_a;input [3:0] e;begin case(e)
  0:edge_a=0;1:edge_a=1;2:edge_a=3;3:edge_a=4;4:edge_a=6;5:edge_a=7;
  6:edge_a=0;7:edge_a=3;8:edge_a=1;9:edge_a=4;10:edge_a=2;11:edge_a=5;
  12:edge_a=1;13:edge_a=3;14:edge_a=5;15:edge_a=7;
 endcase end endfunction
 function [3:0] edge_b;input [3:0] e;begin case(e)
  0:edge_b=1;1:edge_b=2;2:edge_b=4;3:edge_b=5;4:edge_b=7;5:edge_b=8;
  6:edge_b=3;7:edge_b=6;8:edge_b=4;9:edge_b=7;10:edge_b=5;11:edge_b=8;
  12:edge_b=9;13:edge_b=10;14:edge_b=11;15:edge_b=12;
 endcase end endfunction
 reg [15:0] distance[0:12];reg [3:0] previous[0:12],previous_edge[0:12];
 reg [12:0] visited;reg [15:0] blocked,best_cost;
 reg [3:0] state,scan,best,edge_index,current,root,back,depth;
 wire [3:0] ea=edge_a(edge_index),eb=edge_b(edge_index);
 wire adjacent=(ea==current)||(eb==current);
 wire [3:0] neighbour=(ea==current)?eb:ea;
 wire [15:0] proposed=distance[current]+((edge_index<12)?16'd176:16'd80);
 wire [3:0] predecessor=previous[back],back_edge=previous_edge[back];
 wire forward_direction=(back_edge<12)?(predecessor<back):
                         (back_edge<14)?(predecessor>=9):(predecessor<9);
 integer i;
 always @(posedge clk or posedge rst)
  if(rst)begin
   busy<=0;done<=0;no_path<=1;route<=0;directions<=0;destination<=9;path_length<=0;reverse_nodes<=0;
   visited<=0;blocked<=0;best_cost<=65535;state<=0;scan<=0;best<=15;edge_index<=0;current<=0;root<=0;back<=0;depth<=0;
   for(i=0;i<13;i=i+1)begin distance[i]<=65535;previous[i]<=15;previous_edge[i]<=0;end
  end else begin
   done<=0;
   if(start && !busy)begin
    busy<=1;state<=1;root<=origin;blocked<=closed;visited<=0;scan<=0;
    route<=0;directions<=0;no_path<=0;reverse_nodes<=0;path_length<=0;
   end else case(state)
    1:begin // Initialize one node per clock.
     distance[scan]<=(scan==root)?16'd0:16'hffff;previous[scan]<=15;previous_edge[scan]<=0;
     if(scan==12)begin scan<=0;best<=15;best_cost<=65535;state<=2;end else scan<=scan+1'b1;
    end
    2:begin
     if(!visited[scan] && distance[scan]<best_cost)begin best<=scan;best_cost<=distance[scan];end
     if(scan==12)state<=3;else scan<=scan+1'b1;
    end
    3:begin
     if(best==15)begin no_path<=1;route<=0;busy<=0;done<=1;state<=0;end
     else if(best>=9)begin destination<=best;back<=best;depth<=0;state<=5;end
     else begin current<=best;visited[best]<=1;edge_index<=0;state<=4;end
    end
    4:begin
     if(adjacent && !blocked[edge_index] && !visited[neighbour] && proposed<distance[neighbour])begin
      distance[neighbour]<=proposed;previous[neighbour]<=current;previous_edge[neighbour]<=edge_index;
     end
     if(edge_index==15)begin scan<=0;best<=15;best_cost<=65535;state<=2;end else edge_index<=edge_index+1'b1;
    end
    5:begin // Complete result is published only after bounded backtracking.
     reverse_nodes[depth*4+:4]<=back;
     if(back==root)begin path_length<=depth;busy<=0;done<=1;state<=0;end
     else if(depth==12 || predecessor==15)begin no_path<=1;route<=0;busy<=0;done<=1;state<=0;end
     else begin route[back_edge]<=1;directions[back_edge]<=forward_direction;back<=predecessor;depth<=depth+1'b1;end
    end
   endcase
  end
endmodule

// S2 short release changes the incident; a >=700ms hold changes road closures.
// A long press never also produces a short-press command.
module map_event_button #(parameter integer CLK_HZ=25000000,DEBOUNCE_MS=20,HOLD_MS=700)(
 input clk,rst,button,output reg short_press,long_press);
 reg [1:0] sync;reg stable,held;reg [24:0] debounce,age;
 always @(posedge clk or posedge rst)
  if(rst)begin sync<=3;stable<=1;held<=0;debounce<=0;age<=0;short_press<=0;long_press<=0;end
  else begin
   sync<={sync[0],button};short_press<=0;long_press<=0;
   if(sync[1]==stable)debounce<=0;
   else if(debounce==CLK_HZ/1000*DEBOUNCE_MS-1)begin
    debounce<=0;stable<=sync[1];
    if(!sync[1])begin age<=0;held<=0;end
    else begin if(!held)short_press<=1;age<=0;end
   end else debounce<=debounce+1'b1;
   if(!stable && !held)begin
    if(age==CLK_HZ/1000*HOLD_MS-1)begin long_press<=1;held<=1;end else age<=age+1'b1;
   end
  end
endmodule

// B owns route search, walking along the computed node chain, camera following,
// and fixed-point inverse view projection. A receives one atomic scene packet.
module distributed_map_worker #(
 parameter integer CLK_HZ=25000000,FRAME_CYCLES=416667,DEBOUNCE_MS=20,COMPUTE_VIEW=1
)(input clk,rst,online,input [2:0] actual_state,input [1:0] switches,barrier_mode,
 input stream_ready,output stream_valid,output [223:0] stream_data);
 function [9:0] node_u;input [3:0] n;begin case(n)
  0,3,6:node_u=80;1,4,7,9,12:node_u=256;2,5,8:node_u=432;10:node_u=0;default:node_u=512;
 endcase end endfunction
 function [9:0] node_v;input [3:0] n;begin case(n)
  0,1,2:node_v=80;3,4,5,10,11:node_v=256;6,7,8:node_v=432;9:node_v=0;default:node_v=512;
 endcase end endfunction
 function [3:0] start_node;input [1:0] e;begin case(e)
  0:start_node=6;1:start_node=0;2:start_node=2;3:start_node=8;
 endcase end endfunction
 function [15:0] closures;input [1:0] e,m;reg [15:0] mask;begin
  case(e)0:mask=16'h0080;1:mask=16'h0001;2:mask=16'h0400;3:mask=16'h0020;endcase
  // Additional physical exit-spur closures, not a table of alternative routes.
  if(m==1 || m==2)case(e)
   0:mask=mask|16'h8000;1:mask=mask|16'h2000;2:mask=mask|16'h1000;3:mask=mask|16'h4000;
  endcase
  if(m==2)case(e)
   0:mask=mask|16'h4000;1:mask=mask|16'h8000;2:mask=mask|16'h2000;3:mask=mask|16'h1000;
  endcase
  if(m==3)mask=mask|16'hf000;
  closures=mask;
 end endfunction
 reg [1:0] sw_meta,sw_sync,sw_candidate,zoom;reg [19:0] debounce;
 reg [18:0] frame_count;wire tick=frame_count==FRAME_CYCLES-1;
 reg [1:0] event_q,barrier_q;reg solve_request,have_route;
 wire solver_busy,solver_done,solver_no_path;wire [15:0] solved_route,solved_dirs;
 wire [3:0] solved_exit,solved_length;wire [51:0] solved_nodes;
 reg [15:0] route,dirs,closed;reg no_path;
 reg [51:0] nodes;reg [3:0] walk_index,exit_node;
 reg [9:0] walk_u,walk_v,centre_x,centre_y;
 wire [3:0] target_node=(walk_index==0)?nodes[3:0]:(nodes>>((walk_index-1'b1)*4));
 wire [9:0] target_u=node_u(target_node),target_v=node_v(target_node);
 wire [11:0] guide_x=12'd640+walk_u-walk_v;
 wire [11:0] guide_y=12'd136+((walk_u+{1'b0,walk_v})>>1);
 wire [11:0] exit_x=12'd640+node_u(exit_node)-node_v(exit_node);
 wire [11:0] exit_y=12'd150+((node_u(exit_node)+{1'b0,node_v(exit_node)})>>1);
 wire [9:0] follow_x=(guide_x<360)?10'd360:(guide_x>920)?10'd920:guide_x[9:0];
 wire [9:0] follow_y=(guide_y+32<290)?10'd290:(guide_y+32>530)?10'd530:guide_y[9:0]+10'd32;
 wire [11:0] step=(zoom==1)?12'd2458:(zoom==2)?12'd2048:12'd3072;
 wire signed [23:0] origin_x=$signed({2'd0,centre_x,12'd0})-$signed({3'd0,step,9'd0}+{5'd0,step,7'd0});
 wire signed [23:0] origin_y=$signed({2'd0,centre_y,12'd0})-$signed({4'd0,step,8'd0}+{6'd0,step,6'd0}+{7'd0,step,5'd0}+{9'd0,step,3'd0});
 reg pending,restart;reg [15:0] packet_sequence;reg [187:0] held;
 assign stream_valid=pending && online;
 assign stream_data={36'd0,held};
 campus_route_solver u_solver(.clk(clk),.rst(rst),.start(solve_request),.origin(start_node(event_q)),
  .closed(closures(event_q,barrier_q)),.busy(solver_busy),.done(solver_done),.no_path(solver_no_path),
  .route(solved_route),.directions(solved_dirs),.destination(solved_exit),.path_length(solved_length),.reverse_nodes(solved_nodes));
 always @(posedge clk or posedge rst)
  if(rst)begin
   sw_meta<=0;sw_sync<=0;sw_candidate<=0;zoom<=0;debounce<=0;frame_count<=0;
   event_q<=0;barrier_q<=0;solve_request<=0;have_route<=0;route<=0;dirs<=0;closed<=0;no_path<=1;
   nodes<=0;walk_index<=0;exit_node<=9;walk_u<=80;walk_v<=432;centre_x<=640;centre_y<=404;
   pending<=0;restart<=1;packet_sequence<=0;held<=0;
  end else begin
   sw_meta<=switches;sw_sync<=sw_meta;solve_request<=0;
   if(sw_sync!=sw_candidate)begin sw_candidate<=sw_sync;debounce<=0;end
   else if(debounce<CLK_HZ/1000*DEBOUNCE_MS)debounce<=debounce+1'b1;
   else zoom<=(sw_candidate==3)?2'd0:sw_candidate;
   if(tick)frame_count<=0;else frame_count<=frame_count+1'b1;
   if(!online)begin pending<=0;restart<=1;have_route<=0;centre_x<=640;centre_y<=404;end
   else begin
    if(pending && stream_ready)begin pending<=0;restart<=0;packet_sequence<=packet_sequence+1'b1;end
    if(!solver_busy && !solve_request && (!have_route || event_q!=actual_state[2:1] || barrier_q!=barrier_mode))begin
     event_q<=actual_state[2:1];barrier_q<=barrier_mode;solve_request<=1;have_route<=1;
    end
    if(solver_done)begin
     route<=solved_route;dirs<=solved_dirs;closed<=closures(event_q,barrier_q);no_path<=solver_no_path;
     nodes<=solved_nodes;walk_index<=solved_length;exit_node<=solved_exit;
     walk_u<=node_u(start_node(event_q));walk_v<=node_v(start_node(event_q));
    end
    if(tick && !solver_busy && !solve_request && !solver_done && have_route && event_q==actual_state[2:1] && barrier_q==barrier_mode)begin
     held<={exit_y,exit_x,guide_y,guide_x,closed,dirs,route,step,(COMPUTE_VIEW?origin_y:24'd0),(COMPUTE_VIEW?origin_x:24'd0),
             packet_sequence,2'd0,zoom,event_q,no_path,restart,8'd3};pending<=1;
     if(actual_state[0])begin
      // Two-pixel camera increments avoid jumps after replanning/zoom changes.
      if(centre_x+2<follow_x)centre_x<=centre_x+2'd2;else if(centre_x>follow_x+2)centre_x<=centre_x-2'd2;else centre_x<=follow_x;
      if(centre_y+2<follow_y)centre_y<=centre_y+2'd2;else if(centre_y>follow_y+2)centre_y<=centre_y-2'd2;else centre_y<=follow_y;
      if(!no_path)begin
       if(walk_u<target_u)walk_u<=walk_u+2'd2;else if(walk_u>target_u)walk_u<=walk_u-2'd2;
       else if(walk_v<target_v)walk_v<=walk_v+2'd2;else if(walk_v>target_v)walk_v<=walk_v-2'd2;
       else if(walk_index!=0)walk_index<=walk_index-1'b1;
       else begin walk_index<=solved_length;walk_u<=node_u(start_node(event_q));walk_v<=node_v(start_node(event_q));end
      end
     end
    end
   end
  end
endmodule

// Atomic network->video transfer. A never commits a scene mid-frame. A complete
// received packet may replace a previous pending scene; it cannot tear fields.
module distributed_map_client #(parameter integer TIMEOUT_FRAMES=12)(
 input net_clk,video_clk,rst,online,packet_valid,input [223:0] packet,
 input frame_tick,input [1:0] event_type,
 output live,output [187:0] scene);
 wire delivered;wire [187:0] received;wire ready;
 ethernet_mailbox #(.WIDTH(188)) u_scene_mailbox(
  .src_clk(net_clk),.src_rst(rst),.src_valid(online && packet_valid && packet[7:0]==3 &&
     packet[15:14]==0 && packet[13:12]!=3 && packet[223:188]==0 &&
     (packet[91:80]==3072 || packet[91:80]==2458 || packet[91:80]==2048)),
  .src_data(packet[187:0]),.src_ready(ready),.dst_clk(video_clk),.dst_rst(rst),.dst_valid(delivered),.dst_data(received));
 reg [1:0] online_sync;reg fresh,have_scene;reg [4:0] age;reg [187:0] active_scene;
 wire [15:0] delta=received[31:16]-active_scene[31:16];
 wire new_scene=fresh && received[11:10]==event_type &&
                (!have_scene || received[8] || (delta!=0 && !delta[15]));
 assign scene=active_scene;
 assign live=have_scene && age<TIMEOUT_FRAMES;
 always @(posedge video_clk or posedge rst)
  if(rst)begin online_sync<=0;fresh<=0;have_scene<=0;age<=TIMEOUT_FRAMES;active_scene<=0;end
  else begin
   online_sync<={online_sync[0],online};
   if(delivered)fresh<=1;
   if(frame_tick)begin
    if(!online_sync[1])begin have_scene<=0;age<=TIMEOUT_FRAMES;fresh<=0;end
    else if(new_scene)begin active_scene<=received;have_scene<=1;age<=0;fresh<=delivered;end
    else begin
     if(active_scene[11:10]!=event_type)have_scene<=0;
     if(age<TIMEOUT_FRAMES)age<=age+1'b1;
    end
   end
  end
endmodule

// Incremental inverse projection in A: additions only, no per-pixel multiply.
// cx/cy are the existing sequential raster counters, with cx=0 during blanking.
module map_view_raster #(parameter PIXEL_STEP=1,ROW_SCALE_3_2=0)(
 input clk,rst,input [11:0] cx,cy,input signed [23:0] origin_x,origin_y,input [11:0] step,
 output signed [11:0] scene_x,scene_y);
 reg signed [23:0] acc_x,acc_y;reg [11:0] last_y;
 wire signed [23:0] increment=PIXEL_STEP==2?$signed({11'd0,step,1'b0}):$signed({12'd0,step});
 wire signed [23:0] row_increment=ROW_SCALE_3_2?($signed({12'd0,step})+$signed({13'd0,step[11:1]})):increment;
 wire signed [23:0] next_y=acc_y+row_increment;
 assign scene_x=(cx==0)?origin_x[23:12]:acc_x[23:12];
 assign scene_y=(cy==0)?origin_y[23:12]:(cy!=last_y)?next_y[23:12]:acc_y[23:12];
 always @(posedge clk or posedge rst)
  if(rst)begin acc_x<=0;acc_y<=0;last_y<=0;end
  else begin
   if(cx==0)acc_x<=origin_x+increment;else acc_x<=acc_x+increment;
   if(cy==0)acc_y<=origin_y;else if(cy!=last_y)acc_y<=next_y;
   last_y<=cy;
  end
endmodule
