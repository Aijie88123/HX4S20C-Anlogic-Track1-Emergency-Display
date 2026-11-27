`timescale 1ns/1ps
module tb_page_audio25;
reg src=0,audio=0,rst=1;always #20 src=~src;always #40.690104 audio=~audio;
reg toggle=0,valid=0,emer=0;reg [2:0] page=0;reg [7:0] count=0;wire tick=count==255;
always @(posedge audio)if(rst)count<=0;else count<=count+1'b1;
wire [2:0] target;wire pending,target_emer;
image_audio_commit_cdc dut(.src_clk(src),.dst_clk(audio),.rst(rst),.src_commit_toggle(toggle),.src_page(page),.src_valid(valid),.src_emergency(emer),.dst_sample_tick(tick),.dst_page(target),.dst_pending(pending),.dst_emergency(target_emer));
integer seen=0;reg [2:0] expected[0:3];reg [3:0] expected_emer=4'b1100;
always @(posedge audio)if(!rst&&tick&&pending)begin
if(seen>3||target!==expected[seen]||target_emer!==expected_emer[seen])$fatal(1,"page/audio commit mismatch sample=%0d got=%0d/%0d",seen,target,target_emer);
seen=seen+1;
end
task send_page;input [2:0] p;input e;begin @(negedge src);page=p;emer=e;toggle=~toggle;valid=1;end endtask
initial begin
expected[0]=2;expected[1]=5;expected[2]=0;expected[3]=6;
repeat(5)@(negedge src);rst=0;
send_page(2,0);wait(pending);send_page(3,0);send_page(4,0);send_page(5,0);wait(seen==2);
repeat(10)@(negedge src);rst=1;valid=0;toggle=0;repeat(6)@(negedge src);
if(pending||target!=0||target_emer)$fatal(1,"stale audio page after reset");
rst=0;send_page(0,1);wait(pending);send_page(6,1);wait(seen==4);repeat(10)@(negedge src);
$display("PASS: 25MHz page-control source to independent audio clock; commits accepted on stereo sample ticks, newest queued page retained through backpressure, emergency tag atomic and reset clears stale work");$finish;
end
initial begin #200000;$fatal(1,"audio page CDC timeout");end
endmodule
