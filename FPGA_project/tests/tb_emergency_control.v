module tb_emergency_control;
 reg clk=0;always #7 clk=~clk;
 reg rst=1,toggle=0,step=0,valid=0;reg [10:0] command=0;
 wire mode;wire [1:0] event_type;
 dual_board_emergency_control dut(.clk(clk),.rst(rst),.local_toggle(toggle),.local_event_step(step),.remote_valid(valid),.remote_command(command),.emergency_mode(mode),.emergency_event(event_type));
 reg old_mode=0;reg [1:0] old_event=0;integer i;
 always @(posedge clk)begin
  if(rst)begin old_mode<=0;old_event<=0;end
  else begin
   if(toggle)old_mode<=~old_mode;
   if(!old_mode)old_event<=0;else if(step)old_event<=old_event+1'b1;
  end
 end
 task remote;input [7:0] seq;input [2:0] state;begin @(negedge clk);command={seq,state};valid=1;@(negedge clk);valid=0;end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<2000;i=i+1)begin
   toggle=($random & 31)==0;step=($random & 7)==0;@(negedge clk);
   if(mode!==old_mode)$fatal(1,"FAIL: local S4 changed");
   // Original event resets one cycle after a local toggle; visible state must match.
   if(event_type!==old_event)$fatal(1,"FAIL: local event behavior changed");
  end
  toggle=0;step=0;rst=1;repeat(2)@(negedge clk);rst=0;
  remote(1,5);if(!mode || event_type!=2)$fatal(1,"FAIL: remote alarm/event");
  remote(1,5);if(!mode || event_type!=2)$fatal(1,"FAIL: duplicate changed state");
  @(negedge clk);toggle=1;@(negedge clk);toggle=0;
  remote(1,5);if(mode)$fatal(1,"FAIL: heartbeat overrode local cancellation");
  remote(2,7);if(!mode || event_type!=3)$fatal(1,"FAIL: next remote command");
  repeat(1000)@(negedge clk);if(!mode)$fatal(1,"FAIL: silence cleared alarm");
  remote(3,0);if(mode)$fatal(1,"FAIL: explicit remote clear");
  @(negedge clk);toggle=1;@(negedge clk);toggle=0;repeat(2)@(negedge clk);
  remote(4,0);if(!mode)$fatal(1,"FAIL: remote normal cleared local alarm");
  $display("PASS: local arbitration, remote absolute state, duplicate suppression, local override, explicit clear and alarm retention on silence");$finish;
 end
endmodule
