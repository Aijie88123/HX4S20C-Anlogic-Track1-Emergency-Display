// Local S4 toggles state. New remote heartbeats never override a local owner.
module dual_board_emergency_control(input clk,rst,local_toggle,local_event_step,
 input remote_valid,input [10:0] remote_command,
 output reg emergency_mode,output reg [1:0] emergency_event);
 reg seen,local_owned;reg [10:0] last_command;
 // Reachable-state equivalent of the previous remote_owner encoding.
 wire remote_owner=emergency_mode && !local_owned;
 wire new_command=remote_valid && (!seen || last_command!=remote_command);
 always @(posedge clk or posedge rst)
  if(rst)begin seen<=0;last_command<=0;local_owned<=0;emergency_mode<=0;emergency_event<=0;end
  else begin
   if(remote_valid)begin seen<=1;last_command<=remote_command;end
   if(local_toggle)begin
    emergency_mode<=~emergency_mode;local_owned<=!emergency_mode;
    if(!emergency_mode)emergency_event<=0;else if(local_event_step)emergency_event<=emergency_event+1'b1;
   end
   else if(local_event_step && emergency_mode)emergency_event<=emergency_event+1'b1;
   else if(new_command && remote_command[0] && !local_owned)begin
    emergency_mode<=1;emergency_event<=remote_command[2:1];
   end else if(new_command && !remote_command[0])begin
    if(remote_owner)begin emergency_mode<=0;emergency_event<=0;end
   end else if(!emergency_mode)emergency_event<=0;
  end
endmodule
