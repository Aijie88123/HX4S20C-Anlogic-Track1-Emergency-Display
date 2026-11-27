// Clause22 serial MDIO at 390.625kHz, full preamble, tri-state read turnaround.
module ethernet_mdio(input clk,rst,start,read_op,input [4:0] phy_addr,reg_addr,input [15:0] write_data,
 output reg mdc,inout mdio,output reg busy,done,output reg [15:0] read_data,output reg response);
 reg [1:0] mdio_sync;
 always @(posedge clk or posedge rst)if(rst)mdio_sync<=2'b11;else mdio_sync<={mdio_sync[0],mdio};
 reg [4:0] divider;reg [5:0] bit_index;reg [63:0] shift;reg reading;
 wire drive=busy && !(reading && bit_index>=46);
 assign mdio=(drive && !shift[63])?1'b0:1'bz;
 always @(posedge clk or posedge rst)
  if(rst)begin mdc<=0;busy<=0;done<=0;divider<=0;bit_index<=0;shift<=0;reading<=0;read_data<=0;response<=0;end
  else begin
   done<=0;
   if(!busy)begin
    mdc<=0;divider<=0;
    if(start)begin busy<=1;reading<=read_op;read_data<=0;response<=0;bit_index<=0;
     shift<={32'hffffffff,2'b01,(read_op?2'b10:2'b01),phy_addr,reg_addr,2'b10,write_data};
    end
   end else if(divider==31)begin
    divider<=0;mdc<=~mdc;
    if(!mdc)begin
     if(reading && bit_index==47)response<=!mdio_sync[1];
     if(reading && bit_index>=48)read_data<={read_data[14:0],mdio_sync[1]};
    end else begin
     if(bit_index==63)begin busy<=0;done<=1;end
     else begin bit_index<=bit_index+1'b1;shift<={shift[62:0],1'b1};end
    end
   end else divider<=divider+1'b1;
  end
endmodule

// Board schematic RTL8211E PHY. Scan addresses 1..7, verify 001C:C915,
// force RGMII RX delay on / TX delay off by RMW, advertise only 100M full.
// Delay bits follow Linux realtek.c RTL8211E_RX_DELAY=BIT(11), TX=BIT(12).
module ethernet_phy_config #(parameter BOOT_CYCLES=1048576)(
 input clk,rst,poll,inout mdio,output mdc,output reg configured,link_100_full,output reg [2:0] address);
 reg [20:0] boot_count;reg boot_done;
 reg [3:0] step;reg waiting,start;reg [15:0] delay_value;reg [5:0] link_misses;
 reg read_op;reg [4:0] reg_addr;reg [15:0] write_data;
 wire busy,done,response;wire [15:0] read_data;
 ethernet_mdio md(.clk(clk),.rst(rst),.start(start),.read_op(read_op),.phy_addr({2'd0,address}),.reg_addr(reg_addr),.write_data(write_data),.mdc(mdc),.mdio(mdio),.busy(busy),.done(done),.read_data(read_data),.response(response));
 always @* begin
  read_op=0;reg_addr=0;write_data=0;
  case(step)
   0:begin read_op=1;reg_addr=2;end
   1:begin read_op=1;reg_addr=3;end
   2:begin reg_addr=31;write_data=7;end
   3:begin reg_addr=30;write_data=16'ha4;end
   4:begin read_op=1;reg_addr=28;end
   5:begin reg_addr=28;write_data=(delay_value & 16'hc7ff)|16'h2800;end
   6:begin reg_addr=31;write_data=0;end
   7:begin reg_addr=9;write_data=0;end
   8:begin reg_addr=4;write_data=16'h0101;end
   9:begin reg_addr=0;write_data=16'h1200;end
   10:begin read_op=1;reg_addr=17;end
  endcase
 end
 always @(posedge clk or posedge rst)
  if(rst)begin boot_count<=0;boot_done<=0;step<=0;waiting<=0;start<=0;configured<=0;link_100_full<=0;address<=1;delay_value<=0;link_misses<=0;end
  else begin
   start<=0;
   if(!boot_done)begin
    if(boot_count==BOOT_CYCLES-1)boot_done<=1;else boot_count<=boot_count+1'b1;
   end else if(!waiting && !busy && (step!=10 || poll))begin start<=1;waiting<=1;end
   if(done && waiting)begin
    waiting<=0;
    case(step)
     0:if(response && read_data==16'h001c)step<=1;else address<=(address==7)?1:address+1'b1;
     1:if(response && read_data==16'hc915)step<=2;else begin address<=(address==7)?1:address+1'b1;step<=0;end
     4:if(response)begin delay_value<=read_data;step<=5;end else begin step<=0;configured<=0;end
     9:begin configured<=1;step<=10;end
     10:begin
      link_100_full<=response && read_data[15:14]==1 && read_data[13] && read_data[10];
      if(response && read_data[15:14]==1 && read_data[13] && read_data[10])link_misses<=0;
      else if(link_misses==63 || (!response && link_misses>=3))begin
       // A PHY-only reset may have restored gigabit advertisement/delay straps.
       // Re-discover and re-apply the complete profile, without resetting caches.
       configured<=0;link_100_full<=0;link_misses<=0;address<=1;step<=0;
      end else link_misses<=link_misses+1'b1;
     end
     default:step<=step+1'b1;
    endcase
   end
  end
endmodule
