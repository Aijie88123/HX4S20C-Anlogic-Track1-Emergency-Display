"""Verify UART-only production changes against immutable best follow_view."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_service_20261026';P=Path('D:/HX4S20C_follow_view_20261025')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
manifest=read(E/'parent-inputs.json')['files'];modified=['B_control/rtl/dual_board_control_top.v','B_control/constraints/pin.adc','B_control/constraints/timing.sdc','B_control/project/smart_terminal_720p.prj'];added=['B_control/rtl/'+n for n in ['maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v']]
changed=[];inputs={}
for rel,h in manifest.items():
 assert sha(P/rel)==h,'parent modified: '+rel
 assert (R/rel).exists(),rel
 if sha(R/rel)!=h:changed.append(rel)
 inputs[str(R/rel)]=sha(R/rel)
assert sorted(changed)==sorted(modified),changed
for board in ['A_display','B_control']:
 for sub in ['rtl','ip','vendor','constraints','project']:
  for p in (R/board/sub).rglob('*'):
   if p.is_file() and 'smart_terminal_Runs' not in p.parts:
    rel=p.relative_to(R).as_posix()
    if rel not in manifest:assert rel in added,rel
for sub in ['common','assets/indoor_map']:
 for p in (P/sub).rglob('*'):
  if p.is_file():
   rel=p.relative_to(P);assert sha(R/rel)==sha(p),str(rel);inputs[str(R/rel)]=sha(R/rel)
for ext in ['bit','bin']:
 rel='firmware/A_display_3V3.'+ext;assert sha(R/rel)==sha(P/rel);inputs[str(R/rel)]=sha(R/rel)
for rel in modified[1:3]:assert (R/rel).read_bytes().startswith((P/rel).read_bytes()),rel
s=(R/modified[0]).read_text();original=(P/modified[0]).read_text()
s=s.replace(',UART_BAUD=115200','').replace(' input uart_rx,output uart_tx,\n','')
a=s.index(' wire uart_action_valid');b=s.index(' reg command_armed',a);s=s[:a]+s[b:]
block=''' always @(posedge net_clk or posedge rst)
  if(rst)command_origin_uart<=0;
  else if(uart_key_priority)command_origin_uart<=0;
  else if(uart_action_valid&&uart_action_ready)command_origin_uart<=1;
''';assert block in s;s=s.replace(block,'')
a=s.index(' else if(uart_action_valid&&uart_action_ready&&uart_action_type!=2)');b=s.index(' wire [20:0] peer;',a);s=s[:a]+s[b:]
s=s.replace("  else if(uart_action_valid&&uart_action_ready)barrier_mode<=uart_action_type==2?uart_action_value:2'd0;\n",'')
a=s.index(' wire [7:0] uart_cached;');b=s.index(' wire stream_valid,stream_ready,spectrum_valid,map_valid;',a);s=s[:a]+s[b:]
s=s.replace('  assign uart_cached=available;assign uart_source_fault=fault;\n','').replace("  assign uart_cached=0;assign uart_source_fault=4'hf;\n",'')
s=s.replace(' ethernet_command_link #(.BOARD_B(1)', ' wire [2:0] desired={event_type,emergency};\n ethernet_command_link #(.BOARD_B(1)')
marker='  .stream_valid(stream_valid),.stream_data(outgoing_stream),.stream_ready(stream_ready),.peer_stream(incoming_stream));\n';assert marker in s
s=s.replace(marker,marker+' wire acknowledged=online && peer[19] && peer[18:11]==command_sequence && peer[2:0]==desired;\n')
normalize=lambda t:'\n'.join(l for l in t.splitlines() if l.strip())
assert normalize(s)==normalize(original),'non-UART top logic differs'
for rel in added:inputs[str(R/rel)]=sha(R/rel)
inputs[str(Path(__file__))]=sha(Path(__file__));inputs[str(E/'parent-inputs.json')]=sha(E/'parent-inputs.json')
(E/'scope.json').write_text(json.dumps(dict(status='PASS',parent=str(P),production_changes=modified,production_additions=added,mechanically_restored_top_equals_parent_ignoring_blank_lines=True,A_unchanged=True,original_constraints_retained_as_exact_byte_prefix=True,source_hashes=inputs,not_merged='map_flow_20261026',baseline_promoted=False),indent=2));print('PASS: UART-only scope; A/map/art/route/SDRAM/audio/V12 unchanged; original constraints exact byte prefix')
