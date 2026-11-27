`timescale 1ns/1ps
// First qualified high-temperature sample latches the alarm.
// CONFIRM_SAMPLES continues to apply only to cool-down/manual-clear eligibility.
module temperature_alarm #(
 parameter integer CLK_HZ=25000000,STALE_MS=2500,CONFIRM_SAMPLES=3,
 parameter signed [15:0] WARN_RAW=16'sd720,ALARM_RAW=16'sd880,CLEAR_RAW=16'sd800)(
 input clk,rst,reading_valid,sample_valid,input signed [15:0] temperature_raw,input manual_clear,
 output sensor_fault,warning_active,clear_allowed,output reg alarm_latched,alarm_rise,alarm_cleared);
 localparam integer MS_DIV=CLK_HZ/1000;
 localparam integer DCW=$clog2(MS_DIV)>0?$clog2(MS_DIV):1;
 localparam integer ACW=$clog2(STALE_MS+1)>0?$clog2(STALE_MS+1):1;
 localparam integer CCW=$clog2(CONFIRM_SAMPLES+1)>0?$clog2(CONFIRM_SAMPLES+1):1;
 reg [DCW-1:0] div;reg [ACW-1:0] age;reg have_sample;
 reg [CCW-1:0] cool_count;
 wire ms_tick=div==MS_DIV-1;
 assign sensor_fault=!reading_valid || !have_sample || age>=STALE_MS;
 assign warning_active=alarm_latched || (!sensor_fault && temperature_raw>=WARN_RAW);
 assign clear_allowed=alarm_latched && !sensor_fault && cool_count>=CONFIRM_SAMPLES;
 always @(posedge clk or posedge rst)
  if(rst)begin div<=0;age<=0;have_sample<=0;cool_count<=0;alarm_latched<=0;alarm_rise<=0;alarm_cleared<=0;end
  else begin
   alarm_rise<=0;alarm_cleared<=0;
   if(ms_tick)div<=0;else div<=div+1'b1;
   if(sample_valid && reading_valid)begin age<=0;have_sample<=1;end
   else if(ms_tick && age<STALE_MS)age<=age+1'b1;
   if(!reading_valid || (sensor_fault && !sample_valid))begin cool_count<=0;end
   if(sample_valid && reading_valid)begin
    if(temperature_raw>=ALARM_RAW)begin
     if(!alarm_latched)begin alarm_latched<=1;alarm_rise<=1;end
    end
    if(temperature_raw<=CLEAR_RAW)begin if(sensor_fault)cool_count<=1;else if(cool_count<CONFIRM_SAMPLES)cool_count<=cool_count+1'b1;end
    else cool_count<=0;
   end
   // A fault/overtemperature sample on this edge must not permit clearing an old cool decision.
   if(manual_clear && clear_allowed && !(ms_tick && age>=STALE_MS-1 && !sample_valid) && (!sample_valid || temperature_raw<=CLEAR_RAW))begin
    alarm_latched<=0;alarm_cleared<=1;cool_count<=0;
   end
  end
 `ifndef SYNTHESIS
 initial begin
  if(CONFIRM_SAMPLES<1 || STALE_MS<1 || CLK_HZ%1000!=0)$fatal(1,"invalid alarm timing");
  if(CLEAR_RAW>=ALARM_RAW || WARN_RAW>ALARM_RAW)$fatal(1,"invalid signed thresholds");
 end
 `endif
endmodule
