`timescale 1ns/1ps
module resource_mac_case #(parameter SIDE=0,RAW=1,VERSION=12,STREAM=1,EXT=1,ID=0)(output reg done=0);
 reg clk=0,rst=1,start=0;always #20 clk=~clk;
 reg [20:0] msg=0;reg [7:0] ext=0;reg [223:0] payload=0;
 wire busy0,busy1;wire [3:0] nib0,nib1;integer frame=0,accepted=0,ticks=0;
 wire pv0,pv1;wire [20:0] m0,m1;wire [7:0] e0,e1;wire [223:0] p0,p1;
 wire flip=frame%7==3 && old_tx.position==92;
 wire error=frame%11==5 && old_tx.position==73;
 wire valid=busy0 && !(frame%13==6 && old_tx.position>110);
 ethernet_frame_tx_reference #(.BOARD_B(SIDE),.STREAM(STREAM),.EXTENDED(EXT),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(RAW),.RAW_TF_VERSION(VERSION)) old_tx(
  .clk(clk),.rst(rst),.start(start),.message(msg),.extension(ext),.stream_data(payload),.busy(busy0),.nibble(nib0));
 ethernet_frame_tx #(.BOARD_B(SIDE),.STREAM(STREAM),.EXTENDED(EXT),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(RAW),.RAW_TF_VERSION(VERSION)) new_tx(
  .clk(clk),.rst(rst),.start(start),.message(msg),.extension(ext),.stream_data(payload),.busy(busy1),.nibble(nib1));
 ethernet_frame_rx_reference #(.BOARD_B(!SIDE),.STREAM(STREAM),.EXTENDED(EXT),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(RAW),.RAW_TF_VERSION(VERSION)) old_rx(
  .clk(clk),.rst(rst),.nibble(nib0^(flip?4'd1:4'd0)),.valid(valid),.error(error),.packet_valid(pv0),.message(m0),.extension(e0),.stream_data(p0));
 ethernet_frame_rx #(.BOARD_B(!SIDE),.STREAM(STREAM),.EXTENDED(EXT),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(RAW),.RAW_TF_VERSION(VERSION)) new_rx(
  .clk(clk),.rst(rst),.nibble(nib0^(flip?4'd1:4'd0)),.valid(valid),.error(error),.packet_valid(pv1),.message(m1),.extension(e1),.stream_data(p1));
 always @(posedge clk)begin
  ticks<=ticks+1;#1;
  if({busy0,nib0}!=={busy1,nib1})$fatal(1,"MAC cycle mismatch case=%0d frame=%0d tick=%0d",ID,frame,ticks);
  if(pv0!==pv1)$fatal(1,"MAC publication timing mismatch case=%0d",ID);
  if(pv0)begin
   if({m0,e0,p0}!=={m1,e1,p1})$fatal(1,"MAC full stream mismatch case=%0d frame=%0d",ID,frame);
   accepted<=accepted+1;
  end
 end
 integer j,k;
 initial begin
  repeat(8)@(negedge clk);rst=0;
  for(j=0;j<192;j=j+1)begin
   frame=j;msg=$random;ext=$random&8'h1f;
   for(k=0;k<7;k=k+1)payload[k*32+:32]=$random;
   if(j%2==0)begin payload[7:0]=0;payload[15:8]=0;end
   else begin payload[7:0]=j%16;payload[15:8]=j%4;end
   @(negedge clk);start=1;@(negedge clk);start=0;
   // The source changes immediately after capture, as real stream endpoints do.
   payload=~payload;msg=~msg;
   wait(!busy0);repeat(25)@(negedge clk);
   if(j%29==28)begin rst=1;repeat(3)@(negedge clk);rst=0;end
  end
  if(accepted<40)$fatal(1,"MAC equivalence vacuous case=%0d accepted=%0d",ID,accepted);
  $display("PASS: bit/cycle-identical MAC case=%0d direction=%0d raw=%0d version=%0d stream=%0d accepted=%0d; valid/invalid type, corrupt FCS, PHY error, truncation and reset",ID,SIDE,RAW,VERSION,STREAM,accepted);done=1;
 end
endmodule

module tb_resource_mac_equivalence;
 wire [9:0] done;
 resource_mac_case #(.ID(0),.SIDE(0),.RAW(0),.STREAM(0),.EXT(0)) c0(done[0]);
 resource_mac_case #(.ID(1),.SIDE(1),.RAW(0),.STREAM(0),.EXT(0)) c1(done[1]);
 resource_mac_case #(.ID(2),.SIDE(0),.RAW(0)) c2(done[2]);
 resource_mac_case #(.ID(3),.SIDE(1),.RAW(0)) c3(done[3]);
 resource_mac_case #(.ID(4),.SIDE(0),.VERSION(9)) c4(done[4]);
 resource_mac_case #(.ID(5),.SIDE(1),.VERSION(9)) c5(done[5]);
 resource_mac_case #(.ID(6),.SIDE(0),.VERSION(11)) c6(done[6]);
 resource_mac_case #(.ID(7),.SIDE(1),.VERSION(11)) c7(done[7]);
 resource_mac_case #(.ID(8),.SIDE(0)) c8(done[8]);
 resource_mac_case #(.ID(9),.SIDE(1)) c9(done[9]);
 initial begin wait(&done);$display("PASS: all ten MAC configurations match original wire bits and valid-cycle outputs");$finish;end
 initial begin #10000000;$fatal(1,"MAC test timeout");end
endmodule

module tb_resource_map_equivalence;
 reg clk=0,rst=1,active=0,tick=0;always #10 clk=~clk;
 reg [187:0] scene=0;reg [1:0] event_type=0;reg blink=0;reg [11:0] x=0,y=0;
 wire [23:0] c0,c1;wire [7:0] a0,a1;integer pixels=0;
 emergency_map_top_reference #(.REMOTE_MAP(1),.RASTER_STEP(2),.RASTER_VGA(1)) original(
  .clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(tick),.cx(x),.cy(y),.map_rgb(c0),.map_alpha(a0));
 emergency_map_top #(.REMOTE_MAP(1),.RASTER_STEP(2),.RASTER_VGA(1),.ARCHITECTURE_DETAILS(0)) optimized(
  .clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(tick),.cx(x),.cy(y),.map_rgb(c1),.map_alpha(a1));
 always @(posedge clk)begin #1;if({c0,a0}!=={c1,a1})$fatal(1,"map cycle/pixel mismatch x=%0d y=%0d old=%h/%h new=%h/%h",x,y,c0,a0,c1,a1);if(active)pixels<=pixels+1;end
 integer f,e,b,status,row,col,i;reg [223:0] full_scene;reg [51:0] nodes;
 initial begin
  #1;for(i=0;i<1024;i=i+1)if(optimized.scene_glyph(i)!==original.scene_glyph(i))$fatal(1,"glyph function differs at%0d",i);
  f=$fopen("map_partition_scenes.txt","r");
  for(i=0;i<16;i=i+1)begin
   status=$fscanf(f,"%d %d %h %h\n",e,b,full_scene,nodes);if(status!=4)$fatal(1,"scene input missing");
   @(negedge clk);rst=1;active=0;tick=0;repeat(5)@(negedge clk);
   scene=full_scene[187:0];event_type=e;blink=i[0];rst=0;active=1;tick=1;
   repeat(3)@(negedge clk);tick=0;repeat(5)@(negedge clk);
   for(row=0;row<480;row=row+1)for(col=0;col<640;col=col+1)begin x=col*2;y=row+(row>>1);@(negedge clk);end
   x=1600;y=900;repeat(8)@(negedge clk);
  end
  $fclose(f);$display("PASS:details disabled:1024 glyph words identical; all4915200 native map pixels and pipeline/reset cycles match original across16 event/barrier/zoom scenes; no added pixel latency");$finish;
 end
 initial begin #200000000;$fatal(1,"map equivalence timeout");end
endmodule
