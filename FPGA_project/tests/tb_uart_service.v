`timescale 1ns/1ps
module tb_uart_service;
 localparam BIT=8680;
 reg clk=0,rst=1,rx=1;always #20 clk=~clk;
 wire tx,action_valid;wire [1:0] action_type,action_value;
 reg online=0,configured=1,link=1,acknowledged=0,origin_uart=0;
 reg [2:0] desired=0,actual=0;reg [1:0] barrier=0;reg [7:0] cached=8'hff;reg [3:0] fault=0;
 reg scene_valid=0;reg [187:0] scene=0;reg blocked=0;wire ready=online&&!blocked&&(action_type!=2||actual[0]);
 b_uart_service dut(.clk(clk),.rst(rst),.uart_rx(rx),.uart_tx(tx),.online(online),.configured(configured),.phy_link(link),.acknowledged(acknowledged),
  .desired(desired),.actual(actual),.origin_uart(origin_uart),.barrier(barrier),.cached(cached),.source_fault(fault),.scene_valid(scene_valid),.scene(scene),
  .control_ready(ready),.control_blocked(blocked),.action_valid(action_valid),.action_type(action_type),.action_value(action_value));
 integer actions=0;
 always @(posedge clk)if(action_valid&&ready)begin
  actions<=actions+1;origin_uart<=1;
  if(action_type==2)barrier<=action_value;
  else begin desired<=action_type==0?{action_value,1'b1}:3'd0;barrier<=0;end
 end
 string lines[0:511];string current="";integer line_count=0;
 integer capture,marks;reg [7:0] got;integer b;
 initial begin capture=$fopen("wire.txt","w");marks=$fopen("marks.txt","w");end
 // Independent centre-of-bit monitor; it does not instantiate our UART RX.
 always @(negedge tx)if(!rst)begin
  #(BIT+BIT/2);
  for(b=0;b<8;b=b+1)begin got[b]=tx;#(BIT);end
  if(tx!==1)$fatal(1,"UART TX stop bit");
  $fwrite(capture,"%c",got);
  if(got==10)begin lines[line_count]=current;line_count=line_count+1;current="";end
  else if(got!=13)current={current,got};
 end
 task byte_send(input [7:0] value,input integer period,input bit bad_stop);integer k;begin
  rx=0;#(period);for(k=0;k<8;k=k+1)begin rx=value[k];#(period);end
  rx=!bad_stop;#(period);rx=1;#(period/3);
 end endtask
 task command(input string s);integer k;begin
  #13;for(k=0;k<s.len();k=k+1)byte_send(s[k],BIT,0);byte_send(13,BIT,0);byte_send(10,BIT,0);
 end endtask
 task transact(input string cmd,input string expected);integer start;begin
  start=line_count;command(cmd);wait(line_count>start);
  if(lines[start]!=expected)$fatal(1,"command %s response got[%s] expected[%s]",cmd,lines[start],expected);
 end endtask
 task status(input string mark);integer start;begin
  start=line_count;command("STATUS?");wait(line_count>start);$fdisplay(marks,"%s %0d",mark,start);
 end endtask
 task new_scene(input [15:0] closed,input bit no_path,input [2:0] exit_n);begin
  @(negedge clk);scene=0;scene[11:10]=actual[2:1];scene[9]=no_path;scene[107:92]=16'h1201;scene[139:124]=closed;
  scene[175:164]=(exit_n==1||exit_n==3)?896:384;scene[187:176]=(exit_n==1||exit_n==2)?278:534;
  scene_valid=1;@(negedge clk);scene_valid=0;
 end endtask
 integer k,start,old_actions,old_revision;reg [63:0] frozen[0:63];integer rows;
 initial begin
  repeat(12)@(negedge clk);rst=0;repeat(20)@(negedge clk);
  transact("PING","PONG");status("OFFLINE");
  transact("DEMO FIRE","ERR LINK_OFFLINE");if(actions!=0)$fatal(1,"offline action");
  online=1;transact("DEMO FIRE","OK REQUEST STATE=1");status("REQUEST_ONLY");
  if(actions!=1||desired!=1||actual!=0)$fatal(1,"request accepted as fake actual");
  actual=1;acknowledged=1;new_scene(16'h0080,0,1);status("ACTIVE_FIRE");old_revision=dut.route_revision;
  online=0;repeat(3)@(negedge clk);online=1;repeat(3)@(negedge clk);
  if(dut.fresh)$fatal(1,"reconnect reused pre-disconnect scene as fresh");
  new_scene(16'h0080,0,1);repeat(2)@(negedge clk);old_revision=dut.route_revision;
  for(k=0;k<100;k=k+1)begin @(negedge clk);scene[31:16]=k;scene[55:32]=k;scene[151:140]=k;scene_valid=1;@(negedge clk);scene_valid=0;end
  if(dut.route_revision!=old_revision)$fatal(1,"counted moving scene packets as replans");
  transact("BARRIER SET 2","OK REQUEST BARRIER=2");status("BARRIER_PENDING");
  new_scene(16'hc080,0,2);status("BARRIER_APPLIED");
  transact("BARRIER SET 3","OK REQUEST BARRIER=3");new_scene(16'hf080,1,0);status("NO_ROUTE");
  transact("TEMP?","ERR SENSOR_NOT_INSTALLED");
  transact("LOG READ 0","ERR RANGE");transact("LOG READ 65","ERR RANGE");
  transact("BARRIER SET 9","ERR COMMAND");transact("DEMO BAD","ERR COMMAND");
  transact("STATUS?EXTRA","ERR COMMAND");transact("12345678901234567","ERR LINE");
  blocked=1;old_actions=actions;transact("DEMO LAB","ERR KEY_PRIORITY");blocked=0;
  if(actions!=old_actions)$fatal(1,"key priority lost");
  // Fill and wrap the ring with actual source-cache changes.
  for(k=0;k<80;k=k+1)begin @(negedge clk);cached=k;repeat(10)@(negedge clk);end
  repeat(20)@(negedge clk);if(dut.log_count!=64||dut.log_lost==0)$fatal(1,"ring retention/wrap");
  start=line_count;command("LOG READ 64");wait(dut.snapshot_ready);@(negedge clk);
  for(k=0;k<64;k=k+1)frozen[k]=dut.u_log.exported[k];
  fork
   begin for(integer n=0;n<100;n=n+1)begin repeat(100)@(negedge clk);cached=n+101;end end
   begin command("DEMO DRILL");end
  join
  wait(line_count>=start+66);if(lines[start+65]!="END LOG")$fatal(1,"log footer/order");
  for(k=0;k<64;k=k+1)$fdisplay(marks,"LOGROW %0d %016h",start+1+k,frozen[k]);
  wait(line_count>=start+67);if(lines[start+66]!="ERR BUSY")$fatal(1,"busy command not rejected");
  if(actions!=old_actions)$fatal(1,"executed busy command");
  transact("LOG CLEAR","OK LOG CLEARED");repeat(30)@(negedge clk);status("CLEARED");
  // Partial lines expire without changing control state.
  byte_send("D",BIT,0);byte_send("E",BIT,0);start=line_count;#1010000000;wait(line_count>start);
  if(lines[start]!="ERR TIMEOUT")$fatal(1,"line timeout");status("STALE");
  // False start, baud offsets, and a framing error followed by clean recovery.
  rx=0;#80;rx=1;#100000;
  for(k=0;k<10;k=k+1)begin
   start=line_count;byte_send("P",k[0]?BIT+160:BIT-160,0);byte_send("I",k[0]?BIT+160:BIT-160,0);byte_send("N",k[0]?BIT+160:BIT-160,0);byte_send("G",k[0]?BIT+160:BIT-160,0);byte_send(10,k[0]?BIT+160:BIT-160,0);
   wait(line_count>start);if(lines[start]!="PONG")$fatal(1,"baud offset receive");
  end
  start=line_count;byte_send(8'h55,BIT,1);wait(line_count>start);if(lines[start]!="ERR UART_FRAME")$fatal(1,"framing error report");
  start=line_count;byte_send(10,BIT,0);wait(line_count>start);if(lines[start]!="ERR LINE")$fatal(1,"framing partial line survived");transact("PING","PONG");
  transact("DEMO QUAKE","OK REQUEST STATE=3");actual=3;new_scene(16'h0001,0,2);
  transact("DEMO LAB","OK REQUEST STATE=5");actual=5;new_scene(16'h0400,0,3);
  transact("DEMO DRILL","OK REQUEST STATE=7");actual=7;new_scene(16'h0020,0,4);
  transact("DEMO STOP","OK REQUEST STATE=0");actual=0;
  transact("BARRIER SET 1","ERR NOT_EMERGENCY");status("NORMAL");
  $display("PASS: actual1152008N1 UART wire,independent TX monitor,request/actual/barrier/freshness,all4demo+stop,key/offline/busy/error/timeout,100motionpackets no route-count inflation,64record snapshot while ring changes.");$finish;
 end
 initial begin #(64'd2500000000);$fatal(1,"UART service timeout state=%0d lines=%0d",dut.state,line_count);end
endmodule

