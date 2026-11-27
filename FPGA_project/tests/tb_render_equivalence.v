`timescale 1ns/1ps
module tb_render_equivalence;
reg clk=0;always #10 clk=~clk;reg rst=1,enabled=0,scene_valid=0;reg[187:0] scene=0;reg[1:0] zoom=0,barrier=0;
wire sv;wire[223:0] sp;
distributed_map_worker worker(.clk(clk),.rst(rst),.online(1'b1),.actual_state(3'd1),.switches(zoom),.barrier_mode(barrier),.stream_ready(1'b1),.stream_valid(sv),.stream_data(sp));
wire rq0,rq1,en0,en1,fv0,fv1;wire[31:0] wd0,wd1;reg done0=0,done1=0;integer n0=0,n1=0,ticks=0,fast=0,slow=0;reg[31:0] golden[0:115199],actual[0:115199];
b_map_frame_renderer_reference original(.clk(clk),.rst(rst),.enabled(enabled),.scene_valid(scene_valid),.scene(scene),.write_req(rq0),.write_ack(rq0),.write_full(1'b0),.write_done_toggle(done0),.write_en(en0),.write_data(wd0),.write_cancel(),.frame_valid(fv0),.frame_event(),.frame_consumed(1'b0));
b_map_frame_renderer optimized(.clk(clk),.rst(rst),.enabled(enabled),.scene_valid(scene_valid),.scene(scene),.write_req(rq1),.write_ack(rq1),.write_full(1'b0),.write_done_toggle(done1),.write_en(en1),.write_data(wd1),.write_cancel(),.frame_valid(fv1),.frame_event(),.frame_consumed(1'b0));
always @(posedge clk)begin
 ticks<=ticks+1;
 if(rst)begin n0<=0;n1<=0;done0<=0;done1<=0;end else begin
 if(en0)begin golden[n0]<=wd0;n0<=n0+1;if(n0==115199)begin done0<=~done0;slow<=ticks;end end
 if(en1)begin actual[n1]<=wd1;n1<=n1+1;if(n1==115199)begin done1<=~done1;fast<=ticks;end end
 end
end
integer testno,j,start;
initial begin
 for(testno=0;testno<4;testno=testno+1)begin
 rst=1;enabled=0;scene_valid=0;zoom=testno%3;barrier=testno==3?3:0;
 repeat(10)@(negedge clk);rst=0;wait(sv);@(negedge clk);scene=sp[187:0];scene_valid=1;enabled=1;start=ticks;@(negedge clk);scene_valid=0;
 wait(fv0&&fv1);@(negedge clk);
 if(n0!=115200||n1!=115200)$fatal(1,"render count");
 for(j=0;j<115200;j=j+1)if(golden[j]!==actual[j])$fatal(1,"different retained pixel test=%d word=%d ref=%h actual=%h",testno,j,golden[j],actual[j]);
 $display("PASS: scene=%d zoom=%d barrier=%d all 230400 RGB565 pixels identical; reference_cycles=%d optimized_cycles=%d",testno,zoom,barrier,slow-start,fast-start);
 end
 $finish;
end
initial begin #200000000;$fatal(1,"render equivalence timeout");end
endmodule
