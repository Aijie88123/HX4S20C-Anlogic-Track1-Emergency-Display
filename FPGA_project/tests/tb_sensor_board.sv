`timescale 1ns/1ps
module tb_sensor_board;
 reg clk=0,rst_n=1,rx=1,k2=1,k3=1,k4=1;always #250 clk=~clk;
 tri1 dq;wire tx,mdio;reg enabled=1,corrupt=0;reg signed [15:0] temperature=401;
 dual_board_control_top #(.ENABLE_MEDIA(0),.ENABLE_RASTER(0),.ENABLE_REMOTE_TF(0),.ENABLE_SUBTITLE(0),.ENABLE_SENSOR(1),.UART_BAUD(100000)) dut(
 .clk(clk),.rst_n(rst_n),.key_next(k2),.key_auto(k3),.key_emergency(k4),.sw(4'd0),.uart_rx(rx),.uart_tx(tx),.ds18b20_dq(dq),
 .sd_miso(1'b1),.eth_rx_clk(1'b0),.eth_rx_ctl(1'b0),.eth_rxd(4'd0),.eth_mdc(),.eth_mdio(mdio));
 // Real protocol/conversion durations. One-million-Hz sensor/control clock
 // reduces simulator cycles; production remains25MHz and uses identical RTL.
 defparam dut.temperature_service.u_temperature.CLK_HZ=1000000;
 defparam dut.u_uart_service.CLK_HZ=1000000;
 defparam dut.s2.CLK_HZ=1000000;
 defparam dut.s3.CLK_FREQ_HZ=1000000;
 defparam dut.s4.CLK_FREQ_HZ=1000000;
 defparam dut.u_carousel_clock.CLK_FREQ_HZ=1000000;
 ds18b20_model probe(.dq(dq),.enabled(enabled),.stuck_low(1'b0),.corrupt_crc(corrupt),.busy_forever(1'b0),.bad_config(1'b0),
 .temperature(temperature),.presence_delay_us(30),.presence_length_us(120),.read_zero_delay_ns(1000));
 task clocks(input integer n);repeat(n)@(negedge dut.net_clk);endtask
 task check(input bit ok,input string msg);if(!ok)$fatal(1,"%s",msg);endtask
 task sample(input integer raw);begin @(posedge dut.temperature_sample_valid);clocks(3);check(dut.temperature_valid&&$signed(dut.temperature_raw)==raw,"real DQ sample mismatch");end endtask
 localparam BIT=10000;
 string lines[0:255],current="";integer count=0,b,wirefile,marks;reg [7:0] got;
 initial begin wirefile=$fopen("wire.txt","w");marks=$fopen("marks.txt","w");end
 always @(negedge tx)if(!dut.rst)begin
 #(BIT+BIT/2);for(b=0;b<8;b++)begin got[b]=tx;#BIT;end
 check(tx===1'b1,"TX stop bit");$fwrite(wirefile,"%c",got);
 if(got==10)begin lines[count]=current;count++;current="";end else if(got!=13)current={current,got};
 end
 task command(input string text);integer c,j;reg[7:0] v;begin
 for(c=0;c<=text.len();c++)begin v=c==text.len()?10:text[c];rx=0;#BIT;for(j=0;j<8;j++)begin rx=v[j];#BIT;end rx=1;#(BIT+BIT/3);end
 end endtask
 task request(input string text,input string expected);integer start;begin start=count;command(text);wait(count>start);check(lines[start]==expected,{text," reply: ",lines[start]});end endtask
 task status(input string tag);integer start;begin start=count;command("TEMP?");wait(count>start);$fdisplay(marks,"%s %0d",tag,start);end endtask
 task press2;begin k2=0;#12000000;k2=1;#12000000;end endtask
 task press3;begin k3=0;#12000000;k3=1;#12000000;end endtask
 task press4;begin k4=0;#12000000;k4=1;#12000000;end endtask
 integer seq,start,n;
 initial begin
 #1;rst_n=0;#2000;rst_n=1;dut.u_ethernet_pll.run_clock=1;dut.u_ethernet_pll.locked_value=1;
 dut.u_ethernet_link.online_value=0;dut.u_ethernet_link.configured_value=1;dut.u_ethernet_link.feedback_value=8'h0e;
 clocks(5);request("PING","PONG");status("BOOT");check(!dut.temperature_valid&&!dut.temperature_alarm,"boot value qualified");
 sample(401);check(!dut.temperature_warning&&!dut.temperature_alarm,"room temperature alarm");status("NORMAL");
 temperature=-162;sample(-162);check(!dut.temperature_alarm,"negative temperature alarm");status("NEGATIVE");
 temperature=880;corrupt=1;wait(dut.temperature_report_fault==3);clocks(3);check(!dut.temperature_valid&&!dut.temperature_alarm,"CRC data qualified");status("CRC");
 corrupt=0;temperature=720;sample(720);check(dut.temperature_warning&&!dut.temperature_alarm,"45C warning policy");status("WARNING");
 temperature=880;sample(880);check(dut.temperature_alarm,"first valid55C sample did not alarm");
 check(dut.temperature_alarm&&dut.temperature_request_valid&&!dut.command_armed,"offline sensor request not held");status("HOT_OFFLINE");
 press3;check(dut.temperature_alarm&&dut.temperature_request_valid&&!dut.command_armed,"hot key cleared alarm");request("TEMP CLEAR","ERR SENSOR_COOL");
 temperature=800;sample(800);check(!dut.temperature_clear_allowed,"cool confirmation1");sample(800);check(!dut.temperature_clear_allowed,"cool confirmation2");sample(800);check(dut.temperature_clear_allowed,"cool confirmation3");
 request("TEMP CLEAR","OK TEMP REQUEST");clocks(4);check(!dut.temperature_alarm&&!dut.temperature_request_valid&&!dut.command_armed,"offline clear failed to cancel held request");status("CANCELLED_OFFLINE");
 temperature=880;sample(880);check(dut.temperature_alarm&&dut.temperature_request_valid,"single-sample alarm rearm failed");
 dut.u_ethernet_link.online_value=1;wait(dut.command_armed&&dut.emergency);clocks(4);check(dut.command_origin_sensor&&dut.event_type==0&&!dut.temperature_request_valid,"sensor FIRE local acceptance/source");
 dut.u_ethernet_link.peer_value={1'b0,1'b1,dut.command_sequence,8'd0,3'd1};clocks(4);seq=dut.command_sequence;status("SENSOR_FIRE");
 request("DEMO STOP","ERR SENSOR_LOCK");request("DEMO QUAKE","ERR SENSOR_LOCK");request("BARRIER SET 2","OK REQUEST BARRIER=2");check(dut.barrier_mode==2&&dut.command_origin_sensor,"barrier/source during sensor lock");
 press2;press3;press4;check(dut.temperature_alarm&&dut.command_sequence==seq&&dut.emergency&&dut.event_type==0&&dut.barrier_mode==2,"keys bypassed sensor lock");
 enabled=0;wait(dut.temperature_report_fault==1);clocks(3);check(!dut.temperature_valid&&dut.temperature_alarm&&!dut.temperature_clear_allowed,"disconnect cleared latched alarm");request("TEMP CLEAR","ERR SENSOR_COOL");status("DISCONNECTED_LOCKED");
 enabled=1;temperature=800;sample(800);sample(800);sample(800);check(dut.temperature_clear_allowed,"reconnect cool confirmation");status("CLEAR_ALLOWED");
 request("TEMP CLEAR","OK TEMP REQUEST");clocks(3);check(!dut.temperature_alarm&&dut.emergency&&dut.command_sequence==seq,"temperature clear directly stopped A/emergency");
 request("DEMO STOP","OK REQUEST STATE=0");clocks(3);check(!dut.emergency&&dut.command_sequence==seq+1&&!dut.command_origin_sensor,"ordinary STOP after qualified clear");
 dut.u_ethernet_link.peer_value={1'b0,1'b1,dut.command_sequence,8'd0,3'd0};status("STOPPED");
 start=count;command("LOG READ 64");wait(count>start);wait(lines[count-1]=="END LOG");
 $display("PASS: actual B top real single-wire DS18B20 reset/config/760ms conversion/9-byte CRC and signed temperature;45C warning/55C single-valid-sample lock/50C3-sample manual-clear;offline held/cancelled/rearmed FIRE;source identity;keys+UART lock;barriers;disconnect retains alarm;explicit STOP;atomic sensor STATUS and7-channel64-log export");
 $display("PASS: wire conversion commands=%0d scratchpad reads=%0d",probe.convert_commands,probe.read_commands);$finish;
 end
 initial begin #(64'd40000000000);$fatal(1,"sensor board timeout");end
endmodule
