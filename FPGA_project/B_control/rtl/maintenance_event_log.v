// Bounded event ring plus an immutable export snapshot. Log writes pause only
// for the short copy, never for the UART transmission. Control remains live.
module maintenance_event_log #(parameter integer EVENTS=6)(
 input clk,rst,clear,input [EVENTS-1:0] event_valid,input [EVENTS*64-1:0] event_data,
 output reg [6:0] count,output reg [15:0] lost,
 input snapshot_start,input [6:0] requested,output snapshot_busy,
 output reg snapshot_ready,output reg [6:0] snapshot_count,
 input [5:0] snapshot_address,output reg [63:0] snapshot_data);
 (* ram_style="bram" *) reg [63:0] entries[0:63]; /* fehdl force_ram=1, ram_style="bram" */
 (* ram_style="bram" *) reg [63:0] exported[0:63]; /* fehdl force_ram=1, ram_style="bram" */
 reg [63:0] pending_data[0:EVENTS-1];reg [EVENTS-1:0] pending;reg [5:0] write_pointer,copy_address,copy_index;
 reg [6:0] copy_left;reg [2:0] copy_state;reg [63:0] entry_q;
 integer i,j;reg [2:0] selected;reg found;reg [3:0] lost_now;reg [16:0] lost_sum;
 wire drain=copy_state==0&&!snapshot_start&&!clear&&found;
 assign snapshot_busy=copy_state!=0;
 always @*begin
  found=0;selected=0;
  for(i=EVENTS-1;i>=0;i=i-1)if(pending[i])begin found=1;selected=i;end
  lost_now=(drain&&count==64)?1:0;
  for(i=0;i<EVENTS;i=i+1)if(event_valid[i]&&pending[i]&&!(drain&&selected==i))lost_now=lost_now+1'b1;
  lost_sum={1'b0,lost}+lost_now;
 end
 always @(posedge clk)begin
  if(drain)entries[write_pointer]<=pending_data[selected];
  entry_q<=entries[copy_address];
  if(copy_state==3)exported[copy_index]<=entry_q;
  snapshot_data<=exported[snapshot_address];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin count<=0;lost<=0;pending<=0;write_pointer<=0;copy_state<=0;copy_left<=0;copy_address<=0;copy_index<=0;snapshot_ready<=0;snapshot_count<=0;end
  else begin
   snapshot_ready<=0;lost<=lost_sum[16]?16'hffff:lost_sum[15:0];
   if(drain)begin pending[selected]<=0;write_pointer<=write_pointer+1'b1;if(count<64)count<=count+1'b1;end
   if(clear)begin count<=0;lost<=0;pending<=0;write_pointer<=0;end
   for(j=0;j<EVENTS;j=j+1)if(event_valid[j])begin pending[j]<=1;pending_data[j]<=event_data[j*64+:64];end
   case(copy_state)
    0:if(snapshot_start)begin
     snapshot_count<=requested<count?requested:count;copy_left<=requested<count?requested:count;
     copy_address<=write_pointer-(requested<count?requested:count);copy_index<=0;
     if(requested==0||count==0)snapshot_ready<=1;else copy_state<=1;
    end
    1:copy_state<=2;
    2:copy_state<=3;
    3:if(copy_left==1)begin copy_state<=0;snapshot_ready<=1;end
      else begin copy_left<=copy_left-1'b1;copy_address<=copy_address+1'b1;copy_index<=copy_index+1'b1;copy_state<=1;end
   endcase
  end
endmodule
