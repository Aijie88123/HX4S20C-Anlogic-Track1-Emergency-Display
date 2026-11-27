`timescale 1ns/1ps
module tb_sensor_owner;
 reg clk=0,rst=1,toggle=0,step=0,valid=0;reg[10:0] command=0;wire emergency;wire[1:0] event_type;
 always #5 clk=~clk;
 dual_board_emergency_control dut(.clk(clk),.rst(rst),.local_toggle(toggle),.local_event_step(step),.remote_valid(valid),.remote_command(command),.emergency_mode(emergency),.emergency_event(event_type));
 integer sequence_number=0,checks=0,e,r,k;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task check(input bit pass,input string text);begin checks++;if(!pass)$fatal(1,"%s",text);end endtask
 task send(input bit on,input[1:0] ev);begin sequence_number++;command={sequence_number[7:0],ev,on};valid=1;cycles(1);valid=0;cycles(1);end endtask
 task local_toggle;begin toggle=1;cycles(1);toggle=0;cycles(1);end endtask
 task local_step;begin step=1;cycles(1);step=0;cycles(1);end endtask
 initial begin
 cycles(3);rst=0;cycles(1);send(1,0);check(emergency&&event_type==0&&dut.remote_owner,"remote normal entry");send(1,2);check(emergency&&event_type==2&&dut.remote_owner,"remote owned event change");send(0,0);check(!emergency&&!dut.remote_owner,"remote owned STOP");
 for(e=0;e<4;e++)begin
  local_toggle;for(k=0;k<e;k++)local_step;
  for(r=0;r<4;r++)begin send(1,r);check(emergency&&event_type==e&&!dut.remote_owner,"remote entry stole local ownership/event");send(0,0);check(emergency&&event_type==e&&!dut.remote_owner,"remote STOP cleared local owner");end
  local_toggle;check(!emergency&&!dut.remote_owner,"local explicit exit");
 end
 sequence_number++;command={sequence_number[7:0],2'd2,1'b1};toggle=1;valid=1;cycles(1);toggle=0;valid=0;cycles(1);
 check(emergency&&event_type==0&&!dut.remote_owner,"in-flight FIRE raced local toggle");valid=1;cycles(5);valid=0;check(!dut.remote_owner&&event_type==0,"repeat heartbeat stole owner");
 send(1,3);send(0,0);check(emergency&&!dut.remote_owner,"new sensor FIRE then STOP bypassed local owner");local_toggle;
 send(1,1);check(emergency&&event_type==1&&dut.remote_owner,"new remote event after local exit");send(0,0);check(!emergency,"normal STOP restored");
 $display("PASS: %0d ownership checks; all16 local/remote event pairs, normal remote changes, heartbeat replay, local toggle/in-flight FIRE race and STOP preservation",checks);$finish;
 end
endmodule
