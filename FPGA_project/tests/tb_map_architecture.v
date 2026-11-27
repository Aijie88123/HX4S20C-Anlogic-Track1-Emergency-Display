`timescale 1ns/1ps
module tb_map_architecture;
 reg clk=0,rst=1,active=0,tick=0;always #10 clk=~clk;
 reg [187:0] scene=0;reg [1:0] event_type=0;reg blink=0;reg [11:0] x=0,y=0;
 wire [23:0] old_rgb,new_rgb;wire [7:0] old_alpha,new_alpha;
 emergency_map_top_reference #(.REMOTE_MAP(1),.RASTER_STEP(2),.RASTER_VGA(1)) original(
  .clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(tick),.cx(x),.cy(y),.map_rgb(old_rgb),.map_alpha(old_alpha));
 emergency_map_top #(.REMOTE_MAP(1),.RASTER_STEP(2),.RASTER_VGA(1)) detailed(
  .clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(tick),.cx(x),.cy(y),.map_rgb(new_rgb),.map_alpha(new_alpha));
 reg [3:0] golden[0:131071],atlas[0:8191];reg [8:0] indices[0:8191];reg [23:0] palette[0:7];
 initial begin
  $readmemh("../assets/map_architecture/materials.hex",golden);
  $readmemh("../assets/map_architecture/tile_index.hex",indices);
  $readmemh("../assets/map_architecture/tile_atlas.hex",atlas);
  $readmemh("architecture_palette.hex",palette);
 end
 reg model_region2=0;reg [3:0] model_word2=0;
 reg expected_region,override_scene,opaque_scene,danger,hatch;
 reg [3:0] expected_word,expected_class;reg [23:0] expected_colour;
 reg changed3=0,changed4=0,changed5=0;
 integer px,py,address,changed=0,total_changed=0,cycles=0,opaque_checks=0;
 always @(posedge clk)begin
  if(rst)begin
   model_region2=0;model_word2=0;changed3=0;changed4=0;changed5=0;
   #1;if({old_rgb,old_alpha}!=={new_rgb,new_alpha})$fatal(1,"reset output mismatch");
  end else begin
   px=detailed.sx1;py=detailed.sy1;
   expected_region=px>=128 && px<1152 && py>=144 && py<656;
   address=((py-144)/2)*512+(px-128)/2;
   expected_word=expected_region?golden[address]:0;
   override_scene=model_region2 && model_word2[2:0]!=0 &&
    !original.header2 && !original.box2 && !original.footer2 && !original.sign2 && !original.stem2;
   opaque_scene=model_region2 && model_word2[3];
   expected_colour=palette[model_word2[2:0]];
   danger=original.r2_danger||original.r2_spread;hatch=original.r2_hatch;
   changed5=changed4;changed4=changed3;changed3=override_scene||opaque_scene;
   #1;
   cycles=cycles+1;
   if({original.gu,original.gv,original.sx1,original.sy1,original.valid1}!==
      {detailed.gu,detailed.gv,detailed.sx1,detailed.sy1,detailed.valid1})
    $fatal(1,"camera/projection/valid pipeline changed");
   if(detailed.detail_region2!==expected_region ||
      (expected_region && detailed.detail_word2!==expected_word))
    $fatal(1,"material ROM/address latency mismatch at scene%0d,%0d expected=%h got=%h",px,py,expected_word,detailed.detail_word2);
   if(detailed.scene3!==(override_scene?expected_colour:original.scene3))
    $fatal(1,"surface material palette or R2/R3 timing mismatch");
   expected_class=original.class3;
   if(opaque_scene && expected_class>=6 && expected_class<=10)begin
    expected_class=danger?(hatch?11:12):0;opaque_checks=opaque_checks+1;
   end
   if(detailed.class3!==expected_class)$fatal(1,"person/hazard/route layering changed unexpectedly");
   if(new_alpha!==old_alpha)$fatal(1,"output valid/alpha latency changed");
   if(!changed5 && new_rgb!==old_rgb)$fatal(1,"unrelated pixel altered");
   if(new_alpha==255 && new_rgb!==old_rgb)changed=changed+1;
   model_region2=expected_region;model_word2=expected_word;
  end
 end
 integer f,e,b,status,row,col,i;reg [223:0] full_scene;reg [51:0] nodes;
 initial begin
  #1;for(i=0;i<8192;i=i+1)begin
   if(detailed.u_architecture_index.data[i]!==indices[i])$fatal(1,"tile index init mismatch%0d",i);
   if(detailed.u_architecture.data[i]!==atlas[i])$fatal(1,"tile atlas init mismatch%0d",i);
  end
  f=$fopen("map_partition_scenes.txt","r");
  for(i=0;i<16;i=i+1)begin
   status=$fscanf(f,"%d %d %h %h\n",e,b,full_scene,nodes);if(status!=4)$fatal(1,"missing A-computed scene");
   @(negedge clk);rst=1;active=0;tick=0;repeat(5)@(negedge clk);
   changed=0;scene=full_scene[187:0];event_type=e;blink=i[0];rst=0;active=1;tick=1;
   repeat(3)@(negedge clk);tick=0;repeat(5)@(negedge clk);
   for(row=0;row<480;row=row+1)for(col=0;col<640;col=col+1)begin x=col*2;y=row+(row>>1);@(negedge clk);end
   x=1600;y=900;repeat(8)@(negedge clk);
   if(changed<100)$fatal(1,"detail coverage missing for event%0d/barrier%0d",e,b);
   total_changed=total_changed+changed;
   $display("SCENE: event=%0d barrier=%0d changed_native_pixels=%0d",e,b,changed);
  end
  $fclose(f);
  $display("PASS: all16384 material ROM words match independent atlas; 16 A-computed event/barrier/zoom scenes and4915200 native pixels; canonical material addressing/palette, unchanged camera/markers/hazards/alpha, route occlusion, reset and exact existing pixel latency; changed=%0d checked_cycles=%0d route_occlusion_checks=%0d",total_changed,cycles,opaque_checks);$finish;
 end
 initial begin #200000000;$fatal(1,"architecture validation timeout");end
endmodule
