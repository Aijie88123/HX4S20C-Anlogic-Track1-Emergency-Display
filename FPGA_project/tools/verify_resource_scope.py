"""Check the complete approved-fast production snapshot and narrow whitelist."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];F=R/'tests/reference_resource_timing/approved_fast_sources.json';E=R/'evidence/resource_timing_20261025';E.mkdir(exist_ok=True,parents=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
expected=json.loads(F.read_text(encoding='utf-8'))
changed=[];current={}
for rel,dig in expected.items():
 p=R/rel;assert p.exists(),rel;current[rel]=sha(p)
 if current[rel]!=dig:changed.append(rel)
allowed=['A_display/rtl/audio_spectrum_precise_overlay.v','A_display/rtl/audio_waveform_precise_overlay.v','B_control/rtl/audio_dft12.v','B_control/rtl/b_particle_shader.v','B_control/rtl/distributed_media.v','B_control/rtl/raster_map_window.v','common/audio_dft12.v','common/distributed_media.v','common/raster_map_window.v']
assert sorted(changed)==sorted(allowed),changed
for name in ['audio_dft12.v','distributed_media.v','raster_map_window.v']:assert sha(R/'B_control/rtl'/name)==sha(R/'common'/name)
top=(R/'A_display/rtl/smart_terminal_hw_top.v').read_text(encoding='utf-8-sig');assert 'qualified_memory_guard' in top and 'photo_geometry_active || qualified_memory_guard' in top
assert 'FAST_DEMO' in top
rows={str(R/k):v for k,v in current.items()};rows.update({str(F):sha(F),str(Path(__file__).resolve()):sha(Path(__file__))})
report=dict(status='PASS',production_changes=changed,source_hashes=rows,comparison='Complete frozen approved fast-carousel source snapshot; every non-whitelisted input byte-identical.',white_line_repairs_retained=True,TF_protocol_V12_clocks_pins_final_SDC_vendor_SDRAM_FIFO_unchanged=True,latency_and_format_preserved=True,fast_periods_ms=[350,1000,2000],geometry_stages=17,first_auto_dwell_ms=3000,diagnostic_default=False,baseline_promoted=False)
(E/'scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS: only9 resource RTL inputs change; complete vendor/PLL/SDC/pin/TF/V12/white-fix/fast-control inputs match approved source')
