// A: camera, XYZ vertex transforms, perspective division and reciprocal depth.
// Every emitted scene is immutable until its final acknowledged triangle.
module a_mesh3d_projector #(parameter CLK_HZ=25000000,FRAME_PERIOD=833333)(
 input clk,rst,online,active,input [1:0] event_type,view_mode,
 input packet_valid,input [223:0] packet,
 output triangle_valid,output [223:0] triangle,input triangle_ready);
 reg [15:0] geometry[0:1023]; /* fehdl force_ram=1, ram_style="bram" */
 initial begin
GEOMETRY_INITIAL
 end
 function [19:0] trig;input [5:0] a;begin case(a)
TRIG_CASE
  default:trig=20'd0;
 endcase end endfunction
 localparam IDLE=0,RADDR=1,RWAIT=2,RCAP=3,DECODE=4,VLOAD=5,
  OPLOAD=6,OPWAIT=7,OPCAP=8,DIVSTART=9,DIVWAIT=10,EMIT=11,NEXT=12;
 reg [3:0] state;reg [3:0] op;reg [1:0] vertex,div_op;
 reg [2:0] word_index;reg [6:0] index;reg [9:0] address;
 reg [15:0] rom_q;reg [127:0] record;
 reg [187:0] latest,scene;reg have_scene;
 reg [15:0] frame_id;reg [223:0] held;
 reg [21:0] cooldown,auto_count;reg [6:0] orbit;
 reg [5:0] yaw;reg [1:0] zoom,mode;
 reg signed [9:0] sine,cosine;
 reg signed [12:0] focus_u,focus_v,person_u,person_v,hazard_u,hazard_v,hazard_h;
 reg signed [12:0] du,dv,height,rx,rz,cam_y,cam_z;
 reg signed [31:0] temporary;
 reg signed [24:0] mul_a;reg signed [12:0] mul_b;reg signed [37:0] product;
 reg signed [11:0] sx[0:2],sy[0:2];reg [15:0] iz[0:2];
 reg [15:0] colour;reg [3:0] kind,reference_id,fx;reg [2:0] edge_mask;
 reg div_start;reg signed [31:0] numerator,denominator;
 wire div_busy,div_done,div_zero;wire signed [31:0] quotient;
 mesh3d_divider #(.W(32)) u_div(.clk(clk),.rst(rst),.start(div_start),.numerator(numerator),.denominator(denominator),
  .busy(div_busy),.done(div_done),.zero(div_zero),.quotient(quotient));
 wire signed [31:0] incoming_u=$signed({1'b0,latest[163:152]})-32'sd136+(($signed({1'b0,latest[151:140]})-32'sd640)>>>1);
 wire signed [31:0] incoming_v=$signed({1'b0,latest[163:152]})-32'sd136-(($signed({1'b0,latest[151:140]})-32'sd640)>>>1);
 wire [5:0] auto_yaw=orbit<=63?orbit[5:0]:7'd126-orbit;
 wire [5:0] selected_yaw=view_mode==1?0:view_mode==2?32:view_mode==3?63:auto_yaw;
 wire [19:0] selected_trig=trig(selected_yaw);
 wire signed [12:0] focal=zoom==1?13'sd300:zoom==2?13'sd360:13'sd240;
 wire [31:0] raw_vertex=record>>(vertex*32);
 reg signed [12:0] wu,wv,wh;
 always @* begin
  wu=$signed(raw_vertex[10:0]);wv=$signed(raw_vertex[21:11]);wh=$signed(raw_vertex[31:22]);
  if(kind==4)begin wu=wu+person_u;wv=wv+person_v;end
  else if(kind==5)begin wu=wu+hazard_u;wv=wv+hazard_v;wh=wh+hazard_h;end
  else if(kind==6)case(reference_id)
   0:begin wu=wu+256;end
   1:begin wv=wv+256;end
   2:begin wu=wu+512;wv=wv+256;end
   default:begin wu=wu+256;wv=wv+512;end
  endcase
 end
 always @(posedge clk)begin rom_q<=geometry[address];product<=mul_a*mul_b;end
 assign triangle_valid=state==EMIT && online;
 assign triangle=held;
 integer i;
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;op<=0;vertex<=0;div_op<=0;word_index<=0;index<=0;address<=0;record<=0;
   latest<=0;scene<=0;have_scene<=0;frame_id<=0;held<=0;cooldown<=0;auto_count<=0;orbit<=32;
   yaw<=32;zoom<=0;mode<=0;sine<=-181;cosine<=181;
   focus_u<=256;focus_v<=256;person_u<=0;person_v<=0;hazard_u<=0;hazard_v<=0;hazard_h<=0;
   du<=0;dv<=0;height<=0;rx<=0;rz<=0;cam_y<=0;cam_z<=900;temporary<=0;
   mul_a<=0;mul_b<=0;colour<=0;kind<=0;reference_id<=0;fx<=0;edge_mask<=0;
   div_start<=0;numerator<=0;denominator<=1;
   for(i=0;i<3;i=i+1)begin sx[i]<=0;sy[i]<=0;iz[i]<=0;end
  end else begin
   div_start<=0;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(active && online)begin
    if(auto_count==CLK_HZ/20-1)begin auto_count<=0;orbit<=orbit==125?0:orbit+1'b1;end else auto_count<=auto_count+1'b1;
   end
   if(packet_valid && packet[7:0]==3 && packet[15:14]==0 && packet[13:12]!=3 && packet[223:188]==0)begin latest<=packet[187:0];have_scene<=1;end
   if(!online)begin state<=IDLE;have_scene<=0;cooldown<=0;end
   else if(!active)begin state<=IDLE;cooldown<=0;focus_u<=256;focus_v<=256;end
   else case(state)
    IDLE:if(have_scene && latest[11:10]==event_type && cooldown==0 && !div_busy)begin
     scene<=latest;frame_id<=frame_id+1'b1;index<=0;word_index<=0;state<=RADDR;
     yaw<=selected_yaw;sine<=$signed(selected_trig[19:10]);cosine<=$signed(selected_trig[9:0]);zoom<=latest[13:12];mode<=view_mode;
     person_u<=incoming_u;person_v<=incoming_v;
     focus_u<=256+((incoming_u-256)>>>1);focus_v<=256+((incoming_v-256)>>>1);
     case(event_type)
      0:begin hazard_u<=133;hazard_v<=344;hazard_h<=90;end
      1:begin hazard_u<=133;hazard_v<=168;hazard_h<=68;end
      2:begin hazard_u<=309;hazard_v<=168;hazard_h<=105;end
      3:begin hazard_u<=309;hazard_v<=344;hazard_h<=80;end
     endcase
     cooldown<=FRAME_PERIOD-1;
    end
    RADDR:begin address<={index,word_index};state<=RWAIT;end
    RWAIT:state<=RCAP;
    RCAP:begin record[word_index*16+:16]<=rom_q;if(word_index==7)state<=DECODE;else begin word_index<=word_index+1'b1;state<=RADDR;end end
    DECODE:begin
     kind<=record[127:124];reference_id<=record[123:120];edge_mask<=record[115:113];colour<=record[111:96];fx<=record[127:124];vertex<=0;state<=VLOAD;
     if((record[127:124]==1 || record[127:124]==2) && record[123:120]==(scene[11:10]==0?4:scene[11:10]==1?0:scene[11:10]==2?2:6))colour<=record[127:124]==1?16'hd086:16'h9004;
     if(record[127:124]==3)begin
      if(scene[124+record[123:120]])begin colour<=16'hd068;fx<=9;end
      else if(scene[92+record[123:120]] && !scene[9])begin colour<=16'h05b1;fx<=8;end
     end
    end
    VLOAD:begin du<=wu-focus_u;dv<=wv-focus_v;height<=wh;op<=0;state<=OPLOAD;end
    OPLOAD:begin
     case(op)
      0:begin mul_a<=du;mul_b<=cosine;end
      1:begin mul_a<=dv;mul_b<=sine;end
      2:begin mul_a<=du;mul_b<=sine;end
      3:begin mul_a<=dv;mul_b<=cosine;end
      4:begin mul_a<=height;mul_b<=147;end
      5:begin mul_a<=rz;mul_b<=210;end
      6:begin mul_a<=height;mul_b<=210;end
      7:begin mul_a<=rz;mul_b<=147;end
      8:begin mul_a<=rx;mul_b<=focal;end
      9:begin mul_a<=cam_y;mul_b<=focal;end
     endcase
     state<=OPWAIT;
    end
    OPWAIT:state<=OPCAP;
    OPCAP:begin
     case(op)
      0,2,4,6:temporary<=product;
      1:rx<=($signed(temporary)-product)>>>8;
      3:rz<=($signed(temporary)+product)>>>8;
      5:cam_y<=($signed(temporary)+product)>>>8;
      7:cam_z<=13'sd900+(($signed(product)-$signed(temporary))>>>8);
      8,9:begin numerator<=product;denominator<=cam_z;div_op<=op==8?0:1;state<=DIVSTART;end
     endcase
     if(op<8)begin op<=op+1'b1;state<=OPLOAD;end
    end
    DIVSTART:begin div_start<=1;state<=DIVWAIT;end
    DIVWAIT:if(div_done)begin
     if(div_zero)begin sx[vertex]<=-1024;sy[vertex]<=-1024;iz[vertex]<=0;state<=NEXT;end
     else if(div_op==0)begin sx[vertex]<=quotient+160;op<=9;state<=OPLOAD;end
     else if(div_op==1)begin sy[vertex]<=80-quotient;numerator<=16777216;denominator<=cam_z;div_op<=2;state<=DIVSTART;end
     else begin iz[vertex]<=quotient[31:16]!=0?16'hffff:quotient[15:0];state<=NEXT;end
    end
    NEXT:if(vertex!=2)begin vertex<=vertex+1'b1;state<=VLOAD;end
     else begin
      held<={27'd0,mode,scene[9],zoom,yaw,scene[11:10],iz[2],sy[2],sx[2],iz[1],sy[1],sx[1],iz[0],sy[0],sx[0],colour,fx,edge_mask,index==117,{1'b0,index},frame_id,8'd1,8'd14};state<=EMIT;
     end
    EMIT:if(triangle_ready)begin if(index==117)state<=IDLE;else begin index<=index+1'b1;word_index<=0;state<=RADDR;end end
    default:state<=IDLE;
   endcase
  end
endmodule
