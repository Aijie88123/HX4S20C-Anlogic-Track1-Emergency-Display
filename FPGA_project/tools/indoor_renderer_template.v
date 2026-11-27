`timescale 1ns/1ps
// Native640x480 isometric floor cutaway. Exactly five pixel registers.
// Existing A graph/route/closures/guide and V12 scene interface retained.
module emergency_map_top #(
 parameter integer REMOTE_MAP=0,RASTER_STEP=1,RASTER_VGA=0,ARCHITECTURE_DETAILS=1,
 SCREEN_W=1280,SCREEN_H=720,MAP_XP0=0,MAP_XP1=100,MAP_YP0=0,MAP_YP1=100
)(input clk,rst,active,input [2:0] state,input [1:0] event_type,
 input remote_live,input [187:0] remote_scene,input blink_on,frame_tick,
 input [11:0] cx,cy,output reg [23:0] map_rgb,output reg [7:0] map_alpha);
reg [4:0] flow;
always @(posedge clk or posedge rst)if(rst)flow<=0;else if(active&&frame_tick)flow<=flow+1'b1;
// Restore the original A smooth camera displacement from its V12 viewport.
// A emits origin=(centre<<12)-step*(640,360). The named native map uses
// half-scale coordinates; zero displacement is the original reset centre640,404.
wire [11:0] view_step=remote_scene[91:80];
wire signed [25:0] original_cx_q12=$signed({{2{remote_scene[55]}},remote_scene[55:32]})+
 ($signed({14'd0,view_step})<<<9)+($signed({14'd0,view_step})<<<7);
wire signed [25:0] original_cy_q12=$signed({{2{remote_scene[79]}},remote_scene[79:56]})+
 ($signed({14'd0,view_step})<<<8)+($signed({14'd0,view_step})<<<6)+
 ($signed({14'd0,view_step})<<<5)+($signed({14'd0,view_step})<<<3);
reg signed [13:0] camera_dx,camera_dy;
always @(posedge clk or posedge rst)
 if(rst)begin camera_dx<=0;camera_dy<=0;end
 else begin
  camera_dx<=view_step==0?14'sd0:$signed(original_cx_q12[25:13])-14'sd320;
  camera_dy<=view_step==0?14'sd0:$signed(original_cy_q12[25:13])-14'sd202;
 end
// Existing three zoom scales are retained. Camera registers settle in WARM.
wire [1:0] zoom=remote_scene[13:12];
wire [11:0] ix=RASTER_VGA?cx:(cx>>1),iy=RASTER_VGA?cy:((cy*12'd171)>>8);
wire [11:0] fixed_vx=zoom==2?12'd160+(ix>>1):zoom==1?12'd80+(ix>>1)+(ix>>2):ix;
wire [11:0] fixed_vy=zoom==2?12'd120+(iy>>1):zoom==1?12'd60+(iy>>1)+(iy>>2):iy;
wire signed [13:0] view_x=$signed({2'd0,fixed_vx})+camera_dx;
wire signed [13:0] view_y=$signed({2'd0,fixed_vy})+camera_dy;
wire [11:0] vx=view_x[11:0],vy=view_y[11:0];
// Fixed HUD samples screen coordinates; only the map receives existing zoom.
wire screen_band=iy<54 || iy>=410 || (iy>=58&&iy<90&&(ix<210||ix>=430));
// Clip translated canvas edges and exclude baked HUD artwork from map sampling.
wire map_bounds=view_x>=0&&view_x<640&&view_y>=0&&view_y<480;
wire source_band=vy<54 || vy>=410 || (vy>=58&&vy<90&&(vx<210||vx>=430));
wire map_content=map_bounds&&!source_band;
wire [11:0] image_x=screen_band?ix:map_content?vx:12'd0;
wire [11:0] image_y=screen_band?iy:map_content?vy:12'd100;
wire [14:0] tile_address=({8'd0,image_y[8:2]}<<7)+({8'd0,image_y[8:2]}<<5)+{7'd0,image_x[9:2]};
wire [@INDEX_BITS@-1:0] tile1;reg [3:0] offset1;
indoor_index_rom index_rom(.clk(clk),.address(tile_address),.q(tile1));
wire [3:0] colour2;
indoor_palette_rom palette_rom(.clk(clk),.address({tile1,offset1}),.q(colour2));
reg [10:0] x1,y1,x2,y2,scrx1,scry1;reg screen_band1,screen_band2,map_content1,map_content2;reg valid1,valid2,valid3,valid4;
reg signed [12:0] u2,v2;
wire signed [12:0] world_v=(($signed({1'b0,y1})-13'sd94)<<<1)-($signed({1'b0,x1})-13'sd320);
always @(posedge clk)begin
 offset1<={image_y[1:0],image_x[1:0]};x1<=vx[10:0];y1<=vy[10:0];valid1<=active&&remote_live&&ix<640&&iy<480;
 scrx1<=ix[10:0];scry1<=iy[10:0];screen_band1<=screen_band;screen_band2<=screen_band1;
 map_content1<=map_content;map_content2<=map_content1;
 x2<=x1;y2<=y1;valid2<=valid1;v2<=world_v;
 u2<=($signed({1'b0,x1})-13'sd320)+(($signed({1'b0,y1})-13'sd94)<<<1);
end
// Route geometry shares the exact world coordinates/edge IDs of the existing solver.
reg hhit,vhit;reg [3:0] he,ve;reg [5:0] hp,vp;reg [4:0] ha,va;
reg [2:0] row,col;
always @* begin
 hhit=0;vhit=0;he=0;ve=0;hp=0;vp=0;ha=0;va=0;row=3;col=3;
 if(v2>=70&&v2<=90)row=0;else if(v2>=246&&v2<=266)row=1;else if(v2>=422&&v2<=442)row=2;
 if(u2>=70&&u2<=90)col=0;else if(u2>=246&&u2<=266)col=1;else if(u2>=422&&u2<=442)col=2;
 if(row<3)begin
  if(u2>=80&&u2<=256)begin hhit=1;he={row,1'b0};end
  else if(u2>256&&u2<=432)begin hhit=1;he={row,1'b0}+1'b1;end
  else if(row==1&&u2>=0&&u2<80)begin hhit=1;he=13;end
  else if(row==1&&u2>432&&u2<=512)begin hhit=1;he=14;end
  case(row)0:hp=v2-80;1:hp=v2-256;default:hp=v2-432;endcase
 end
 if(col<3)begin
  if(v2>=80&&v2<=256)begin vhit=1;ve=6+{col,1'b0};end
  else if(v2>256&&v2<=432)begin vhit=1;ve=7+{col,1'b0};end
  else if(col==1&&v2>=0&&v2<80)begin vhit=1;ve=12;end
  else if(col==1&&v2>432&&v2<=512)begin vhit=1;ve=15;end
  case(col)0:vp=u2-80;1:vp=u2-256;default:vp=u2-432;endcase
 end
 ha=hp[5]?-hp:hp;va=vp[5]?-vp:vp;
end
wire [15:0] route=remote_scene[107:92],dirs=remote_scene[123:108],closed=remote_scene[139:124];
wire no_path=remote_scene[9];
wire hroute=hhit&&route[he]&&!closed[he]&&!no_path;
wire vroute=vhit&&route[ve]&&!closed[ve]&&!no_path;
// One consistent width and a chevron every64world units; graph/directions unchanged.
wire [5:0] hphase=(dirs[he]?u2[5:0]:-u2[5:0])-{flow,1'b0};
wire [5:0] vphase=(dirs[ve]?v2[5:0]:-v2[5:0])-{flow,1'b0};
wire line_hit=(hroute&&ha<=8)||(vroute&&va<=8);
wire arrow=(hroute&&ha<=7&&(hphase+ha==32 || hphase+ha==33)) || (vroute&&va<=7&&(vphase+va==32 || vphase+va==33));
wire road_surface=(colour2==11 || colour2==12 || colour2==13);
wire blocked=(hhit&&closed[he])||(vhit&&closed[ve]);
wire hazard=event_type==0?(u2>=106&&u2<=230&&v2>=282&&v2<=406):
 event_type==1?(u2>=106&&u2<=230&&v2>=106&&v2<=230):
 event_type==2?(u2>=282&&u2<=406&&v2>=106&&v2<=230):
 (u2>=282&&u2<=406&&v2>=282&&v2<=406);
// Projected roof/face compensation is visual only. Hazard node and closed mask stay original.
wire hazard_surface=event_type==0?(u2>=80&&u2<=230&&v2>=256&&v2<=406):
 event_type==1?(u2>=80&&u2<=230&&v2>=80&&v2<=230):
 event_type==2?(u2>=256&&u2<=406&&v2>=80&&v2<=230):
 (u2>=256&&u2<=406&&v2>=256&&v2<=406);
wire flame_a=(x2>=222&&x2<=226&&y2>=204-flow[1]&&y2<=212&&(y2>=207||x2==224));
wire flame_b=(x2>=239&&x2<=243&&y2>=206-flow[2]&&y2<=213&&(y2>=209||x2==241));
wire flame=event_type==0&&(flame_a||flame_b)&&hazard_surface&&!road_surface;
wire flame_core=(x2==224&&y2>=208)||(x2==241&&y2>=209);
// Guide coordinates are decoded from original canonical isometric packet fields.
wire signed [13:0] gu=($signed({2'd0,remote_scene[151:140]})-14'sd640+ (($signed({2'd0,remote_scene[163:152]})-14'sd136)<<<1))>>>1;
wire signed [13:0] gv=((($signed({2'd0,remote_scene[163:152]})-14'sd136)<<<1)-($signed({2'd0,remote_scene[151:140]})-14'sd640))>>>1;
wire signed [13:0] gx=14'sd320+((gu-gv)>>>1),gy=14'sd94+((gu+gv)>>>2);
wire guide_head=($signed({3'd0,x2})>=gx-1&&$signed({3'd0,x2})<=gx+1&&$signed({3'd0,y2})>=gy-7&&$signed({3'd0,y2})<=gy-5);
wire guide_body=($signed({3'd0,x2})>=gx-3&&$signed({3'd0,x2})<=gx+3&&$signed({3'd0,y2})>=gy-3&&$signed({3'd0,y2})<=gy+2);
wire guide=guide_head||guide_body;
wire exit_area=(u2>=244&&u2<=268&&(v2<24||v2>488))||(v2>=244&&v2<=268&&(u2<24||u2>488));
wire exit_closed=v2<24?closed[12]:u2<24?closed[13]:u2>488?closed[14]:closed[15];
// Compact1-bit status atlas: values come from existing scene fields only.
wire [2:0] exit_id=remote_scene[187:176]>400?(remote_scene[175:164]>640?3'd3:3'd4):(remote_scene[175:164]>640?3'd1:3'd2);
wire [2:0] open_exits=3'd4-{2'd0,closed[12]}-{2'd0,closed[13]}-{2'd0,closed[14]}-{2'd0,closed[15]};
reg [4:0] hud_row;reg [6:0] hud_x;reg [3:0] hud_y;reg hud_on1;reg [2:0] hud_zone1;
always @* begin
 hud_row=0;hud_x=0;hud_y=0;hud_on1=0;hud_zone1=0;
 if(scry1>=65&&scry1<81&&scrx1>=50&&scrx1<178)begin hud_row=18+event_type;hud_x=scrx1-50;hud_y=scry1-65;hud_on1=1;hud_zone1=0;end
 else if(scry1>=445&&scry1<461)begin
  hud_y=scry1-445;
  if(scrx1>=29&&scrx1<157)begin hud_row={3'd0,event_type};hud_x=scrx1-29;hud_on1=1;hud_zone1=0;end
  else if(scrx1>=179&&scrx1<307)begin hud_row=no_path?5'd8:5'd3+exit_id;hud_x=scrx1-179;hud_on1=1;hud_zone1=1;end
  else if(scrx1>=329&&scrx1<457)begin hud_row=9+event_type;hud_x=scrx1-329;hud_on1=1;hud_zone1=2;end
  else if(scrx1>=479&&scrx1<607)begin hud_row=13+open_exits;hud_x=scrx1-479;hud_on1=1;hud_zone1=3;end
 end
end
wire [15:0] hud_address={hud_row,hud_y,hud_x};wire [7:0] hud_byte2;
refine2_hud_bytes_rom hud_font(.clk(clk),.address(hud_address[15:3]),.q(hud_byte2));
reg [2:0] hud_sub2,hud_zone2;reg hud_on2;
always @(posedge clk)begin hud_sub2<=hud_address[2:0];hud_zone2<=hud_zone1;hud_on2<=hud_on1;end
wire hud_pixel2=hud_on2&&hud_byte2[hud_sub2];
function [23:0] palette;input [3:0] i;begin case(i)
@PALETTE@
endcase end endfunction
reg [23:0] base3,hud_colour3;reg [1:0] danger_tone3;reg hud3,flame3,flame_core3;reg line3,arrow3,block3,danger3,guide3,exit3,exitclosed3,blink3;
reg [23:0] rgb4;
always @(posedge clk)begin
 valid3<=valid2;base3<=palette(colour2);
 line3<=road_surface&&line_hit&&!screen_band2&&map_content2;arrow3<=road_surface&&arrow&&!screen_band2&&map_content2;
 block3<=road_surface&&blocked&&(u2[3]^v2[3])&&!screen_band2&&map_content2;
 danger3<=hazard_surface&&((colour2>=4&&colour2<=8)||colour2>=14)&&!screen_band2&&map_content2;
 danger_tone3<=colour2==8?2'd3:colour2==7?2'd2:colour2==6?2'd1:2'd0;guide3<=guide&&!no_path&&!screen_band2&&map_content2;
 exit3<=exit_area&&u2>=0&&u2<=512&&v2>=0&&v2<=512&&!screen_band2&&map_content2;exitclosed3<=exit_closed;
 flame3<=flame&&!screen_band2&&map_content2;flame_core3<=flame_core;hud3<=hud_pixel2;
 case(hud_zone2)
  0:hud_colour3<=event_type==0?24'hff8855:event_type==1?24'hffbb66:24'h88ddcc;
  1:hud_colour3<=no_path?24'hff8855:24'h55ff99;
  2:hud_colour3<=24'hff9955;
  default:hud_colour3<=open_exits==0?24'hff8855:24'h55ddcc;
 endcase
 blink3<=blink_on;valid4<=valid3;
 if(hud3)rgb4<=hud_colour3;
 else if(flame3)rgb4<=flame_core3?24'hffee88:24'hffaa33;
 else if(exit3)rgb4<=exitclosed3?24'hee5544:24'h33ddbb;
 else if(guide3)rgb4<=24'hffdd44;
 else if(block3)rgb4<=24'hdd5544;
 else if(arrow3)rgb4<=24'haaffcc;
 else if(line3)rgb4<=24'h44ee88;
 else if(danger3)case(danger_tone3)
  0:rgb4<=blink3?24'h662222:24'h551122;
  1:rgb4<=blink3?24'h883322:24'h772222;
  2:rgb4<=blink3?24'h993322:24'h882222;
  default:rgb4<=blink3?24'hee6633:24'hdd5533;
 endcase
 else rgb4<=base3;
 if(rst)begin map_rgb<=0;map_alpha<=0;end else begin map_rgb<=valid4?rgb4:24'd0;map_alpha<=valid4?8'hff:8'd0;end
end
endmodule
