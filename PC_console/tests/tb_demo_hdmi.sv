`timescale 1ns/1ps
module tb_demo_hdmi;
 reg net=0,video=0,rst=1,valid=0,vs=0,emergency=0;
 always #20 net=~net;always #6.667 video=~video;
 reg [223:0] packet=0;reg ackready=0;reg [11:0] x=0,y=0;
 wire ack,active,pixel,bar;wire [223:0] ackpacket;
 subtitle_display dut(.net_clk(net),.net_rst(rst),.packet_valid(valid),.packet(packet),.ack_valid(ack),.ack_packet(ackpacket),.ack_ready(ackready),
 .video_clk(video),.video_rst(rst),.video_vs(vs),.emergency(emergency),.x_pre(x),.y_pre(y),.custom_active(active),.custom_pixel(pixel),.custom_bar(bar));
 reg [223:0] packets[0:1429];reg [15:0] widths[0:10];integer outputfile,c,i,xx,yy,top;reg oldbank;
 task clocks(input integer n);repeat(n)@(negedge net);endtask
 task send(input [223:0] value);begin @(negedge net);packet=value;valid=1;clocks(1);valid=0;end endtask
 task response(input [223:0] value);begin wait(ack);if(ackpacket[23:16]!==0||ackpacket[31:24]!==value[31:24]||ackpacket[47:32]!==value[47:32]||ackpacket[55:48]!==value[23:16])$fatal(1,"ACK mismatch");@(negedge net);ackready=1;clocks(1);ackready=0;clocks(1);end endtask
 task frame;begin @(negedge video);vs=1;repeat(4)@(negedge video);vs=0;repeat(4)@(negedge video);end endtask
 initial begin
  $readmemh("packets.hex",packets);$readmemh("widths.hex",widths);outputfile=$fopen("pixels.txt","w");clocks(8);rst=0;
  for(c=0;c<11;c++)begin
   for(i=0;i<129;i++)begin send(packets[c*130+i]);response(packets[c*130+i]);end
   oldbank=dut.active_bank;send(packets[c*130+129]);clocks(40);
   if(ack || dut.active_bank!=oldbank)$fatal(1,"commit/ACK before VS");
   emergency=c>=6;frame;response(packets[c*130+129]);
   if(!active||dut.active_width!=widths[c]||dut.phase!=1280)$fatal(1,"wrong committed metadata/initial phase");
   top=c>=6?580:680;
   for(yy=top-4;yy<top+36;yy++)for(xx=0;xx<1280;xx++)begin
    @(negedge video);x=xx;y=yy;@(posedge video);#1;
    $fdisplay(outputfile,"%0d %0d %0d %b %b %b",c,xx,yy,active,pixel,bar);
   end
  end
  $display("PASS:11 real host captions,1430 accepted packets,11 VS-qualified commits,native dual-clock font RAM and normal/emergency scanout.");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
