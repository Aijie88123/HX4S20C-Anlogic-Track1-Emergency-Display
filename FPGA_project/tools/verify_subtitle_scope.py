"""Check subtitle-only scope using recorded immutable parent inputs."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_20261026'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((E/'parent-inputs.json').read_text())['files']
modified=['A_display/rtl/ethernet_command_link.v', 'A_display/rtl/ethernet_frame_rx.v', 'A_display/rtl/smart_terminal_hw_top.v', 'A_display/rtl/smart_terminal_overlay_pipelined.v', 'A_display/rtl/text_overlay_8x8.v', 'A_display/project/smart_terminal_720p.prj', 'B_control/rtl/b_uart_service.v', 'B_control/rtl/dual_board_control_top.v', 'B_control/rtl/ethernet_command_link.v', 'B_control/rtl/ethernet_frame_rx.v', 'B_control/project/smart_terminal_720p.prj', 'common/ethernet_command_link.v', 'common/ethernet_frame_rx.v', 'A_display/project/phy_settings.cfg', 'A_display/project/DefaultFlow.tcl']
added=['A_display/rtl/subtitle_display.v','B_control/rtl/uart_subtitle_bridge.v']
changed=[];inputs={}
for rel,h in manifest.items():
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
 for n in ['ethernet_command_link.v','ethernet_frame_rx.v']:assert (R/board/'rtl'/n).read_bytes()==(R/'common'/n).read_bytes()
 for f in (R/board/'constraints').rglob('*'):
  if f.is_file():assert sha(f)==manifest[f.relative_to(R).as_posix()]
flow=(R/'A_display/project/DefaultFlow.tcl').read_text()
assert flow.index('set_clock_uncertainty -setup 0.500')<flow.index('  place\n')
assert flow.index('clear_sdc -user')<flow.index('read_sdc ../../../constraints/timing.sdc')<flow.index('update_timing -mode final')
for rel in added:inputs[str(R/rel)]=sha(R/rel)
ref=R/'tests/subtitle_parent_text.v'
assert hashlib.sha256(ref.read_text().replace('module subtitle_parent_text #','module text_overlay_8x8 #').encode()).hexdigest()=='e5dd9aa0f98c028fc59159664ee2660c6d94b23fff04f12a282b396f975d581b'
inputs[str(ref)]=sha(ref)
for p in [Path(__file__),E/'parent-inputs.json',E/'production-diff.patch']:inputs[str(p)]=sha(p)
(E/'scope.json').write_text(json.dumps(dict(status='PASS',parent='uart_service_20261026',best='follow_view_20261025',production_changes=modified,production_additions=added,all_other_recorded_inputs_identical=True,all_constraints_identical=True,map_assets_and_geometry_identical=True,common_mirrors_identical=True,baseline_promoted=False,map_flow_merged=False,source_hashes=inputs),indent=2));print('PASS: subtitle scope, exact unchanged constraints/map/assets/other production inputs and common mirrors')
