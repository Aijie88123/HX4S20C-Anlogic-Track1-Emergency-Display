`timescale 1ns/1ps
// Independent time/event-driven single-drop DS18B20 responder. No DUT hierarchy access.
module ds18b20_rc_model(inout tri dq,input enabled,stuck_low,corrupt_crc,busy_forever,bad_config,
 output wire drive_low, input signed [15:0] temperature,input integer presence_delay_us,presence_length_us,read_zero_delay_ns);
 reg slave_low=0;assign drive_low=stuck_low || slave_low;assign dq=(stuck_low || slave_low)?1'b0:1'bz;
 reg [7:0] th=8'h4B,tl=8'h46,config_byte=8'h7F;
 reg [15:0] converted=16'h0550;realtime conversion_start=0;
 integer mode=0,rx_bit=0,read_bit=0,config_index=0,convert_commands=0,read_commands=0;
 reg [7:0] rx=0;reg [71:0] pad;realtime started,low_us,bus_low_start;reg from_slave=0;
 function automatic [7:0] crc8(input [63:0] x);reg [7:0] v;integer i;begin v=0;for(i=0;i<64;i=i+1)v=(v>>1)^((v[0]^x[i])?8'h8C:0);crc8=v;end endfunction
 task automatic build_pad;begin
  pad[63:0]={8'h10,8'h0C,8'hFF,bad_config?8'h1F:config_byte,tl,th,converted};
  pad[71:64]=crc8(pad[63:0])^(corrupt_crc?8'h01:8'h00);
 end endtask
 // mode: 0 command, 1 configuration bytes, 2 conversion polling, 3 scratchpad bits.
 always @(negedge dq)bus_low_start=$realtime;
 always @(negedge dq)begin
  if(!slave_low && !stuck_low)begin
   started=$realtime;
   if(enabled)begin
    if(mode==2)fork begin
     #1000;if($realtime-conversion_start<750000000 || busy_forever)begin from_slave=1;slave_low=1;#44000;slave_low=0;wait(dq===1'b1);#1;from_slave=0;end
    end join_none
    else if(mode==3)begin
     if(read_bit==0)begin if($realtime-conversion_start>=750000000 && !busy_forever)converted=temperature;build_pad();end
     if(!pad[read_bit])fork begin #(read_zero_delay_ns);from_slave=1;slave_low=1;#44000;slave_low=0;wait(dq===1'b1);#1;from_slave=0;end join_none
    end
   end
  end
 end
 always @(posedge dq)begin
  if(!stuck_low)begin
   low_us=($realtime-bus_low_start)/1000.0;
   if(low_us>=480)begin
    mode=0;rx_bit=0;read_bit=0;rx=0;config_index=0;
    if(enabled)fork begin #(presence_delay_us*1000);from_slave=1;slave_low=1;#(presence_length_us*1000);slave_low=0;wait(dq===1'b1);#1;from_slave=0;end join_none
   end else if(!from_slave && enabled && low_us<120)begin
    if(mode==3)begin
     // This event may be the slave's late release for a zero; one bit per initiating pulse.
    end else if(mode!=2)begin
     rx[rx_bit]=low_us<15;
     if(rx_bit==7)begin
      rx_bit=0;
      if(mode==1)begin
       case(config_index)0:th=rx;1:tl=rx;2:begin config_byte=rx;mode=0;end endcase
       config_index=config_index+1;
      end else case(rx)
       8'hCC:begin end
       8'h4E:begin mode=1;config_index=0;end
       8'h44:begin conversion_start=$realtime;convert_commands=convert_commands+1;mode=2;end
       8'hBE:begin mode=3;read_bit=0;read_commands=read_commands+1;end
       default:$fatal(1,"Model saw unexpected command %h at %t",rx,$time);
      endcase
     end else rx_bit=rx_bit+1;
    end
   end
  end
 end
 // Advance scratchpad index once per slot, independent of whether slave extended the low.
 always @(negedge dq)if(!slave_low && !stuck_low && enabled && mode==3)begin
  fork begin #60000;if(read_bit<71)read_bit=read_bit+1;end join_none
 end
endmodule
