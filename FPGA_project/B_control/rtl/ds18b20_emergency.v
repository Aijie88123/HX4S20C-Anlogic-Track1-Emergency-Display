`timescale 1ns/1ps
// Place DQ tri-state only at the FPGA top-level I/O boundary. Same clk as B net_clk.
module ds18b20_emergency #(
 parameter integer CLK_HZ=25000000,CONFIRM_SAMPLES=3,
 parameter signed [15:0] WARN_RAW=16'sd720,ALARM_RAW=16'sd880,CLEAR_RAW=16'sd800)(
 input clk,rst,input manual_clear,inout dq,
 output signed [15:0] temperature_raw,output reading_valid,sample_valid,
 output [2:0] fault_code,output sensor_fault,warning_active,alarm_latched,clear_allowed,
 output request_valid,input request_ready,output [1:0] request_type,request_value,
 output request_accepted,block_nonbarrier);
 wire drive_low,alarm_rise,alarm_cleared;reg pending;
 assign request_valid=pending && alarm_latched;
 assign dq=drive_low?1'b0:1'bz;
 ds18b20_master #(.CLK_HZ(CLK_HZ)) master(.clk(clk),.rst(rst),.dq_in(dq),.drive_low(drive_low),
  .temperature_raw(temperature_raw),.reading_valid(reading_valid),.sample_valid(sample_valid),
  .fault_pulse(),.fault_code(fault_code),.busy());
 temperature_alarm #(.CLK_HZ(CLK_HZ),.CONFIRM_SAMPLES(CONFIRM_SAMPLES),.WARN_RAW(WARN_RAW),
  .ALARM_RAW(ALARM_RAW),.CLEAR_RAW(CLEAR_RAW)) alarm(.clk(clk),.rst(rst),.reading_valid(reading_valid),
  .sample_valid(sample_valid),.temperature_raw(temperature_raw),.manual_clear(manual_clear),
  .sensor_fault(sensor_fault),.warning_active(warning_active),.clear_allowed(clear_allowed),
  .alarm_latched(alarm_latched),.alarm_rise(alarm_rise),.alarm_cleared(alarm_cleared));
 assign request_type=2'd0;assign request_value=2'd0; // Existing B action: DEMO FIRE.
 assign request_accepted=request_valid && request_ready;
 assign block_nonbarrier=alarm_latched;
 always @(posedge clk or posedge rst)
  if(rst)pending<=0;
  else if(alarm_rise)pending<=1;
  else if(alarm_cleared || request_accepted)pending<=0;
endmodule

// Combinational priority mux for the existing synchronous B action interface.
// Selection may change while not ready; each producer holds its own pending command.
// Not an AXI bus: downstream only consumes on action_valid && action_ready.
// downstream_ready must include online, actual command readiness and local key arbitration.
module sensor_action_arbiter(
 input sensor_valid,sensor_lock,input [1:0] sensor_type,sensor_value,output sensor_ready,
 input uart_valid,input [1:0] uart_type,uart_value,output uart_ready,
 output action_valid,output [1:0] action_type,action_value,input action_ready);
 wire choose_sensor=sensor_valid;
 wire allow_uart=!sensor_lock || uart_type==2'd2; // retain barrier controls during alarm
 assign action_valid=choose_sensor || (uart_valid && allow_uart);
 assign action_type=choose_sensor?sensor_type:uart_type;
 assign action_value=choose_sensor?sensor_value:uart_value;
 assign sensor_ready=action_ready && choose_sensor;
 assign uart_ready=action_ready && !choose_sensor && allow_uart;
endmodule
