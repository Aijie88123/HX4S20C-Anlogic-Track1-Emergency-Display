`timescale 1ns/1ps
module tb_subtitle_display;
 reg net=0,video=0,rst=1,valid=0,vs=0,emergency=0;always #20 net=~net;always #6.667 video=~video;
 reg [223:0] packet=0;wire ack;wire [223:0] ackpacket;wire active,pixel,bar;reg ackready=0;reg [11:0] x=0,y=0;
 subtitle_display dut(.net_clk(net),.net_rst(rst),.packet_valid(valid),.packet(packet),.ack_valid(ack),.ack_packet(ackpacket),.ack_ready(ackready),
 .video_clk(video),.video_rst(rst),.video_vs(vs),.emergency(emergency),.x_pre(x),.y_pre(y),.custom_active(active),.custom_pixel(pixel),.custom_bar(bar));
 reg [15:0] words[0:2047];reg [15:0] digest0,digest1;integer out;
 initial begin $readmemh("words.hex",words);out=$fopen("pixels.txt","w");end
 task clocks(input integer n);repeat(n)@(negedge net);endtask
 task send(input [7:0] op,id,input [15:0] index,crc,input [127:0] data);begin
 @(negedge net);packet={32'h53554231,data,crc,index,id,op,8'd1,8'd18};valid=1;clocks(1);valid=0;end endtask
 task response(input [7:0] status);begin wait(ack);if(ackpacket[23:16]!==status)$fatal(1,"response%0d wanted%0d",ackpacket[23:16],status);
 @(negedge net);ackready=1;clocks(1);ackready=0;clocks(1);end endtask
 task frame;begin @(negedge video);vs=1;repeat(4)@(negedge video);vs=0;repeat(4)@(negedge video);end endtask
 task scan(input integer tag,input integer y0,input integer y1);integer xx,yy;begin
 for(yy=y0;yy<y1;yy++)for(xx=0;xx<1280;xx++)begin @(negedge video);x=xx;y=yy;@(posedge video);#1;$fdisplay(out,"%0d %0d %0d %b %b %b %0d",tag,xx,yy,active,pixel,bar,dut.phase);end end endtask
 task upload(input integer bank,input [7:0] id,input [15:0] width);integer i,j;reg [127:0] data;begin
 send(0,id,width,0,0);response(0);
 for(i=0;i<128;i++)begin for(j=0;j<8;j++)data[j*16+:16]=words[bank*1024+i*8+j];send(1,id,i,0,data);response(0);end
 end endtask
 integer i;reg oldbank;reg [15:0] expected_crc[0:1];
 initial begin $readmemh("digests.hex",expected_crc);clocks(8);rst=0;scan(0,676,716);
 send(0,1,15,0,0);response(10);upload(0,2,512);
 send(2,2,128,expected_crc[0]^1,0);response(13);if(active)$fatal(1,"bad digest displayed");
 // Begin again because failed requests are idempotently acknowledged.
 upload(0,3,512);send(2,3,128,expected_crc[0],0);clocks(100);
 if(ack||active)$fatal(1,"commit acknowledged before real VS");frame;response(0);if(!active)$fatal(1,"commit not enabled");
 scan(1,676,716);frame;scan(2,676,716);oldbank=dut.active_bank;
 // Partial data cannot touch or switch the active bank.
 send(0,4,1024,0,0);response(0);send(1,4,1,0,0);response(11);scan(3,680,684);
 if(dut.active_bank!=oldbank)$fatal(1,"partial upload swapped bank");
 upload(1,5,1024);send(2,5,128,expected_crc[1],0);clocks(30);if(ack||dut.active_bank!=oldbank)$fatal(1,"early bank/ack");
 emergency=1;frame;response(0);scan(4,576,616);scan(5,615,720);
 // Retrying a completed commit does not reset scroll or flip banks.
 oldbank=dut.active_bank;send(2,5,128,expected_crc[1],0);response(0);if(dut.active_bank!=oldbank)$fatal(1,"duplicate commit");
 send(3,6,0,0,0);clocks(20);if(!active||ack)$fatal(1,"clear before VS");frame;response(0);scan(6,680,684);if(active)$fatal(1,"clear failed");
 upload(0,7,16);rst=1;clocks(5);rst=0;frame;if(active)$fatal(1,"reset exposed RAM");
 $display("PASS: native dual-clock subtitle RAM,complete128blocks,digest rejection,inactive bank,realVS commit/clear ACK,duplicate,normal/emergency/HUD pixel scan,reset.");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout state%0d",dut.state);end
endmodule
