// Onboard CH340 maintenance service. All status/control is in net_clk.
// No sensor data is fabricated; no changes to A, V12 or pixel transfer.
module b_uart_service #(parameter CLK_HZ=25000000,BAUD=115200,EXTERNAL_UART=0,ENABLE_SENSOR=0)(
 input clk,rst,uart_rx,output uart_tx,
 input external_rx_valid,external_rx_error,input [7:0] external_rx_data,
 output external_tx_valid,output [7:0] external_tx_data,input external_tx_ready,output service_idle,
 input online,configured,phy_link,acknowledged,input [2:0] desired,actual,input origin_uart,
 input [1:0] barrier,input [7:0] cached,input [3:0] source_fault,
 input scene_valid,input [187:0] scene,
 input signed [15:0] sensor_temperature,
 input sensor_valid,sensor_warning,sensor_alarm,sensor_clear_allowed,sensor_origin,sensor_request_accepted,
 input [2:0] sensor_fault_code,output reg sensor_clear,
 input control_ready,control_blocked,
 output reg action_valid,output reg [1:0] action_type,action_value);
 wire rx_valid,rx_error,tx_ready;wire [7:0] rx_data;wire tx_valid;wire [7:0] tx_data;
 generate if(EXTERNAL_UART)begin: byte_interface
  assign rx_valid=external_rx_valid;assign rx_error=external_rx_error;assign rx_data=external_rx_data;
  assign tx_ready=external_tx_ready;assign uart_tx=1'b1;
 end else begin: wire_interface
 maintenance_uart #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
  .rx_valid(rx_valid),.rx_data(rx_data),.rx_error(rx_error),.tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready));
 end endgenerate
 assign external_tx_valid=tx_valid;assign external_tx_data=tx_data;
 localparam MS_CW=$clog2(CLK_HZ/1000)>0?$clog2(CLK_HZ/1000):1;
 reg [MS_CW-1:0] ms_div;reg [31:0] milliseconds;
 always @(posedge clk or posedge rst)
  if(rst)begin ms_div<=0;milliseconds<=0;end
  else if(ms_div==CLK_HZ/1000-1)begin ms_div<=0;milliseconds<=milliseconds+1'b1;end else ms_div<=ms_div+1'b1;
 reg have_scene,last_no_path;reg [1:0] last_event;reg [2:0] last_exit;
 reg [15:0] last_closed,last_route,route_revision;reg [31:0] scene_at;
 reg have_signature;reg [53:0] signature;
 function [2:0] exit_number;input [187:0] s;begin
  if(s[9])exit_number=0;
  else case({s[187:176],s[175:164]})
   {12'd278,12'd896}:exit_number=1;{12'd278,12'd384}:exit_number=2;
   {12'd534,12'd896}:exit_number=3;{12'd534,12'd384}:exit_number=4;
   default:exit_number=0;
  endcase
 end endfunction
 wire [53:0] incoming_signature={scene[11:10],scene[9],scene[107:92],scene[123:108],scene[139:124],exit_number(scene)};
 wire scene_accepted=online&&scene_valid;
 wire solution_change=scene_accepted&&actual[0]&&scene[11:10]==actual[2:1]&&(!have_signature||signature!=incoming_signature);
 wire [31:0] scene_age=milliseconds-scene_at;
 wire fresh=online&&have_scene&&scene_age<1000&&last_event==actual[2:1];
 function [15:0] expected_closed;input [1:0] e,m;reg [15:0] c;begin
  case(e)0:c=16'h0080;1:c=16'h0001;2:c=16'h0400;3:c=16'h0020;endcase
  if(m==1||m==2)case(e)0:c=c|16'h8000;1:c=c|16'h2000;2:c=c|16'h1000;3:c=c|16'h4000;endcase
  if(m==2)case(e)0:c=c|16'h4000;1:c=c|16'h8000;2:c=c|16'h2000;3:c=c|16'h1000;endcase
  if(m==3)c=c|16'hf000;expected_closed=c;
 end endfunction
 wire barrier_applied=fresh&&actual[0]&&last_closed==expected_closed(actual[2:1],barrier);
 always @(posedge clk or posedge rst)
  if(rst)begin have_scene<=0;last_no_path<=1;last_event<=0;last_exit<=0;last_closed<=0;last_route<=0;route_revision<=0;scene_at<=0;have_signature<=0;signature<=0;end
  else begin
   if(!online)begin have_signature<=0;have_scene<=0;end
   if(scene_accepted)begin have_scene<=1;last_no_path<=scene[9];last_event<=scene[11:10];last_exit<=exit_number(scene);last_closed<=scene[139:124];last_route<=scene[107:92];scene_at<=milliseconds;end
   if(solution_change)begin have_signature<=1;signature<=incoming_signature;if(route_revision!=16'hffff)route_revision<=route_revision+1'b1;end
  end
 wire [6:0] log_count,snapshot_count;wire [15:0] log_lost;wire snapshot_busy,snapshot_ready;
 reg log_clear,snapshot_start;reg [6:0] log_requested;reg [5:0] snapshot_address;wire [63:0] snapshot_data;
 reg [15:0] rx_errors;reg reject_event;reg [7:0] reject_reason;
 reg boot_pending,online_d,fresh_d;reg [2:0] actual_d;reg [11:0] source_d;
 reg [6:0] event_valid;reg [447:0] event_data;reg [6:0] sensor_previous;
 wire [6:0] sensor_state={sensor_fault_code,sensor_valid,sensor_warning,sensor_alarm,sensor_clear_allowed};
 wire action_fire=action_valid&&control_ready&&!control_blocked&&online;
 wire [7:0] context_now={acknowledged?(ENABLE_SENSOR&&sensor_origin?2'd3:{1'b0,origin_uart}):2'd2,actual,barrier,last_no_path};
 function [63:0] record;input [7:0] code,ctx;input [15:0] detail;begin record={milliseconds,code,ctx,detail};end endfunction
 always @*begin
  event_valid=0;event_data=0;
  if(boot_pending)begin event_valid[0]=1;event_data[0+:64]=record(8'h01,0,0);end
  else if(online!=online_d)begin event_valid[0]=1;event_data[0+:64]=record(online?8'h02:8'h03,context_now,0);end
  if(online&&actual!=actual_d)begin event_valid[1]=1;event_data[64+:64]=record(8'h20,context_now,{13'd0,actual});end
  if({source_fault,cached}!=source_d)begin event_valid[2]=1;event_data[128+:64]=record(8'h04,context_now,{4'd0,source_fault,cached});end
  if(action_fire)begin
   event_valid[3]=1;event_data[192+:64]=record(8'h10+action_type,{2'd1,action_type==0?{action_value,1'b1}:desired,barrier,1'b0},{14'd0,action_value});
  end
  if(ENABLE_SENSOR&&sensor_request_accepted)begin event_valid[3]=1;event_data[192+:64]=record(8'h13,{2'd3,3'd1,barrier,1'b0},sensor_temperature);end
  if(ENABLE_SENSOR&&sensor_state!=sensor_previous)begin event_valid[6]=1;event_data[384+:64]=record(8'h70,{1'b0,sensor_state},sensor_temperature);end
  if(solution_change)begin event_valid[4]=1;event_data[256+:64]=record(8'h30|{5'd0,exit_number(scene)},context_now,scene[139:124]);end
  if(reject_event)begin event_valid[5]=1;event_data[320+:64]=record(8'h50,context_now,{8'd0,reject_reason});end
  else if(rx_error)begin event_valid[5]=1;event_data[320+:64]=record(8'h60,context_now,rx_errors);end
  else if(fresh_d&&!fresh)begin event_valid[5]=1;event_data[320+:64]=record(8'h40,context_now,0);end
 end
 always @(posedge clk or posedge rst)
  if(rst)begin boot_pending<=1;online_d<=0;actual_d<=0;source_d<=0;fresh_d<=0;sensor_previous<=7'h7f;end
  else begin boot_pending<=0;online_d<=online;actual_d<=actual;source_d<={source_fault,cached};fresh_d<=fresh;sensor_previous<=sensor_state;end
 maintenance_event_log #(.EVENTS(7)) u_log(.clk(clk),.rst(rst),.clear(log_clear),.event_valid(event_valid),.event_data(event_data),
  .count(log_count),.lost(log_lost),.snapshot_start(snapshot_start),.requested(log_requested),.snapshot_busy(snapshot_busy),
  .snapshot_ready(snapshot_ready),.snapshot_count(snapshot_count),.snapshot_address(snapshot_address),.snapshot_data(snapshot_data));

 // Explicit native INIT values preserve the UART strings in hardware.
 reg [9:0] rom_address,message_base;reg [7:0] message_index,out_byte;wire [7:0] rom_q;
 maintenance_text_rom u_text(.clk(clk),.address(rom_address),.q(rom_q));
 localparam IDLE=0,FETCH=1,WAIT_ROM=2,EVAL=3,SEND=4,HEX=5,LOG_WAIT=6,LOG_READ=7,LOG_DELAY=8,LOG_TAKE=9,ACTION=10;
 reg [3:0] state;reg [1:0] message_kind;reg [6:0] log_row;
 reg [255:0] status_snapshot;reg [63:0] log_record;
 reg [31:0] hex_shift;reg [3:0] hex_left;
 function [7:0] hex_char;input [3:0] n;begin hex_char=n<10?8'd48+n:8'd55+n;end endfunction
 assign tx_valid=state==SEND||state==HEX;
 assign tx_data=state==HEX?hex_char(hex_shift[31:28]):out_byte;
 reg [31:0] token_value;reg [3:0] token_digits;
 always @*begin
  token_value=0;token_digits=1;
  case(rom_q)
   8'h80:begin token_value=status_snapshot[31:0];token_digits=8;end
   8'h81:token_value={1'b0,status_snapshot[158:156],28'd0};
   8'h82:token_value={1'b0,status_snapshot[161:159],28'd0};
   8'h83:token_value={3'd0,status_snapshot[170],28'd0};
   8'h84:token_value={2'd0,(status_snapshot[209]?2'd2:{1'b0,status_snapshot[173]}),28'd0};
   8'h85:token_value={3'd0,status_snapshot[167],28'd0};
   8'h86:token_value={3'd0,status_snapshot[168],28'd0};
   8'h87:begin token_value={status_snapshot[151:144],24'd0};token_digits=2;end
   8'h88:token_value={status_snapshot[155:152],28'd0};
   8'h89:token_value={3'd0,status_snapshot[171],28'd0};
   8'h8a:begin token_value=status_snapshot[63:32];token_digits=8;end
   8'h8b:token_value={1'b0,status_snapshot[166:164],28'd0};
   8'h8c:begin token_value={status_snapshot[79:64],16'd0};token_digits=4;end
   8'h8d:begin token_value={status_snapshot[95:80],16'd0};token_digits=4;end
   8'h8e:begin token_value={status_snapshot[111:96],16'd0};token_digits=4;end
   8'h8f:begin token_value={1'b0,status_snapshot[180:174],24'd0};token_digits=2;end
   8'h90:begin token_value={status_snapshot[127:112],16'd0};token_digits=4;end
   8'h91:begin token_value={status_snapshot[143:128],16'd0};token_digits=4;end
   8'h92:begin token_value={1'b0,snapshot_count,24'd0};token_digits=2;end
   8'h93:token_value={1'b0,status_snapshot[183:181],28'd0};
   8'h94:token_value={2'd0,status_snapshot[185:184],28'd0};
   8'h95:token_value={2'd0,status_snapshot[163:162],28'd0};
   8'h96:token_value={3'd0,status_snapshot[172],28'd0};
   8'h97:begin token_value={status_snapshot[201:186],16'd0};token_digits=4;end
   8'h98:token_value={3'd0,status_snapshot[202],28'd0};
   8'h99:token_value={3'd0,status_snapshot[203],28'd0};
   8'h9a:token_value={3'd0,status_snapshot[204],28'd0};
   8'h9b:token_value={3'd0,status_snapshot[205],28'd0};
   8'h9c:token_value={1'b0,status_snapshot[208:206],28'd0};
   8'ha0:begin token_value=log_record[63:32];token_digits=8;end
   8'ha1:begin token_value={log_record[31:24],24'd0};token_digits=2;end
   8'ha2:begin token_value={log_record[23:16],24'd0};token_digits=2;end
   8'ha3:begin token_value={log_record[15:0],16'd0};token_digits=4;end
  endcase
 end
 wire [255:0] live_snapshot;
 assign live_snapshot={46'd0,(ENABLE_SENSOR&&sensor_origin),(ENABLE_SENSOR?sensor_fault_code:3'd7),(ENABLE_SENSOR&&sensor_clear_allowed),(ENABLE_SENSOR&&sensor_alarm),(ENABLE_SENSOR&&sensor_warning),(ENABLE_SENSOR&&sensor_valid),(ENABLE_SENSOR?sensor_temperature:16'd0),5'd0,log_count,origin_uart,barrier_applied,fresh,acknowledged,phy_link,configured,online,
  (actual[0]&&fresh&&!last_no_path?last_exit:3'd0),barrier,actual,desired,source_fault,cached,rx_errors,log_lost,route_revision,last_route,last_closed,
  (have_scene?scene_age:32'hffffffff),milliseconds};
 // Exactly one request/reply is active. Complete commands received while
 // exporting are rejected, not silently executed. Keys/control never wait TX.
 reg [127:0] line_buffer;reg [4:0] line_length;reg bad_line,saw_cr,busy_reply;
 reg [31:0] last_byte_at;reg [6:0] parsed_count;reg valid_count;
 assign service_idle=state==IDLE&&line_length==0&&!bad_line&&!saw_cr&&!busy_reply;

 always @*begin
  parsed_count=0;valid_count=0;
  if(line_length==10&&line_buffer[79:8]=="LOG READ "&&line_buffer[7:0]>=48&&line_buffer[7:0]<=57)begin parsed_count=line_buffer[7:0]-48;valid_count=1;end
  if(line_length==11&&line_buffer[87:16]=="LOG READ "&&line_buffer[15:8]>=48&&line_buffer[15:8]<=54&&line_buffer[7:0]>=48&&line_buffer[7:0]<=57)begin parsed_count=(line_buffer[15:8]-48)*10+line_buffer[7:0]-48;valid_count=1;end
 end
 task reply;input [9:0] base;begin state<=FETCH;message_base<=base;message_index<=0;rom_address<=base;message_kind<=base==0?2'd3:2'd0;end endtask
 task error_reply;input [9:0] base;input [7:0] reason;begin reply(base);reject_event<=1;reject_reason<=reason;end endtask
 task request_action;input [1:0] kind,value;begin
  if(!online)error_reply(320,8'd4);
  else if(ENABLE_SENSOR&&sensor_alarm&&kind!=2)error_reply(928,8'd10);
  else if(kind==2&&!actual[0])error_reply(352,8'd5);
  else if(control_blocked)error_reply(480,8'd8);
  else begin action_type<=kind;action_value<=value;action_valid<=1;state<=ACTION;end
 end endtask
 always @(posedge clk or posedge rst)
  if(rst)begin
   state<=IDLE;message_kind<=0;message_base<=0;message_index<=0;rom_address<=0;out_byte<=0;hex_shift<=0;hex_left<=0;
   status_snapshot<=0;log_record<=0;log_row<=0;log_requested<=0;snapshot_address<=0;snapshot_start<=0;log_clear<=0;
   line_buffer<=0;line_length<=0;bad_line<=0;saw_cr<=0;busy_reply<=0;last_byte_at<=0;
   action_valid<=0;action_type<=0;action_value<=0;rx_errors<=0;reject_event<=0;reject_reason<=0;sensor_clear<=0;
  end else begin
   snapshot_start<=0;log_clear<=0;reject_event<=0;sensor_clear<=0;
   case(state)
    IDLE:if(busy_reply&&!rx_valid)begin busy_reply<=0;error_reply(288,8'd3);end
    FETCH:begin rom_address<=message_base+message_index;state<=WAIT_ROM;end
    WAIT_ROM:state<=EVAL;
    EVAL:if(rom_q==0)begin
     if(message_kind==3)reply(ENABLE_SENSOR?864:816);
     else if(message_kind==1)begin
      if(snapshot_count==0)reply(672);
      else begin snapshot_address<=0;log_row<=0;state<=LOG_READ;end
     end else if(message_kind==2)begin
      if(log_row+1>=snapshot_count)reply(672);
      else begin log_row<=log_row+1'b1;snapshot_address<=snapshot_address+1'b1;state<=LOG_READ;end
     end else state<=IDLE;
    end else if(rom_q[7])begin hex_shift<=token_value;hex_left<=token_digits;state<=HEX;end
    else begin out_byte<=rom_q;state<=SEND;end
    SEND:if(tx_ready)begin message_index<=message_index+1'b1;state<=FETCH;end
    HEX:if(tx_ready)begin hex_shift<=hex_shift<<4;if(hex_left==1)begin message_index<=message_index+1'b1;state<=FETCH;end else hex_left<=hex_left-1'b1;end
    LOG_WAIT:if(snapshot_ready)begin reply(576);message_kind<=1;end
    LOG_READ:state<=LOG_DELAY;
    LOG_DELAY:state<=LOG_TAKE;
    LOG_TAKE:begin log_record<=snapshot_data;reply(608);message_kind<=2;end
    ACTION:if(ENABLE_SENSOR&&sensor_alarm&&action_type!=2)begin action_valid<=0;error_reply(928,8'd10);end
      else if(control_blocked)begin action_valid<=0;error_reply(480,8'd8);end
      else if(!online)begin action_valid<=0;error_reply(320,8'd4);end
      else if(action_type==2&&!actual[0])begin action_valid<=0;error_reply(352,8'd5);end
      else if(control_ready)begin
       action_valid<=0;status_snapshot<=live_snapshot;
       status_snapshot[183:181]<=action_type==0?{action_value,1'b1}:3'd0;
       status_snapshot[185:184]<=action_value;reply(action_type==2?192:160);
      end
   endcase
   if(rx_error)begin
    if(rx_errors!=16'hffff)rx_errors<=rx_errors+1'b1;
    bad_line<=1;line_buffer<=0;line_length<=0;saw_cr<=0;last_byte_at<=milliseconds;
    if(state==IDLE)error_reply(448,8'd7);else busy_reply<=1;
   end else if(rx_valid)begin
    last_byte_at<=milliseconds;
    if(rx_data==10)begin
     line_buffer<=0;line_length<=0;bad_line<=0;saw_cr<=0;
     if(state!=IDLE)begin if(line_length!=0||bad_line)busy_reply<=1;end
     else if(bad_line)error_reply(384,8'd1);
     else if(line_length!=0)begin
      status_snapshot<=live_snapshot;
      case(line_buffer)
       "PING":reply(544);
       "HELP":reply(704);
       "STATUS?","GET STATUS":reply(0);
       "DEMO FIRE":request_action(0,0);
       "DEMO QUAKE":request_action(0,1);
       "DEMO LAB":request_action(0,2);
       "DEMO DRILL":request_action(0,3);
       "DEMO STOP","NORMAL":request_action(1,0);
       "LOG CLEAR":begin log_clear<=1;reply(832);end
       "TEMP?","GET TEMP":if(ENABLE_SENSOR)reply(0);else error_reply(512,8'd9);
       "TEMP CLEAR":if(!ENABLE_SENSOR)error_reply(512,8'd9);
        else if(sensor_alarm&&!sensor_clear_allowed)error_reply(960,8'd11);
        else begin sensor_clear<=1;reply(992);end
       default:if(line_length==13&&line_buffer[103:8]=="BARRIER SET "&&line_buffer[7:0]>=48&&line_buffer[7:0]<=51)request_action(2,line_buffer[1:0]);
        else if(valid_count)begin
         if(parsed_count==0||parsed_count>64)error_reply(256,8'd2);
         else begin log_requested<=parsed_count;snapshot_start<=1;state<=LOG_WAIT;end
        end else error_reply(224,8'd0);
      endcase
     end
    end else if(rx_data==13)saw_cr<=1;
    else if(saw_cr||rx_data<32||rx_data>126||line_length==16)bad_line<=1;
    else begin line_buffer<={line_buffer[119:0],rx_data};line_length<=line_length+1'b1;end
   end else if((line_length!=0||bad_line||saw_cr)&&milliseconds-last_byte_at>=1000)begin
    line_buffer<=0;line_length<=0;bad_line<=0;saw_cr<=0;
    if(state==IDLE)error_reply(416,8'd6);else busy_reply<=1;
   end
  end
endmodule
