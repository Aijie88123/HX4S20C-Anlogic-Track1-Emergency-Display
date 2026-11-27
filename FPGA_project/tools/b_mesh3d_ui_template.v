// B owns all map UI pixels. Three small synchronous ROMs replace variable
// character decoding; no TF traffic, full-frame bitmap or additional SDRAM.
module b_mesh3d_ui(input clk,input [8:0] x,input [7:0] y,input [12:0] meta,input [8:0] phase,
 input [15:0] base_rgb,input signed [11:0] person_x,person_y,hazard_x,hazard_y,route_x,route_y,
 input have_person,have_hazard,have_route,output reg [15:0] rgb);
 (* rom_style="bram_9k" *) reg [1:0] atlas[0:16383]; /* fehdl force_ram=1, ram_style="bram_9k" */
 (* rom_style="bram_9k" *) reg status[0:16383]; /* fehdl force_ram=1, ram_style="bram_9k" */
 (* rom_style="bram_9k" *) reg [1:0] compass[0:8191]; /* fehdl force_ram=1, ram_style="bram_9k" */
 initial begin
ATLAS_INITIAL
STATUS_INITIAL
COMPASS_INITIAL
 end
 // Label origins are clamped once while B unpacks geometry, not per pixel.
 wire [8:0] px=person_x[8:0],hx=hazard_x[8:0],rx=route_x[8:0];
 wire [7:0] py=person_y[7:0],hy=hazard_y[7:0],ry=route_y[7:0];
 wire [9:0] pdx={1'b0,x}-{1'b0,px},hdx={1'b0,x}-{1'b0,hx},rdx={1'b0,x}-{1'b0,rx};
 wire [8:0] pdy={1'b0,y}-{1'b0,py},hdy={1'b0,y}-{1'b0,hy},rdy={1'b0,y}-{1'b0,ry};
 reg [13:0] address;reg [2:0] region;reg [7:0] local_y;reg [8:0] local_x;
 reg [7:0] tag_row;reg [8:0] ox;reg [7:0] oy;
 always @*begin
  region=0;ox=0;oy=0;tag_row=0;
  if(x>=6 && x<198 && y>=5 && y<33)begin region=1;ox=6;oy=5;end
  else if(x>=218 && x<314 && y>=5 && y<45)begin region=2;ox=218;oy=5;end
  else if(x>=6 && x<134 && y>=166 && y<174)begin region=3;ox=6;oy=166;end
  else if(x>=280 && x<312 && y>=142 && y<174)begin region=4;ox=280;oy=142;end
  else if(meta[10] && x>=6 && x<70 && y>=38 && y<50)begin region=7;ox=6;oy=38;tag_row=244;end
  else if(have_hazard && hdx<64 && hdy<12)begin region=5;ox=hx;oy=hy;tag_row=220;end
  else if(have_person && pdx<64 && pdy<12)begin region=6;ox=px;oy=py;tag_row=208;end
  else if(have_route && !meta[10] && rdx<64 && rdy<12)begin region=7;ox=rx;oy=ry;tag_row=232;end
  local_x=x-ox;local_y=y-oy;address=0;
  if(region==1)address={1'b0,local_y[4:0],local_x[7:0]};
  else if(region==2)address={1'b1,local_y[5:0],local_x[6:0]};
  else if(region>=5)address={tag_row+local_y,local_x[5:0]};
 end
 wire [13:0] status_address={meta[12:11],meta[9:8],local_y[2:0],local_x[6:0]};
 wire [12:0] compass_address={meta[7:5],local_y[4:0],local_x[4:0]};
 reg [1:0] code_q,compass_q;reg status_q;reg [2:0] region_q;reg [5:0] row_q;
 always @(posedge clk)begin
  code_q<=atlas[address];status_q<=status[status_address];compass_q<=compass[compass_address];
  region_q<=region;row_q<=local_y;
 end
 reg [1:0] code;reg [15:0] accent;
 always @*begin
  code=code_q;accent=16'h057f;
  if(region_q==2)accent=row_q<10?16'h07e0:row_q<20?16'h02d3:row_q<30?16'hfb2c:16'h07ff;
  else if(region_q==3)code=status_q?3:1;
  else if(region_q==4)code=compass_q;
  else if(region_q==5)accent=phase[4]?16'hfb2c:16'hd166;
  else if(region_q==7)accent=meta[10]?(phase[4]?16'hfb2c:16'hd166):16'h07e0;
  rgb=base_rgb;
  if(region_q!=0)case(code)
   1:rgb=((base_rgb&16'hf7de)>>1)|16'h0023;
   2:rgb=accent;
   3:rgb=16'hcfff;
   default:rgb=base_rgb;
  endcase
 end
endmodule
