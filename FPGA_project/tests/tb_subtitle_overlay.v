// Compare continuing media/OSD/audio outside intentional startup-UI changes.
// Full startup pixels and frame-boundary handoff are checked in tb_startup_seamless.
`timescale 1ns/1ps
module tb_subtitle_overlay;
reg clk=0;always #6.666667 clk=~clk;reg rst=1;wire hs,vs,de;wire[11:0]x,y;integer cycles=0,frames=0;reg oldvs=1;
wire [2:0] retained_fx=3'd3;
wire a_hs,a_vs,a_de,b_hs,b_vs,b_de;wire[11:0]a_x,a_y,b_x,b_y;wire[23:0]a_rgb,b_rgb;
video_scanout_720p timing(.clk(clk),.rst(rst),.read_req(),.read_req_ack(1'b0),.read_en(),.read_data(32'd0),.read_empty(1'b1),.hs(),.vs(),.de(),.rgb(),.raw_hs(hs),.raw_vs(vs),.raw_de(de),.raw_frame_start(),.raw_x(x),.raw_y(y));
always @(posedge clk)if(rst)begin cycles<=0;frames<=0;oldvs<=vs;end else begin cycles<=cycles+1;oldvs<=vs;if(!vs&&oldvs)frames<=frames+1;end

reg net=0;always #20 net=~net;reg pv=0;reg [223:0] packet=0;wire av;wire [223:0] ap;reg ar=1;
wire [11:0] sx,sy;wire active,pixel,bar,show;
subtitle_display bitmap(.net_clk(net),.net_rst(rst),.packet_valid(pv),.packet(packet),.ack_valid(av),.ack_packet(ap),.ack_ready(ar),.video_clk(clk),.video_rst(rst),.video_vs(vs),.emergency(frames>=2),.x_pre(sx),.y_pre(sy),.custom_active(active),.custom_pixel(pixel),.custom_bar(bar));
reg [15:0] words[0:2047];reg [15:0] crc[0:1];
task send(input [7:0] op,input [15:0] index,digest,input [127:0] data);begin
 @(negedge net);packet={32'h53554231,data,digest,index,8'd43,op,8'd1,8'd18};pv=1;@(negedge net);pv=0;
 wait(av);if(ap[23:16]!=0)$fatal(1,"upload failed");@(negedge net);repeat(2)@(negedge net);
end endtask
integer normal_pixels=0,map_pixels=0,glyphs=0,outside=0;integer top,rel,w;reg px;reg [23:0] exp_rgb;integer c;
integer i,j;reg [127:0] data;
initial begin $readmemh("words.hex",words);$readmemh("digests.hex",crc);repeat(10)@(negedge clk);rst=0;
 send(0,512,0,0);for(i=0;i<128;i=i+1)begin for(j=0;j<8;j=j+1)data[j*16+:16]=words[i*8+j];send(1,i,0,data);end
 send(2,128,crc[0],0);wait(frames==5);repeat(100)@(negedge clk);
 if(normal_pixels<50000||map_pixels<50000||glyphs<100)$fatal(1,"coverage %0d %0d %0d",normal_pixels,map_pixels,glyphs);
 $display("PASS: full video_scanout/actual overlay/native subtitle RAM RGB and HS VS DE XY alignment; normal=%0d emergency=%0d glyph=%0d outside=%0d",normal_pixels,map_pixels,glyphs,outside);$finish;end
smart_terminal_overlay_pipelined #(.ENABLE_SUBTITLE(1),.ENHANCED_AUDIO_VIS(1),.WAVE_W(384),.WAVE_H(160),.POINT_PX(2),.SAMPLE_STEP(3),.EXTERNAL_MAP_PIXELS(1),.EXTERNAL_SPECTRUM(1),.NUMBERED_SIX(1),.ENABLE_STARTUP_UI(0),.ENABLE_PERIOD_OSD(1),.SCREEN_W(1280),.SCREEN_H(720),.EVAC_PAGE1_HOLD_FRAMES(1),.EVAC_FADE_FRAMES(1),.ALARM_TO_EVAC_FRAMES(1)) baseline(.subtitle_active(1'b1),.subtitle_pixel(1'b0),.subtitle_bar(1'b0),.subtitle_x(),.subtitle_y(),.subtitle_show(),.clk(clk),.rst(rst),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb({x[7:0],y[7:0],x[7:0]^y[7:0]}),.emergency(frames>=2),.startup_loading(1'b0),.startup_progress(9'd350),.emergency_event(2'd1),.map_pixels_valid(frames>=3),.map_pixels_stale(1'b0),.map_live(1'b1),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(cycles[15]),.load_nearly_done(1'b1),.fx_sel(retained_fx),.fx_off(1'b1),.audio_mag(cycles[15:0]),.audio_sample_valid(cycles%1563==0),.audio_sample(cycles[23:0]),.external_band_valid(cycles%97==0),.external_spectrum_live(1'b1),.external_band_data({cycles[7:4],cycles[15:0]}),.page_index(frames>=3?3'd1:frames>=2?3'd0:3'd2),.brightness(3'd3),.contrast(3'd3),.interval_selection(2'd1),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),.feature_mask(4'h1),.src_w(16'd640),.src_h(16'd480),.o_hs(a_hs),.o_vs(a_vs),.o_de(a_de),.o_rgb(a_rgb),.o_x(a_x),.o_y(a_y));
smart_terminal_overlay_pipelined #(.ENABLE_SUBTITLE(1),.ENHANCED_AUDIO_VIS(1),.WAVE_W(384),.WAVE_H(160),.POINT_PX(2),.SAMPLE_STEP(3),.EXTERNAL_MAP_PIXELS(1),.EXTERNAL_SPECTRUM(1),.NUMBERED_SIX(1),.ENABLE_STARTUP_UI(0),.ENABLE_PERIOD_OSD(1),.SCREEN_W(1280),.SCREEN_H(720),.EVAC_PAGE1_HOLD_FRAMES(1),.EVAC_FADE_FRAMES(1),.ALARM_TO_EVAC_FRAMES(1)) optimized(.subtitle_active(active),.subtitle_pixel(pixel),.subtitle_bar(bar),.subtitle_x(sx),.subtitle_y(sy),.subtitle_show(show),.clk(clk),.rst(rst),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb({x[7:0],y[7:0],x[7:0]^y[7:0]}),.emergency(frames>=2),.startup_loading(1'b0),.startup_progress(9'd350),.emergency_event(2'd1),.map_pixels_valid(frames>=3),.map_pixels_stale(1'b0),.map_live(1'b1),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(cycles[15]),.load_nearly_done(1'b1),.fx_sel(retained_fx),.fx_off(1'b1),.audio_mag(cycles[15:0]),.audio_sample_valid(cycles%1563==0),.audio_sample(cycles[23:0]),.external_band_valid(cycles%97==0),.external_spectrum_live(1'b1),.external_band_data({cycles[7:4],cycles[15:0]}),.page_index(frames>=3?3'd1:frames>=2?3'd0:3'd2),.brightness(3'd3),.contrast(3'd3),.interval_selection(2'd1),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),.feature_mask(4'h1),.src_w(16'd640),.src_h(16'd480),.o_hs(b_hs),.o_vs(b_vs),.o_de(b_de),.o_rgb(b_rgb),.o_x(b_x),.o_y(b_y));


always @(posedge clk)begin #1;
 if(!rst&&cycles>30)begin
 if({a_hs,a_vs,a_de,a_x,a_y}!=={b_hs,b_vs,b_de,b_x,b_y})$fatal(1,"timing mismatch");
 if($isunknown({b_hs,b_vs,b_de,b_x,b_y,b_rgb}))$fatal(1,"unknown output");
 if(b_de&&active&&frames>=1&&optimized.subtitle_show&&baseline.subtitle_show)begin
 top=bitmap.emergency_frame?580:680;rel=b_x+bitmap.phase-1280;
 if(b_y>=top-4&&b_y<top+36)begin
 px=0;if(rel>=0&&rel<1024&&b_y>=top&&b_y<top+32)begin w=((b_y-top)/2)*64+rel/32;px=words[w][15-(rel/2)%16];end
 exp_rgb=24'hffffff;
 if(!px)for(c=0;c<3;c=c+1)exp_rgb[c*8+:8]=(a_rgb[c*8+:8]*75+((24'h12385a>>(c*8))&255)*180)/255;
 if(b_rgb!==exp_rgb)$fatal(1,"subtitle alignment frame%0d x%0d y%0d phase%0d got%h expected%h px%b",frames,b_x,b_y,bitmap.phase,b_rgb,exp_rgb,px);
 if(bitmap.emergency_frame)map_pixels=map_pixels+1;else normal_pixels=normal_pixels+1;if(px)glyphs=glyphs+1;
 end else begin if(b_rgb!==a_rgb)$fatal(1,"outside subtitle changed %0d %0d",b_x,b_y);outside=outside+1;end
 end end end
initial begin #130000000;$fatal(1,"timeout");end
endmodule
