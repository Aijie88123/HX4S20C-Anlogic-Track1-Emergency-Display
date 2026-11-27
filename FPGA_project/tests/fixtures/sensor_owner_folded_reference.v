// Local S4 retains its original toggle. Remote messages set absolute state.
// Repeated heartbeats never retrigger/override a local operation. No timeout clear.
module sensor_owner_reference(input clk,rst,local_toggle,local_event_step,
 input remote_valid,input [10:0] remote_command,
 output reg emergency_mode,output reg [1:0] emergency_event);
 reg seen,remote_owner;reg [10:0] last_command;
 wire new_command=remote_valid && (!seen || last_command!=remote_command);
 always @(posedge clk or posedge rst)
  if(rst)begin seen<=0;last_command<=0;remote_owner<=0;emergency_mode<=0;emergency_event<=0;end
  else begin
   if(remote_valid)begin seen<=1;last_command<=remote_command;end
   if(local_toggle)begin
    emergency_mode<=~emergency_mode;remote_owner<=0;
    if(!emergency_mode)emergency_event<=0;else if(local_event_step)emergency_event<=emergency_event+1'b1;
   end
   else if(local_event_step && emergency_mode)emergency_event<=emergency_event+1'b1;
   else if(new_command && remote_command[0] && (!emergency_mode || remote_owner))begin
    // Gate the full remote FIRE branch: an active local owner retains event and ownership.
    emergency_mode<=1;emergency_event<=remote_command[2:1];remote_owner<=1;
   end else if(new_command && !remote_command[0])begin
    if(remote_owner)begin emergency_mode<=0;emergency_event<=0;end
    remote_owner<=0;
   end else if(!emergency_mode)emergency_event<=0;
  end
endmodule
