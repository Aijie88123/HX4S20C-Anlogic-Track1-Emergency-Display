// Shared signed restoring divider. Small serial datapath, no combinational /.
module mesh3d_divider #(parameter W=40)(
 input clk,rst,start,input signed [W-1:0] numerator,denominator,
 output reg busy,done,zero,output reg signed [W-1:0] quotient);
 reg [W-1:0] dividend,divisor,q;
 reg [W:0] remainder;
 reg negative;reg [$clog2(W)-1:0] count;
 wire [W:0] trial={remainder[W-1:0],dividend[W-1]};
 wire ge=trial>={1'b0,divisor};
 wire [W-1:0] qnext={q[W-2:0],ge};
 always @(posedge clk or posedge rst)
  if(rst)begin busy<=0;done<=0;zero<=0;quotient<=0;dividend<=0;divisor<=0;q<=0;remainder<=0;negative<=0;count<=0;end
  else begin
   done<=0;
   if(start && !busy)begin
    zero<=denominator==0;negative<=numerator[W-1]^denominator[W-1];
    dividend<=numerator[W-1]?-numerator:numerator;divisor<=denominator[W-1]?-denominator:denominator;
    q<=0;remainder<=0;count<=0;
    if(denominator==0)begin quotient<=0;done<=1;end else busy<=1;
   end else if(busy)begin
    remainder<=ge?trial-{1'b0,divisor}:trial;dividend<=dividend<<1;q<=qnext;
    if(count==W-1)begin busy<=0;done<=1;quotient<=negative?-$signed(qnext):$signed(qnext);end
    else count<=count+1'b1;
   end
  end
endmodule
