// B: genuine triangle coverage and reciprocal-Z visibility. A supplies only
// projected vertices; all pixel coverage, depth tests, shading and scanout are B.
// Eight 320-pixel rows fit in BRAM. No full-frame Z allocation is needed.
// Each accepted output word duplicates one source pixel horizontally; each
// source row is emitted twice, preserving the existing 640x360 transport.
module b_mesh3d_tile_renderer(
 input clk,rst,start,abort,input [7:0] triangle_count,input [12:0] frame_meta,
 input [8:0] phase,
 output reg busy,done,output reg [10:0] geometry_address,input [15:0] geometry_data,
 output word_valid,output [31:0] word_data,input word_ready);
 localparam IDLE=0,CLEAR=1,FADDR=2,FWAIT=3,FCAP=4,UNPACK=5,
  OLOAD=6,OWAIT=7,OCAP=8,AREA_CHECK=9,BOUNDS=10,DSTART=11,DWAIT=12,
  RASTER_INIT=13,FRAG_WAIT=14,FRAG_TEST=15,NEXT_TRI=16,SCAN_ADDR=17,SCAN_WAIT=18,SCAN_OUT=19,DRAIN=20;
 reg [4:0] state;reg [4:0] op;reg [3:0] word_index;
 reg [7:0] count,triangle_index;reg [7:0] tile_top;reg [12:0] meta;
 reg [8:0] motion;reg [223:0] packet;
 reg [8:0] scan_x;reg [3:0] scan_row;
 // Four pixel-pairs decouple SDRAM FIFO fullness from the UI ROM address.
 // Fetch credit depends only on registered occupancy, never external ready.
 reg [15:0] output_pixels[0:3];reg [1:0] output_read,output_write;
 reg [2:0] output_count;
 wire scan_room=output_count<4;
 wire scan_advance=state==SCAN_OUT && scan_room && busy && !abort;
 wire output_pop=word_valid && word_ready;
 wire [8:0] next_scan_x=scan_x==319?9'd0:scan_x+1'b1;
 wire [3:0] next_scan_row=scan_x==319?scan_row+1'b1:scan_row;
 wire [8:0] fetch_x=scan_advance?next_scan_x:scan_x;
 wire [3:0] fetch_row=scan_advance?next_scan_row:scan_row;
 wire [11:0] scan_address=fetch_row[3:1]*320+fetch_x;
 reg [11:0] clear_index,tile_index;
 (* ram_style="bram_9k" *) reg [15:0] depth[0:2559]; /* fehdl force_ram=1, ram_style="bram_9k" */
 (* ram_style="bram_9k" *) reg [15:0] colour[0:2559]; /* fehdl force_ram=1, ram_style="bram_9k" */
 reg [15:0] depth_q,colour_q;
 reg signed [9:0] vx0,vx1,vx2,vy0,vy1,vy2;
 reg [15:0] iz0,iz1,iz2,base_colour;reg [3:0] fx;reg [2:0] edge_mask;
 reg signed [9:0] minx,maxx,miny,maxy,px,py;
 // Bounded scene vertices are checked for signed-10-bit range on unpack.
 // Screen-clipped edge values are smaller; use proven 22-bit bounds
 // in area/edge registers; gradients remain 32-bit exactly as before.
 reg signed [21:0] area,e0,e1,e2,erow0,erow1,erow2;
 reg signed [31:0] gx,gy;
 reg signed [10:0] ex0,ex1,ex2,ey0,ey1,ey2;
 reg [10:0] eps0,eps1,eps2;
 reg signed [47:0] temporary,zrow,zcur;
 reg signed [31:0] mul_a;reg signed [10:0] mul_b;reg signed [42:0] product;
 reg div_start;reg [1:0] div_op;reg signed [35:0] numerator,denominator;
 wire div_done,div_busy,div_zero;wire signed [35:0] quotient;
 // |(delta_Z*delta_y - delta_Z*delta_y)<<8| < 2^35.
 mesh3d_divider #(.W(36)) u_div(.clk(clk),.rst(rst),.start(div_start),.numerator(numerator),.denominator(denominator),
  .busy(div_busy),.done(div_done),.zero(div_zero),.quotient(quotient));
 function signed [9:0] lo3;input signed [9:0] a,b,c;begin lo3=a<b?(a<c?a:c):(b<c?b:c);end endfunction
 function signed [9:0] hi3;input signed [9:0] a,b,c;begin hi3=a>b?(a>c?a:c):(b>c?b:c);end endfunction
 function [10:0] magnitude;input signed [10:0] a;begin magnitude=a[10]?-a:a;end endfunction
 wire signed [9:0] raw_minx=lo3(vx0,vx1,vx2),raw_maxx=hi3(vx0,vx1,vx2);
 wire signed [9:0] raw_miny=lo3(vy0,vy1,vy2),raw_maxy=hi3(vy0,vy1,vy2);
 wire covered=e0>=0 && e1>=0 && e2>=0;
 wire zvalid=zcur>0;
 wire [15:0] zvalue=zcur>48'sd16776960 ? 16'hffff:zcur[23:8];
 wire edge_pixel=(edge_mask[0] && e0<eps0)||(edge_mask[1] && e1<eps1)||(edge_mask[2] && e2<eps2);
 reg [15:0] shade;
 always @* begin
  shade=base_colour;
  if(fx==0)begin
   shade=py[6:5]==0?16'h0023:py[6:5]==1?16'h0044:16'h0065;
   if(px[4:0]==0 || py[4:0]==0)shade=16'h00c7;
  end else if(base_colour==16'hd086 || base_colour==16'h9004)shade=motion[4]?16'hb886:16'h9004;
  else if(fx==1 && px[3:0]>=4 && px[3:0]<=9 && py[3:0]>=4 && py[3:0]<=8)shade=16'h230d;
  else if(fx==2 && px[2:0]==2 && py[2:0]==3)shade=16'h1395;
  else if(fx==8 && ((px+py+motion)&15)<3)shade=16'hbff9;
  else if(fx==9 && motion[5])shade=16'h9004;
  if(edge_pixel)shade=(fx==5 || fx==9 || base_colour==16'hd086 || base_colour==16'h9004)?(motion[4]?16'hfb2c:16'hd166):
    (fx==6?16'hffe8:fx==8?16'h07e0:fx==4?16'hffff:fx==3?16'h02d3:16'h13b5);

 end
 wire hit=state==FRAG_TEST && covered && zvalid && zvalue>depth_q;
 always @(posedge clk)begin
  product<=mul_a*mul_b;depth_q<=depth[tile_index];colour_q<=colour[scan_address];
  if(state==CLEAR)begin depth[clear_index]<=0;colour[clear_index]<=16'h0001;end
  else if(hit)begin depth[tile_index]<=zvalue;colour[tile_index]<=shade;end
 end
 wire [7:0] scan_y=tile_top+{5'd0,fetch_row[3:1]};
 // UI is sampled synchronously while SCAN_ADDR/SCAN_WAIT fetch the colour.
 reg signed [11:0] person_x,person_y,hazard_x,hazard_y,route_x,route_y;
 reg have_person,have_hazard,have_route;
 // One shared anchor/clamp path runs only at triangle unpack. This avoids
 // three parallel signed clippers in the 50MHz pixel compositing path.
 wire [3:0] anchor_kind=packet[47:44];
 wire signed [11:0] anchor_x0=anchor_kind==8?$signed(packet[115:104]):$signed(packet[155:144]);
 wire signed [11:0] anchor_y0=anchor_kind==8?$signed(packet[127:116]):$signed(packet[167:156]);
 wire signed [11:0] anchor_x=anchor_x0-(anchor_kind==4?12'sd72:12'sd0);
 wire signed [11:0] anchor_y=anchor_y0+(anchor_kind==4?12'sd32:12'sd0);
 wire [8:0] label_x=anchor_x<3?9'd3:anchor_x>251?9'd251:anchor_x[8:0]+9'd3;
 wire [7:0] label_y=anchor_y<56?8'd38:anchor_y>170?8'd152:anchor_y[7:0]-8'd18;

 wire [15:0] display_colour;
 b_mesh3d_ui u_ui(.clk(clk),.x(fetch_x),.y(scan_y),.meta(meta),.phase(motion),.base_rgb(colour_q),
  .person_x(person_x),.person_y(person_y),.hazard_x(hazard_x),.hazard_y(hazard_y),.route_x(route_x),.route_y(route_y),
  .have_person(have_person),.have_hazard(have_hazard),.have_route(have_route),.rgb(display_colour));
 assign word_valid=output_count!=0 && busy && !abort;
 assign word_data={output_pixels[output_read],output_pixels[output_read]};
 always @(posedge clk or posedge rst)
  if(rst)begin output_read<=0;output_write<=0;output_count<=0;end
  else if(abort)begin output_read<=0;output_write<=0;output_count<=0;end
  else begin
   if(scan_advance)begin output_pixels[output_write]<=display_colour;output_write<=output_write+1'b1;end
   if(output_pop)output_read<=output_read+1'b1;
   case({scan_advance,output_pop})
    2'b10:output_count<=output_count+1'b1;
    2'b01:output_count<=output_count-1'b1;
   endcase
  end
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;op<=0;word_index<=0;count<=0;triangle_index<=0;tile_top<=0;meta<=0;motion<=0;packet<=0;
   clear_index<=0;tile_index<=0;geometry_address<=0;busy<=0;done<=0;
   vx0<=0;vx1<=0;vx2<=0;vy0<=0;vy1<=0;vy2<=0;iz0<=0;iz1<=0;iz2<=0;base_colour<=0;fx<=0;edge_mask<=0;
   minx<=0;maxx<=0;miny<=0;maxy<=0;px<=0;py<=0;area<=0;gx<=0;gy<=0;e0<=0;e1<=0;e2<=0;erow0<=0;erow1<=0;erow2<=0;
   ex0<=0;ex1<=0;ex2<=0;ey0<=0;ey1<=0;ey2<=0;eps0<=0;eps1<=0;eps2<=0;
   temporary<=0;zrow<=0;zcur<=0;mul_a<=0;mul_b<=0;div_start<=0;div_op<=0;numerator<=0;denominator<=1;scan_x<=0;scan_row<=0;person_x<=0;person_y<=0;hazard_x<=0;hazard_y<=0;route_x<=0;route_y<=0;have_person<=0;have_hazard<=0;have_route<=0;
  end else begin
   done<=0;div_start<=0;
   if(abort)begin state<=IDLE;busy<=0;end
   else case(state)
    IDLE:if(start && !div_busy)begin busy<=1;count<=triangle_count;meta<=frame_meta;motion<=phase;tile_top<=0;clear_index<=0;have_person<=0;have_hazard<=0;have_route<=0;state<=CLEAR;end
    CLEAR:if(clear_index==2559)begin triangle_index<=0;word_index<=0;state<=FADDR;end else clear_index<=clear_index+1'b1;
    FADDR:begin geometry_address<={triangle_index[6:0],word_index};state<=FWAIT;end
    FWAIT:state<=FCAP;
    FCAP:begin packet[word_index*16+:16]<=geometry_data;if(word_index==13)state<=UNPACK;else begin word_index<=word_index+1'b1;state<=FADDR;end end
    // Wire coordinates stay 12-bit. Unsupported wider triangles are skipped
    // before truncation, so a corrupted/out-of-envelope vertex cannot wrap.
    UNPACK:if(!(packet[75:74]=={2{packet[73]}} &&
      packet[87:86]=={2{packet[85]}} &&
      packet[115:114]=={2{packet[113]}} &&
      packet[127:126]=={2{packet[125]}} &&
      packet[155:154]=={2{packet[153]}} &&
      packet[167:166]=={2{packet[165]}}))state<=NEXT_TRI;
    else begin
     if(tile_top==0)begin
      if(packet[47:44]==4 && !have_person)begin person_x<={3'd0,label_x};person_y<={4'd0,label_y};have_person<=1;end
      if(packet[47:44]==5 && !have_hazard)begin hazard_x<={3'd0,label_x};hazard_y<={4'd0,label_y};have_hazard<=1;end
      if(packet[47:44]==8 && !have_route)begin route_x<={3'd0,label_x};route_y<={4'd0,label_y};have_route<=1;end
     end
     vx0<=packet[75:64];vy0<=packet[87:76];iz0<=packet[103:88];vx1<=packet[115:104];vy1<=packet[127:116];iz1<=packet[143:128];
     vx2<=packet[155:144];vy2<=packet[167:156];iz2<=packet[183:168];base_colour<=packet[63:48];fx<=packet[47:44];edge_mask<=packet[43:41];
     op<=0;state<=OLOAD;
    end
    OLOAD:begin
     case(op)
      0:begin mul_a<=vx1-vx0;mul_b<=vy2-vy0;end
      1:begin mul_a<=vy1-vy0;mul_b<=vx2-vx0;end
      2:begin mul_a<=$signed({1'b0,iz1})-$signed({1'b0,iz0});mul_b<=vy2-vy0;end
      3:begin mul_a<=$signed({1'b0,iz2})-$signed({1'b0,iz0});mul_b<=vy1-vy0;end
      4:begin mul_a<=$signed({1'b0,iz2})-$signed({1'b0,iz0});mul_b<=vx1-vx0;end
      5:begin mul_a<=$signed({1'b0,iz1})-$signed({1'b0,iz0});mul_b<=vx2-vx0;end
      6:begin mul_a<=gx;mul_b<=minx-vx0;end
      7:begin mul_a<=gy;mul_b<=miny-vy0;end
      8:begin mul_a<=vx1-vx0;mul_b<=miny-vy0;end
      9:begin mul_a<=vy1-vy0;mul_b<=minx-vx0;end
      10:begin mul_a<=vx2-vx1;mul_b<=miny-vy1;end
      11:begin mul_a<=vy2-vy1;mul_b<=minx-vx1;end
      12:begin mul_a<=vx0-vx2;mul_b<=miny-vy2;end
      13:begin mul_a<=vy0-vy2;mul_b<=minx-vx2;end
     endcase
     state<=OWAIT;
    end
    OWAIT:state<=OCAP;
    OCAP:begin
     case(op)
      0,2,4,6,8,10,12:temporary<=product;
      1:begin area<=temporary-product;state<=AREA_CHECK;end
      3,5:begin numerator<=($signed(temporary)-product)<<<8;denominator<=area;div_op<=op==3?0:1;state<=DSTART;end
      7:zrow<=$signed({1'b0,iz0,8'd0})+temporary+product;
      9:erow0<=temporary-product;
      11:erow1<=temporary-product;
      13:begin erow2<=temporary-product;state<=RASTER_INIT;end
     endcase
     if(op==0 || op==2 || op==4 || op==6 || op==7 || op==8 || op==9 || op==10 || op==11 || op==12)begin op<=op+1'b1;state<=OLOAD;end
    end
    AREA_CHECK:if(area==0 || iz0==0 || iz1==0 || iz2==0)state<=NEXT_TRI;
     else begin
      if(area<0)begin vx1<=vx2;vx2<=vx1;vy1<=vy2;vy2<=vy1;iz1<=iz2;iz2<=iz1;edge_mask<={edge_mask[0],edge_mask[1],edge_mask[2]};area<=-area;end
      state<=BOUNDS;
     end
    BOUNDS:begin
     if(raw_maxx<0 || raw_minx>319 || raw_maxy<$signed({4'd0,tile_top}) || raw_miny>$signed({4'd0,tile_top})+7)state<=NEXT_TRI;
     else begin
      minx<=raw_minx<0?0:raw_minx;maxx<=raw_maxx>319?319:raw_maxx;
      miny<=raw_miny<$signed({4'd0,tile_top})?$signed({4'd0,tile_top}):raw_miny;
      maxy<=raw_maxy>$signed({4'd0,tile_top})+7?$signed({4'd0,tile_top})+7:raw_maxy;
      ex0<=vy0-vy1;ex1<=vy1-vy2;ex2<=vy2-vy0;ey0<=vx1-vx0;ey1<=vx2-vx1;ey2<=vx0-vx2;
      eps0<=magnitude(vy0-vy1)+magnitude(vx1-vx0);eps1<=magnitude(vy1-vy2)+magnitude(vx2-vx1);eps2<=magnitude(vy2-vy0)+magnitude(vx0-vx2);
      op<=2;state<=OLOAD;
     end
    end
    DSTART:begin div_start<=1;state<=DWAIT;end
    DWAIT:if(div_done)begin
     if(div_zero)state<=NEXT_TRI;
     else if(div_op==0)begin gx<=quotient;op<=4;state<=OLOAD;end
     else begin gy<=quotient;op<=6;state<=OLOAD;end
    end
    RASTER_INIT:begin
     px<=minx;py<=miny;e0<=erow0;e1<=erow1;e2<=erow2;zcur<=zrow;
     tile_index<=(miny-$signed({4'd0,tile_top}))*320+minx;state<=FRAG_WAIT;
    end
    FRAG_WAIT:state<=FRAG_TEST;
    FRAG_TEST:if(px==maxx)begin
     if(py==maxy)state<=NEXT_TRI;
     else begin
      py<=py+1'b1;px<=minx;erow0<=erow0+ey0;erow1<=erow1+ey1;erow2<=erow2+ey2;
      e0<=erow0+ey0;e1<=erow1+ey1;e2<=erow2+ey2;zrow<=zrow+gy;zcur<=zrow+gy;
      tile_index<=(py+1-$signed({4'd0,tile_top}))*320+minx;state<=FRAG_WAIT;
     end
    end else begin px<=px+1'b1;e0<=e0+ex0;e1<=e1+ex1;e2<=e2+ex2;zcur<=zcur+gx;tile_index<=tile_index+1'b1;state<=FRAG_WAIT;end
    NEXT_TRI:if(triangle_index+1>=count)begin scan_x<=0;scan_row<=0;state<=SCAN_WAIT;end
     else begin triangle_index<=triangle_index+1'b1;word_index<=0;state<=FADDR;end
    SCAN_WAIT:state<=SCAN_OUT;
    SCAN_OUT:if(scan_room)begin
     if(scan_x==319)begin
      scan_x<=0;
      if(scan_row==15 || tile_top==176 && scan_row==7)begin
       if(tile_top==176)state<=DRAIN;
       else begin tile_top<=tile_top+8;clear_index<=0;state<=CLEAR;end
      end else begin scan_row<=next_scan_row;state<=SCAN_OUT;end
     end else begin scan_x<=next_scan_x;state<=SCAN_OUT;end
    end
    DRAIN:if(output_count==0)begin busy<=0;done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
endmodule
