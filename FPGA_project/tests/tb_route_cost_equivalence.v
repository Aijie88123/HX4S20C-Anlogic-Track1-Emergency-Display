`timescale 1ns/1ps
module tb_route_cost_equivalence;
 reg clk=0,rst=1,start=0;always #20 clk=~clk;
 reg [3:0] origin=0;reg [15:0] closed=0;
 wire busy0,busy1,done0,done1,np0,np1;wire [15:0] route0,route1,dirs0,dirs1;
 wire [3:0] dst0,dst1,len0,len1;wire [51:0] nodes0,nodes1;
 campus_route_solver reference_solver(.clk(clk),.rst(rst),.start(start),.origin(origin),.closed(closed),
  .busy(busy0),.done(done0),.no_path(np0),.route(route0),.directions(dirs0),.destination(dst0),.path_length(len0),.reverse_nodes(nodes0));
 a_campus_route_solver compact_solver(.clk(clk),.rst(rst),.start(start),.origin(origin),.closed(closed),
  .busy(busy1),.done(done1),.no_path(np1),.route(route1),.directions(dirs1),.destination(dst1),.path_length(len1),.reverse_nodes(nodes1));
 integer i,j,cases=0;reg [15:0] random_mask=16'h493a;
 always @(negedge clk)if(!rst)begin
  if({busy0,done0}!={busy1,done1})$fatal(1,"FAIL: solver cycle timing changed");
  if(done0 && {np0,route0,dirs0,dst0,len0,nodes0}!=={np1,route1,dirs1,dst1,len1,nodes1})
   $fatal(1,"FAIL: encoded cost route mismatch origin=%d closed=%h",origin,closed);
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;
  for(j=0;j<13;j=j+1)for(i=0;i<1042;i=i+1)begin
   @(negedge clk);origin=j;
   if(i==0)closed=0;else if(i==1)closed=16'hffff;else if(i<18)closed=16'd1<<(i-2);
   else begin random_mask={random_mask[14:0],random_mask[15]^random_mask[13]^random_mask[12]^random_mask[10]};closed=random_mask;end
   start=1;@(negedge clk);start=0;wait(done0);@(negedge clk);cases=cases+1;
  end
  $display("PASS: %0d weighted16 vs encoded5 Dijkstra routes, all 13 origins, every single road closure, open/sealed graphs, 13312 pseudo-random closure masks; cycle-exact route/directions/exit/node-chain/no-path equivalence",cases);$finish;
 end
 initial begin #500000000;$fatal(1,"FAIL: route equivalence timeout");end
endmodule
