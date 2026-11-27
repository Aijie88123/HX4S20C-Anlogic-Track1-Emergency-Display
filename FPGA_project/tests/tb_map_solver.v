`timescale 1ns/1ps
module tb_map_solver;
 reg clk=0,rst=1,start=0;always #20 clk=~clk;
 reg [3:0] origin;reg [15:0] closed;wire busy,done,no_path;
 wire [15:0] route,dirs;wire [3:0] destination,length;wire [51:0] nodes;
 reg [63:0] vectors[0:1087];integer n,cycles,total=0;
 campus_route_solver dut(.clk(clk),.rst(rst),.start(start),.origin(origin),.closed(closed),
  .busy(busy),.done(done),.no_path(no_path),.route(route),.directions(dirs),
  .destination(destination),.path_length(length),.reverse_nodes(nodes));
 initial begin
  $readmemh("map_solver_vectors.hex",vectors);#100;rst=0;
  for(n=0;n<1088;n=n+1)begin
   @(negedge clk);origin=vectors[n][3:0];closed=vectors[n][19:4];start=1;
   @(negedge clk);start=0;cycles=0;
   while(!done && cycles<500)begin @(negedge clk);cycles=cycles+1;end
   if(!done || busy)$fatal(1,"Solver completion bound failed at %0d",n);
   if(no_path!==vectors[n][60] || route!==vectors[n][35:20] || (!no_path &&
      (dirs!==vectors[n][51:36] || destination!==vectors[n][55:52] || length!==vectors[n][59:56])))
    $fatal(1,"Dijkstra differs at %0d root=%0d blocked=%h got route=%h dirs=%h exit=%d len=%d no=%b expected=%h",
      n,origin,closed,route,dirs,destination,length,no_path,vectors[n]);
   if((route&closed)!=0)$fatal(1,"Computed route traverses a closed road");
   if(!no_path && (nodes[3:0]!==destination || (nodes>>(length*4)&15)!==origin))
    $fatal(1,"Computed node chain endpoints differ");
   total=total+cycles;
  end
  $display("PASS: 1088 independent Dijkstra cases, closures, unreachable exits, shortest cost, directions and node chains; maximum <500 clocks, total=%0d",total);
  $finish;
 end
endmodule
