// Full-rate, shared quadrature DFT. All twelve bins see every PCM sample.
// 2048 samples / 48kHz = 42.667ms. 64-segment Hamming window; 40-bit sums.
// Phase and sums use block RAM. Quarter-wave sine ROM is 12-bit/1024 phase.
// Result is monotonic 12-bit log2(power): six exponent + six fraction bits.
module audio_dft12(
 input clk,rst,input signed [23:0] I_audio,input I_audio_valid,
 output busy,output reg O_band_valid,output reg [4:0] O_band,output reg [15:0] O_mag);
 (* ram_style="bram" *) reg [39:0] sums[0:23]; /* fehdl force_ram=1, ram_style="bram" */
 (* ram_style="bram" *) reg [11:0] sine_mem[0:256];
 initial begin
  sine_mem[0]=12'd0;
  sine_mem[1]=12'd13;
  sine_mem[2]=12'd25;
  sine_mem[3]=12'd38;
  sine_mem[4]=12'd50;
  sine_mem[5]=12'd63;
  sine_mem[6]=12'd75;
  sine_mem[7]=12'd88;
  sine_mem[8]=12'd100;
  sine_mem[9]=12'd113;
  sine_mem[10]=12'd126;
  sine_mem[11]=12'd138;
  sine_mem[12]=12'd151;
  sine_mem[13]=12'd163;
  sine_mem[14]=12'd176;
  sine_mem[15]=12'd188;
  sine_mem[16]=12'd201;
  sine_mem[17]=12'd213;
  sine_mem[18]=12'd226;
  sine_mem[19]=12'd238;
  sine_mem[20]=12'd251;
  sine_mem[21]=12'd263;
  sine_mem[22]=12'd275;
  sine_mem[23]=12'd288;
  sine_mem[24]=12'd300;
  sine_mem[25]=12'd313;
  sine_mem[26]=12'd325;
  sine_mem[27]=12'd338;
  sine_mem[28]=12'd350;
  sine_mem[29]=12'd362;
  sine_mem[30]=12'd375;
  sine_mem[31]=12'd387;
  sine_mem[32]=12'd399;
  sine_mem[33]=12'd412;
  sine_mem[34]=12'd424;
  sine_mem[35]=12'd436;
  sine_mem[36]=12'd449;
  sine_mem[37]=12'd461;
  sine_mem[38]=12'd473;
  sine_mem[39]=12'd485;
  sine_mem[40]=12'd497;
  sine_mem[41]=12'd510;
  sine_mem[42]=12'd522;
  sine_mem[43]=12'd534;
  sine_mem[44]=12'd546;
  sine_mem[45]=12'd558;
  sine_mem[46]=12'd570;
  sine_mem[47]=12'd582;
  sine_mem[48]=12'd594;
  sine_mem[49]=12'd606;
  sine_mem[50]=12'd618;
  sine_mem[51]=12'd630;
  sine_mem[52]=12'd642;
  sine_mem[53]=12'd654;
  sine_mem[54]=12'd666;
  sine_mem[55]=12'd678;
  sine_mem[56]=12'd690;
  sine_mem[57]=12'd701;
  sine_mem[58]=12'd713;
  sine_mem[59]=12'd725;
  sine_mem[60]=12'd737;
  sine_mem[61]=12'd748;
  sine_mem[62]=12'd760;
  sine_mem[63]=12'd772;
  sine_mem[64]=12'd783;
  sine_mem[65]=12'd795;
  sine_mem[66]=12'd807;
  sine_mem[67]=12'd818;
  sine_mem[68]=12'd830;
  sine_mem[69]=12'd841;
  sine_mem[70]=12'd852;
  sine_mem[71]=12'd864;
  sine_mem[72]=12'd875;
  sine_mem[73]=12'd887;
  sine_mem[74]=12'd898;
  sine_mem[75]=12'd909;
  sine_mem[76]=12'd920;
  sine_mem[77]=12'd932;
  sine_mem[78]=12'd943;
  sine_mem[79]=12'd954;
  sine_mem[80]=12'd965;
  sine_mem[81]=12'd976;
  sine_mem[82]=12'd987;
  sine_mem[83]=12'd998;
  sine_mem[84]=12'd1009;
  sine_mem[85]=12'd1020;
  sine_mem[86]=12'd1031;
  sine_mem[87]=12'd1042;
  sine_mem[88]=12'd1052;
  sine_mem[89]=12'd1063;
  sine_mem[90]=12'd1074;
  sine_mem[91]=12'd1085;
  sine_mem[92]=12'd1095;
  sine_mem[93]=12'd1106;
  sine_mem[94]=12'd1116;
  sine_mem[95]=12'd1127;
  sine_mem[96]=12'd1137;
  sine_mem[97]=12'd1148;
  sine_mem[98]=12'd1158;
  sine_mem[99]=12'd1168;
  sine_mem[100]=12'd1179;
  sine_mem[101]=12'd1189;
  sine_mem[102]=12'd1199;
  sine_mem[103]=12'd1209;
  sine_mem[104]=12'd1219;
  sine_mem[105]=12'd1229;
  sine_mem[106]=12'd1239;
  sine_mem[107]=12'd1249;
  sine_mem[108]=12'd1259;
  sine_mem[109]=12'd1269;
  sine_mem[110]=12'd1279;
  sine_mem[111]=12'd1289;
  sine_mem[112]=12'd1299;
  sine_mem[113]=12'd1308;
  sine_mem[114]=12'd1318;
  sine_mem[115]=12'd1328;
  sine_mem[116]=12'd1337;
  sine_mem[117]=12'd1347;
  sine_mem[118]=12'd1356;
  sine_mem[119]=12'd1365;
  sine_mem[120]=12'd1375;
  sine_mem[121]=12'd1384;
  sine_mem[122]=12'd1393;
  sine_mem[123]=12'd1402;
  sine_mem[124]=12'd1411;
  sine_mem[125]=12'd1421;
  sine_mem[126]=12'd1430;
  sine_mem[127]=12'd1439;
  sine_mem[128]=12'd1447;
  sine_mem[129]=12'd1456;
  sine_mem[130]=12'd1465;
  sine_mem[131]=12'd1474;
  sine_mem[132]=12'd1483;
  sine_mem[133]=12'd1491;
  sine_mem[134]=12'd1500;
  sine_mem[135]=12'd1508;
  sine_mem[136]=12'd1517;
  sine_mem[137]=12'd1525;
  sine_mem[138]=12'd1533;
  sine_mem[139]=12'd1542;
  sine_mem[140]=12'd1550;
  sine_mem[141]=12'd1558;
  sine_mem[142]=12'd1566;
  sine_mem[143]=12'd1574;
  sine_mem[144]=12'd1582;
  sine_mem[145]=12'd1590;
  sine_mem[146]=12'd1598;
  sine_mem[147]=12'd1606;
  sine_mem[148]=12'd1614;
  sine_mem[149]=12'd1621;
  sine_mem[150]=12'd1629;
  sine_mem[151]=12'd1637;
  sine_mem[152]=12'd1644;
  sine_mem[153]=12'd1652;
  sine_mem[154]=12'd1659;
  sine_mem[155]=12'd1666;
  sine_mem[156]=12'd1674;
  sine_mem[157]=12'd1681;
  sine_mem[158]=12'd1688;
  sine_mem[159]=12'd1695;
  sine_mem[160]=12'd1702;
  sine_mem[161]=12'd1709;
  sine_mem[162]=12'd1716;
  sine_mem[163]=12'd1723;
  sine_mem[164]=12'd1729;
  sine_mem[165]=12'd1736;
  sine_mem[166]=12'd1743;
  sine_mem[167]=12'd1749;
  sine_mem[168]=12'd1756;
  sine_mem[169]=12'd1762;
  sine_mem[170]=12'd1769;
  sine_mem[171]=12'd1775;
  sine_mem[172]=12'd1781;
  sine_mem[173]=12'd1787;
  sine_mem[174]=12'd1793;
  sine_mem[175]=12'd1799;
  sine_mem[176]=12'd1805;
  sine_mem[177]=12'd1811;
  sine_mem[178]=12'd1817;
  sine_mem[179]=12'd1823;
  sine_mem[180]=12'd1828;
  sine_mem[181]=12'd1834;
  sine_mem[182]=12'd1840;
  sine_mem[183]=12'd1845;
  sine_mem[184]=12'd1850;
  sine_mem[185]=12'd1856;
  sine_mem[186]=12'd1861;
  sine_mem[187]=12'd1866;
  sine_mem[188]=12'd1871;
  sine_mem[189]=12'd1876;
  sine_mem[190]=12'd1881;
  sine_mem[191]=12'd1886;
  sine_mem[192]=12'd1891;
  sine_mem[193]=12'd1896;
  sine_mem[194]=12'd1901;
  sine_mem[195]=12'd1905;
  sine_mem[196]=12'd1910;
  sine_mem[197]=12'd1914;
  sine_mem[198]=12'd1919;
  sine_mem[199]=12'd1923;
  sine_mem[200]=12'd1927;
  sine_mem[201]=12'd1932;
  sine_mem[202]=12'd1936;
  sine_mem[203]=12'd1940;
  sine_mem[204]=12'd1944;
  sine_mem[205]=12'd1948;
  sine_mem[206]=12'd1951;
  sine_mem[207]=12'd1955;
  sine_mem[208]=12'd1959;
  sine_mem[209]=12'd1962;
  sine_mem[210]=12'd1966;
  sine_mem[211]=12'd1969;
  sine_mem[212]=12'd1973;
  sine_mem[213]=12'd1976;
  sine_mem[214]=12'd1979;
  sine_mem[215]=12'd1983;
  sine_mem[216]=12'd1986;
  sine_mem[217]=12'd1989;
  sine_mem[218]=12'd1992;
  sine_mem[219]=12'd1994;
  sine_mem[220]=12'd1997;
  sine_mem[221]=12'd2000;
  sine_mem[222]=12'd2003;
  sine_mem[223]=12'd2005;
  sine_mem[224]=12'd2008;
  sine_mem[225]=12'd2010;
  sine_mem[226]=12'd2012;
  sine_mem[227]=12'd2015;
  sine_mem[228]=12'd2017;
  sine_mem[229]=12'd2019;
  sine_mem[230]=12'd2021;
  sine_mem[231]=12'd2023;
  sine_mem[232]=12'd2025;
  sine_mem[233]=12'd2027;
  sine_mem[234]=12'd2028;
  sine_mem[235]=12'd2030;
  sine_mem[236]=12'd2032;
  sine_mem[237]=12'd2033;
  sine_mem[238]=12'd2035;
  sine_mem[239]=12'd2036;
  sine_mem[240]=12'd2037;
  sine_mem[241]=12'd2038;
  sine_mem[242]=12'd2039;
  sine_mem[243]=12'd2040;
  sine_mem[244]=12'd2041;
  sine_mem[245]=12'd2042;
  sine_mem[246]=12'd2043;
  sine_mem[247]=12'd2044;
  sine_mem[248]=12'd2045;
  sine_mem[249]=12'd2045;
  sine_mem[250]=12'd2046;
  sine_mem[251]=12'd2046;
  sine_mem[252]=12'd2046;
  sine_mem[253]=12'd2047;
  sine_mem[254]=12'd2047;
  sine_mem[255]=12'd2047;
  sine_mem[256]=12'd2047;
 end
 function [31:0] increment;input [3:0] n;
 begin case(n)
    4'd0: increment=32'd23410256; // nominal261.63Hz
    4'd1: increment=32'd26276252; // nominal293.66Hz
    4'd2: increment=32'd29494793; // nominal329.63Hz
    4'd3: increment=32'd31248571; // nominal349.23Hz
    4'd4: increment=32'd35075566; // nominal392Hz
    4'd5: increment=32'd39370534; // nominal440Hz
    4'd6: increment=32'd44191634; // nominal493.88Hz
    4'd7: increment=32'd46819617; // nominal523.25Hz
    4'd8: increment=32'd71582788; // nominal800Hz
    4'd9: increment=32'd89478485; // nominal1000Hz
    4'd10: increment=32'd107374182; // nominal1200Hz
    4'd11: increment=32'd143165577; // nominal1600Hz
    default:increment=0;
 endcase end endfunction
 function [7:0] window_coefficient;input [5:0] n;
 begin case(n)
    6'd0: window_coefficient=8'd20;
    6'd1: window_coefficient=8'd21;
    6'd2: window_coefficient=8'd23;
    6'd3: window_coefficient=8'd26;
    6'd4: window_coefficient=8'd30;
    6'd5: window_coefficient=8'd35;
    6'd6: window_coefficient=8'd41;
    6'd7: window_coefficient=8'd48;
    6'd8: window_coefficient=8'd56;
    6'd9: window_coefficient=8'd65;
    6'd10: window_coefficient=8'd74;
    6'd11: window_coefficient=8'd84;
    6'd12: window_coefficient=8'd95;
    6'd13: window_coefficient=8'd106;
    6'd14: window_coefficient=8'd117;
    6'd15: window_coefficient=8'd129;
    6'd16: window_coefficient=8'd141;
    6'd17: window_coefficient=8'd152;
    6'd18: window_coefficient=8'd164;
    6'd19: window_coefficient=8'd175;
    6'd20: window_coefficient=8'd186;
    6'd21: window_coefficient=8'd196;
    6'd22: window_coefficient=8'd206;
    6'd23: window_coefficient=8'd215;
    6'd24: window_coefficient=8'd224;
    6'd25: window_coefficient=8'd231;
    6'd26: window_coefficient=8'd238;
    6'd27: window_coefficient=8'd243;
    6'd28: window_coefficient=8'd248;
    6'd29: window_coefficient=8'd251;
    6'd30: window_coefficient=8'd254;
    6'd31: window_coefficient=8'd255;
    6'd32: window_coefficient=8'd255;
    6'd33: window_coefficient=8'd254;
    6'd34: window_coefficient=8'd251;
    6'd35: window_coefficient=8'd248;
    6'd36: window_coefficient=8'd243;
    6'd37: window_coefficient=8'd238;
    6'd38: window_coefficient=8'd231;
    6'd39: window_coefficient=8'd224;
    6'd40: window_coefficient=8'd215;
    6'd41: window_coefficient=8'd206;
    6'd42: window_coefficient=8'd196;
    6'd43: window_coefficient=8'd186;
    6'd44: window_coefficient=8'd175;
    6'd45: window_coefficient=8'd164;
    6'd46: window_coefficient=8'd152;
    6'd47: window_coefficient=8'd141;
    6'd48: window_coefficient=8'd129;
    6'd49: window_coefficient=8'd117;
    6'd50: window_coefficient=8'd106;
    6'd51: window_coefficient=8'd95;
    6'd52: window_coefficient=8'd84;
    6'd53: window_coefficient=8'd74;
    6'd54: window_coefficient=8'd65;
    6'd55: window_coefficient=8'd56;
    6'd56: window_coefficient=8'd48;
    6'd57: window_coefficient=8'd41;
    6'd58: window_coefficient=8'd35;
    6'd59: window_coefficient=8'd30;
    6'd60: window_coefficient=8'd26;
    6'd61: window_coefficient=8'd23;
    6'd62: window_coefficient=8'd21;
    6'd63: window_coefficient=8'd20;
    default:window_coefficient=0;
 endcase end endfunction
 function [8:0] quarter_address;input [31:0] p;
 begin quarter_address=p[30]?(9'd256-{1'b0,p[29:22]}):{1'b0,p[29:22]};end endfunction
 function [11:0] logarithm;input [36:0] p;
 reg e5,e4,e3,e2,e1,e0;reg [37:0] v38;reg [21:0] v22;reg [13:0] v14;reg [9:0] v10;reg [7:0] v8;reg [6:0] v7;
 begin
  e5=|p[36:32];v38=e5?{27'd0,p[36:26]}:{p[31:0],6'd0};
  e4=|v38[37:22];v22=e4?v38[37:16]:v38[21:0];
  e3=|v22[21:14];v14=e3?v22[21:8]:v22[13:0];
  e2=|v14[13:10];v10=e2?v14[13:4]:v14[9:0];
  e1=|v10[9:8];v8=e1?v10[9:2]:v10[7:0];
  e0=v8[7];v7=e0?v8[7:1]:v8[6:0];
  logarithm={e5,e4,e3,e2,e1,e0,v7[5:0]};
 end endfunction
 reg [3:0] state,bin;reg [10:0] sample_index;
 wire [79:0] state_q;reg [8:0] sine_address;reg [11:0] sine_q;reg sine_negative;
 reg [31:0] phase;reg signed [39:0] sum_i,sum_q;
 reg signed [24:0] window_product;reg signed [15:0] windowed;
 reg signed [28:0] product;reg signed [35:0] square_i,square_q;reg [36:0] power;
 wire signed [12:0] coefficient=sine_negative?-$signed({1'b0,sine_q}):$signed({1'b0,sine_q});
 wire signed [39:0] extended_product={{11{product[28]}},product};
 wire signed [17:0] scaled_i=sum_i>>>20,scaled_q=sum_q>>>20;
 wire [31:0] cos_phase=phase+32'h40000000;
 // Induction: each completed PCM sample adds increment(bin) once;
 // reset/window boundaries start at zero. This replaces the stored phase
 // with the exact low32-bit product, retaining the original state3 capture.
 wire [31:0] phase_at_sample=sample_index*increment(bin);
 assign busy=state!=0;
 // A single40-bit RAM uses the original spare states for prefetch and
 // writes. The two sums are loaded before state3; the original state11
 // external commit/advance schedule and arithmetic widths stay unchanged.
 wire advance_bin=(state==11 && sample_index!=2047 && bin!=11) || (state==13 && bin!=11);
 wire read_first=(state==0 && I_audio_valid) || advance_bin;
 wire read_second=state==1 || state==2;
 wire [3:0] fetch_bin=state==0?4'd0:advance_bin?bin+1'b1:bin;
 wire signed [39:0] next_sum_q=sum_q+extended_product;
 reg [39:0] fetched_sum, fetched_i;reg first_pending;
 assign state_q={fetched_i,fetched_sum};
 always @(posedge clk)begin
  if(state==8)sums[{bin,1'b0}]<=sum_i;
  else if(state==10)sums[{bin,1'b1}]<=next_sum_q;
  else if(read_first || read_second)fetched_sum<=sums[{fetch_bin,read_second}];
 end
 always @(posedge clk)begin
  if(rst)first_pending<=0;else first_pending<=read_first;
  if(first_pending)fetched_i<=fetched_sum;
  sine_q<=sine_mem[sine_address];
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=0;bin<=0;sample_index<=0;O_band_valid<=0;O_band<=0;O_mag<=0;
   sine_address<=0;sine_negative<=0;phase<=0;sum_i<=0;sum_q<=0;
   window_product<=0;windowed<=0;product<=0;square_i<=0;square_q<=0;power<=0;
  end else begin
   O_band_valid<=0;
   case(state)
    0:if(I_audio_valid)begin
     window_product<=$signed(I_audio[23:8])*$signed({1'b0,window_coefficient(sample_index[10:5])});
     bin<=0;state<=1;
    end
    1:begin windowed<=window_product>>>8;state<=2;end
    2:state<=3;
    3:begin
     phase<=sample_index==0?0:phase_at_sample;
     sum_i<=sample_index==0?40'sd0:$signed(state_q[79:40]);
     sum_q<=sample_index==0?40'sd0:$signed(state_q[39:0]);state<=4;
    end
    4:begin sine_address<=quarter_address(phase);sine_negative<=phase[31];state<=5;end
    5:state<=6;
    6:begin product<=windowed*coefficient;state<=7;end
    7:begin sum_i<=sum_i+extended_product;sine_address<=quarter_address(cos_phase);sine_negative<=cos_phase[31];state<=8;end
    8:state<=9;
    9:begin product<=windowed*coefficient;state<=10;end
    10:begin sum_q<=sum_q+extended_product;state<=11;end
    11:begin
     if(sample_index==2047)begin square_i<=scaled_i*scaled_i;square_q<=scaled_q*scaled_q;state<=12;end
     else if(bin==11)begin sample_index<=sample_index+1'b1;state<=0;end
     else begin bin<=bin+1'b1;state<=2;end
    end
    12:begin power<={1'b0,square_i}+{1'b0,square_q};state<=13;end
    13:begin
     O_band_valid<=1;O_band<={1'b0,bin};O_mag<={4'd0,logarithm(power)};
     if(bin==11)begin sample_index<=0;state<=0;end else begin bin<=bin+1'b1;state<=2;end
    end
    default:state<=0;
   endcase
  end
 end
endmodule
