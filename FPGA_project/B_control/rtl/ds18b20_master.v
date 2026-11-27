`timescale 1ns/1ps
// One externally powered DS18B20 per DQ. No parasite supply, Search ROM or EEPROM writes.
module ds18b20_master #(
 parameter integer CLK_HZ=25000000,POWERUP_US=100000,
 parameter integer CONVERSION_US=760000,SAMPLE_PERIOD_US=1000000)(
 input clk,rst,dq_in,output drive_low,
 output reg signed [15:0] temperature_raw,output reg reading_valid,sample_valid,fault_pulse,
 output reg [2:0] fault_code,output busy);
 localparam integer US=CLK_HZ/1000000;
 localparam integer UCW=$clog2(US)>0?$clog2(US):1;
 localparam integer MAX_WAIT=POWERUP_US>SAMPLE_PERIOD_US?POWERUP_US:SAMPLE_PERIOD_US;
 localparam integer LONGEST=MAX_WAIT>CONVERSION_US?MAX_WAIT:CONVERSION_US;
 localparam integer WCW=$clog2(LONGEST+1)>0?$clog2(LONGEST+1):1;
 localparam BOOT=0,CYCLE=1,RESET_SEND=2,RESET_WAIT=3,TX_SEND=4,TX_WAIT=5,
  CONVERT_WAIT=6,POLL_SEND=7,POLL_WAIT=8,RX_SEND=9,RX_WAIT=10,CHECK=11,REST=12;
 reg [3:0] state;reg [UCW-1:0] us_div;wire us_tick=us_div==US-1;
 reg [WCW-1:0] wait_us,cycle_us;
 reg [1:0] phase;reg [2:0] tx_byte,bit_index;reg [6:0] read_index;
 reg [15:0] sample_word;reg [7:0] receive_byte,crc;reg content_ok;
 reg slot_start,slot_write;reg [1:0] slot_operation;
 wire slot_busy,slot_done,slot_read;wire [2:0] slot_error;
 onewire_slot #(.CLK_HZ(CLK_HZ)) slot(.clk(clk),.rst(rst),.dq_in(dq_in),.start(slot_start),
  .operation(slot_operation),.write_bit(slot_write),.drive_low(drive_low),.busy(slot_busy),
  .done(slot_done),.read_bit(slot_read),.error(slot_error));
 function [7:0] command_byte;input [1:0] p;input [2:0] i;begin
  if(i==0)command_byte=8'hCC;
  else if(p==0)case(i)1:command_byte=8'h4E;2:command_byte=8'h4B;3:command_byte=8'h46;default:command_byte=8'h7F;endcase
  else command_byte=p==1?8'h44:8'hBE;
 end endfunction
 wire [7:0] tx_data=command_byte(phase,tx_byte);
 wire [7:0] crc_next={1'b0,crc[7:1]}^((crc[0]^slot_read)?8'h8C:8'h00);
 wire [7:0] received_byte={slot_read,receive_byte[7:1]};
 wire signed [15:0] decoded=$signed(sample_word);
 assign busy=state!=BOOT && state!=REST;
 always @(posedge clk or posedge rst)begin
  if(rst)us_div<=0;else if(us_tick)us_div<=0;else us_div<=us_div+1'b1;
 end
 always @(posedge clk or posedge rst)
  if(rst)begin state<=BOOT;wait_us<=0;cycle_us<=0;phase<=0;tx_byte<=0;bit_index<=0;read_index<=0;sample_word<=0;receive_byte<=0;content_ok<=1;crc<=0;
   slot_start<=0;slot_write<=0;slot_operation<=0;temperature_raw<=0;reading_valid<=0;sample_valid<=0;fault_pulse<=0;fault_code<=0;
  end else begin
   slot_start<=0;sample_valid<=0;fault_pulse<=0;
   if(us_tick && cycle_us<SAMPLE_PERIOD_US)cycle_us<=cycle_us+1'b1;
   case(state)
    BOOT:if(us_tick)begin if(wait_us>=POWERUP_US-1)begin wait_us<=0;state<=CYCLE;end else wait_us<=wait_us+1'b1;end
    CYCLE:begin phase<=0;cycle_us<=0;state<=RESET_SEND;end
    RESET_SEND:if(!slot_busy)begin slot_operation<=0;slot_start<=1;state<=RESET_WAIT;end
    RESET_WAIT:if(slot_done)begin
     if(slot_error!=0)begin reading_valid<=0;fault_pulse<=1;fault_code<=slot_error;state<=REST;end
     else begin tx_byte<=0;bit_index<=0;state<=TX_SEND;end
    end
    TX_SEND:if(!slot_busy)begin slot_operation<=1;slot_write<=tx_data[bit_index];slot_start<=1;state<=TX_WAIT;end
    TX_WAIT:if(slot_done)begin
     if(bit_index!=7)begin bit_index<=bit_index+1'b1;state<=TX_SEND;end
     else begin
      bit_index<=0;
      if(tx_byte==(phase==0?4:1))begin
       if(phase==0)begin phase<=1;state<=RESET_SEND;end
       else if(phase==1)begin wait_us<=0;state<=CONVERT_WAIT;end
       else begin read_index<=0;crc<=0;sample_word<=0;receive_byte<=0;content_ok<=1;state<=RX_SEND;end
      end else begin tx_byte<=tx_byte+1'b1;state<=TX_SEND;end
     end
    end
    // Full 12-bit conversion wait; the subsequent busy read must also report ready.
    CONVERT_WAIT:if(us_tick)begin if(wait_us>=CONVERSION_US-1)state<=POLL_SEND;else wait_us<=wait_us+1'b1;end
    POLL_SEND:if(!slot_busy)begin slot_operation<=2;slot_start<=1;state<=POLL_WAIT;end
    POLL_WAIT:if(slot_done)begin
     if(!slot_read)begin reading_valid<=0;fault_pulse<=1;fault_code<=5;state<=REST;end
     else begin phase<=2;state<=RESET_SEND;end
    end
    RX_SEND:if(!slot_busy)begin slot_operation<=2;slot_start<=1;state<=RX_WAIT;end
    RX_WAIT:if(slot_done)begin
     receive_byte<=received_byte;crc<=crc_next;
     if(read_index[2:0]==7)case(read_index[6:3])
      0:sample_word[7:0]<=received_byte;
      1:sample_word[15:8]<=received_byte;
      2:if(received_byte!=8'h4B)content_ok<=0;
      3:if(received_byte!=8'h46)content_ok<=0;
      4:if(received_byte!=8'h7F)content_ok<=0;
      default:begin end
     endcase
     if(read_index==71)state<=CHECK;else begin read_index<=read_index+1'b1;state<=RX_SEND;end
    end
    CHECK:begin
     state<=REST;
     if(crc!=0)begin reading_valid<=0;fault_code<=3;fault_pulse<=1;end
     // Written TH/TL and 12-bit config must read back. This also rejects all-zero buses.
     else if(!content_ok || decoded < -16'sd880 || decoded > 16'sd2000)begin
      reading_valid<=0;fault_code<=4;fault_pulse<=1;
     end else begin temperature_raw<=decoded;reading_valid<=1;sample_valid<=1;fault_code<=0;end
    end
    REST:if(cycle_us>=SAMPLE_PERIOD_US)state<=CYCLE;
    default:begin state<=BOOT;wait_us<=0;reading_valid<=0;fault_code<=6;fault_pulse<=1;end
   endcase
  end
 `ifndef SYNTHESIS
 initial begin
  if(CONVERSION_US<750000)$fatal(1,"12-bit DS18B20 requires >=750000us conversion wait");
  if(POWERUP_US<1 || SAMPLE_PERIOD_US<1)$fatal(1,"invalid wait parameters");
 end
 `endif
endmodule
