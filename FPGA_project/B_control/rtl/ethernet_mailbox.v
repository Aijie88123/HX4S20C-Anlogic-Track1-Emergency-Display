// Bundled-data CDC: held bus, request toggle and returned acknowledgement.
module ethernet_mailbox #(parameter WIDTH=20)(
 input src_clk,src_rst,src_valid,input [WIDTH-1:0] src_data,output src_ready,
 input dst_clk,dst_rst,output reg dst_valid,output reg [WIDTH-1:0] dst_data);
 reg [WIDTH-1:0] held;
 reg request,acknowledge;
 reg [1:0] ack_sync;
 reg [2:0] req_sync;
 assign src_ready=(request==ack_sync[1]);
 always @(posedge src_clk or posedge src_rst)
  if(src_rst)begin held<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledge};
   if(src_valid && src_ready)begin held<=src_data;request<=~request;end
  end
 always @(posedge dst_clk or posedge dst_rst)
  if(dst_rst)begin req_sync<=0;acknowledge<=0;dst_valid<=0;dst_data<=0;end
  else begin
   req_sync<={req_sync[1:0],request};dst_valid<=0;
   if(req_sync[2]!=acknowledge)begin dst_data<=held;dst_valid<=1;acknowledge<=req_sync[2];end
  end
endmodule
