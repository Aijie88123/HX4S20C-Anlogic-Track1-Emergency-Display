// Direct FPGA UART, 8 data bits, no parity, one stop bit. No generated clock.
module maintenance_uart #(parameter CLK_HZ=25000000,BAUD=115200)(
 input clk,rst,rx,output reg tx,
 output reg rx_valid,output reg [7:0] rx_data,output reg rx_error,
 input tx_valid,input [7:0] tx_data,output tx_ready);
 localparam DIV=(CLK_HZ+BAUD/2)/BAUD;
 localparam CW=$clog2(DIV)>0?$clog2(DIV):1;
 (* async_reg="true" *) reg rx_meta,rx_sync;reg rx_d;
 reg [2:0] rx_state,rx_bit;reg [CW-1:0] rx_count;reg [7:0] rx_shift;
 reg tx_busy;reg [3:0] tx_bit;reg [9:0] tx_shift;reg [CW-1:0] tx_count;
 assign tx_ready=!tx_busy;
 always @(posedge clk or posedge rst)
  if(rst)begin rx_meta<=1;rx_sync<=1;rx_d<=1;end
  else begin rx_meta<=rx;rx_sync<=rx_meta;rx_d<=rx_sync;end
 always @(posedge clk or posedge rst)
  if(rst)begin rx_valid<=0;rx_data<=0;rx_error<=0;rx_state<=0;rx_bit<=0;rx_count<=0;rx_shift<=0;end
  else begin
   rx_valid<=0;rx_error<=0;
   case(rx_state)
    0:if(rx_d&&!rx_sync)begin rx_count<=DIV/2-1;rx_state<=1;end
    1:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else if(!rx_sync)begin rx_state<=2;rx_count<=DIV-1;rx_bit<=0;end else rx_state<=0;
    2:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else begin rx_shift[rx_bit]<=rx_sync;rx_count<=DIV-1;if(rx_bit==7)rx_state<=3;else rx_bit<=rx_bit+1'b1;end
    3:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else begin rx_state<=0;if(rx_sync)begin rx_data<=rx_shift;rx_valid<=1;end else rx_error<=1;end
   endcase
  end
 always @(posedge clk or posedge rst)
  if(rst)begin tx<=1;tx_busy<=0;tx_bit<=0;tx_shift<=10'h3ff;tx_count<=0;end
  else if(!tx_busy)begin
   tx<=1;
   if(tx_valid)begin tx_busy<=1;tx<=0;tx_shift<={1'b1,tx_data,1'b0};tx_bit<=0;tx_count<=DIV-1;end
  end else if(tx_count!=0)tx_count<=tx_count-1'b1;
  else if(tx_bit==9)begin tx<=1;tx_busy<=0;end
  else begin tx_shift<={1'b1,tx_shift[9:1]};tx<=tx_shift[1];tx_bit<=tx_bit+1'b1;tx_count<=DIV-1;end
endmodule
