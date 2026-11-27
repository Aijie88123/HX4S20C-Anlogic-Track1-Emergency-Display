"""Verify selected real native outputs without inventing All stage markers."""
from pathlib import Path
import json,hashlib,re,sys
R=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
for board in (sys.argv[1:] or ['A_display','B_control']):
 E=R/board/'evidence/map_detail_20261020';m=read(E/'build-manifest.json');proof=read(E/'native-route-proof.json')
 assert proof['status']=='PASS' and proof['build_manifest_sha256']==sha(E/'build-manifest.json')
 assert proof['source_manifest_sha256']==sha(E/'synthesis-source.json')
 assert m['sources']==read(E/'synthesis-source.json')
 for row in m['sources']:assert sha(R/board/row['path'])==row['sha256'].upper(),(board,row['path'])
 runtime=R/board/'project/smart_terminal_Runs/phy_1'
 for ext in ['bit','bin']:
  output=R/board/'output'/('smart_terminal.'+ext);packed=R/'firmware'/(board+'_3V3.'+ext)
  selected=output if output.exists() else packed
  assert sha(selected)==m[ext+'Sha256'].upper()
  if proof.get('runtime_output_selected',True) and (runtime/('smart_terminal.'+ext)).exists():assert sha(runtime/('smart_terminal.'+ext))==m[ext+'Sha256'].upper()
  if ext=='bit':assert b'# Version: Release_2026.1_SP2' in selected.read_bytes()[:1024]
 timing=(E/'smart_terminal_phy.ts').read_text();assert timing.replace('\r\n','\n')==m['timing'].replace('\r\n','\n')
 assert not re.search(r'[SH]WNS:\s*-',timing) and 'STNS: 0.000ns' in timing and 'HTNS: 0.000ns' in timing
 drc=(E/'smart_terminal_route_drc.rpt').read_text()
 for c in ['Lut Bridge','Multi Drive','Clock Status','Abnormal Path']:assert re.search(r'End Stage \d+ \| Run '+c+r' Checker',drc)
 assert not re.search('ERROR|CRITICAL-WARNING',drc)
 assert proof['phy_log_sha256']==sha(E/'phy_1-build.log')
 log=(E/'phy_1-build.log').read_text(encoding='utf-8',errors='replace')
 assert 'finish command "bitgen' in log and 'finish command "route' in log and 'finish command "fix_hold' in log
 if proof['mode']=='manual_native':
  p=read(E/'selected-manual-physical.json');t=(E/'selected-native-executed.tcl').read_text()
  inputs=read(E/'selected-native-input-proof.json')
  if inputs.get('physical_mode')=='same_place_reroute':
   previous=read(E/'selected-native-predecessor-input.json')
   assert sha(E/'selected-native-predecessor-input.json')==inputs['predecessor_input_proof_sha256'] and sha(E/'selected-native-predecessor.log')==inputs['predecessor_log_sha256']
   assert previous['gate_db_sha256']==inputs['gate_db_sha256'] and previous['source_manifest_sha256']==inputs['source_manifest_sha256']
   assert 'place -eco' in t
  if 'placement_guide_sha256' in inputs:assert inputs['placement_guide_sha256']==sha(R/board/'project/parameter_initial_placement.adc') and 'clear_inst_adc' in t and 'parameter_initial_placement.adc' in t
  if 'auxiliary_placement_guide_sha256' in inputs:assert inputs['auxiliary_placement_guide_sha256']==sha(E/'selected-native-video-init.adc') and inputs['auxiliary_placement_guide_path'] in t
  assert p['gate_db_sha256']==inputs['gate_db_sha256']
  if (runtime/'smart_terminal_gate.db').exists():assert p['gate_db_sha256']==sha(runtime/'smart_terminal_gate.db')
  assert p['executed_script_sha256']==sha(E/'selected-native-executed.tcl')
  assert p['original_sdc_sha256']==sha(R/board/'constraints/timing.sdc')
  assert t.index('clear_sdc -user')<t.index('read_sdc')<t.index('update_timing -mode final')<t.index('bitgen ')
 print(board+' PASS: current sources/selected native bit+bin/original-SDC setup+hold/all4DRC evidence; '+timing.strip().replace('\n',' '))
 if not runtime.exists():print('Archive verification only: runtime databases were omitted; no new compilation/routing is claimed.')
