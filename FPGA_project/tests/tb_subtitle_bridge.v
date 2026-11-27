`timescale 1ns/1ps
module tb_subtitle_bridge;
reg clk=0,rst=1,rx=1,online=1,idle=1,pv=0;always #20 clk=~clk;
wire tx,sv;wire [223:0] sd;reg [223:0] packet=0;wire lv;wire [7:0] ld;
uart_subtitle_bridge #(.BAUD(1000000),.RETRY_CYCLES(2000),.TIMEOUT_CYCLES(60000),.CHAR_TIMEOUT(20000)) dut(
.clk(clk),.rst(rst),.uart_rx(rx),.uart_tx(tx),.online(online),.legacy_rx_valid(lv),.legacy_rx_data(ld),.legacy_rx_error(),.legacy_idle(idle),.legacy_tx_valid(1'b0),.legacy_tx_data(8'd0),.legacy_tx_ready(),.stream_valid(sv),.stream_data(sd),.stream_ready(1'b1),.packet_valid(pv),.packet(packet));
function [15:0] crc_byte;input [15:0] c;input [7:0] v;reg [15:0] t;integer k;begin t=c^{v,8'd0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_byte=t;end endfunction
reg [7:0] replies[0:255];integer n=0,k;reg [7:0] got;
always @(negedge tx)if(!rst)begin #1500;for(k=0;k<8;k=k+1)begin got[k]=tx;#1000;end if(!tx)$fatal(1,"stop");replies[n]=got;n=n+1;end
integer sent=0;reg [223:0] last;integer ack_after=0;reg schedule=0;
always @(negedge clk)begin
 pv=0;
 if(schedule)begin packet={32'h53554231,136'd0,last[23:16],last[47:32],last[31:24],8'd0,8'd1,8'd19};pv=1;schedule=0;end
 if(sv)begin sent=sent+1;last=sd;if(ack_after!=0&&sent>=ack_after)schedule=1;end
end
integer ascii=0;always @(posedge clk)if(lv)begin if(ld!=8'h50)$fatal(1,"binary leaked to ASCII");ascii=ascii+1;end
task byte_send(input [7:0] v);integer j;begin rx=0;#1000;for(j=0;j<8;j=j+1)begin rx=v[j];#1000;end rx=1;#1400;end endtask
task frame(input [7:0] tag,input bit bad);reg [223:0] p;reg [15:0] c;integer j;begin
 p={32'h53554231,128'd0,16'd0,16'd512,tag,8'd0,8'd1,8'd18};c=16'hffff;byte_send(27);byte_send("S");byte_send(1);
 for(j=0;j<28;j=j+1)begin byte_send(p[j*8+:8]);c=crc_byte(c,p[j*8+:8]);end byte_send(c[7:0]);byte_send(c[15:8]^(bad?8'd1:0));end endtask
task response(input integer start,input [7:0] tag,status);reg [15:0] c;integer j;begin
 wait(n==start+10);#2000;c=16'hffff;for(j=0;j<8;j=j+1)c=crc_byte(c,replies[start+j]);
 if({replies[start+9],replies[start+8]}!==c||replies[start+3]!==tag||replies[start+7]!==status)$fatal(1,"reply tag%0d/%0d status%0d/%0d CRC",replies[start+3],tag,replies[start+7],status);
end endtask
integer start;
initial begin #300;rst=0;
 byte_send("P");if(ascii!=1)$fatal(1,"ASCII path");
 start=n;frame(1,1);response(start,1,2);if(sent)$fatal(1,"bad CRC forwarded");
 start=n;byte_send(27);byte_send("X");byte_send(10);response(start,0,6);
 start=n;byte_send(27);byte_send("S");response(start,0,6);
 online=0;start=n;frame(2,0);response(start,2,3);online=1;
 idle=0;start=n;frame(3,0);idle=1;response(start,3,4);
 start=n;sent=0;ack_after=2;frame(4,0);response(start,4,0);if(sent<2)$fatal(1,"no retry");
 start=n;sent=0;ack_after=0;frame(5,0);response(start,5,5);
 // While first request awaits network, a second binary frame cannot replace
 // its held payload or response identity. Then the original must still ACK.
 start=n;sent=0;ack_after=0;frame(6,0);wait(sent>=1);frame(7,0);
 if(dut.held[31:24]!=6)$fatal(1,"pending overwritten");ack_after=sent+1;response(start,6,0);
 start=n;sent=0;ack_after=0;frame(8,0);wait(sent>=1);online=0;response(start,8,3);online=1;
 if(ascii!=1)$fatal(1,"binary leaked");
 $display("PASS: physicalUART bridge CRC/prefix/character timeout/offline/busy/retry/network timeout/pending ownership/drop-link/legacy demux and independent responseCRC");$finish;end
initial begin #20000000;$fatal(1,"timeout n%0d",n);end
endmodule
