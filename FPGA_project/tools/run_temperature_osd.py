from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_large_20261031/simulation';E.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=E/'work'
parent=(R/'evidence/temperature_osd_20261030/parent_changed_inputs/A_display/rtl/text_overlay_8x8.v').read_text(encoding='utf-8-sig')
(E/'parent_text.v').write_text(parent.replace('text_overlay_8x8','temperature_parent_text').replace('subtitle_shared_font_rom','temperature_parent_font'),encoding='utf-8')
parent_wave=(R/'evidence/temperature_osd_20261030/parent_changed_inputs/A_display/rtl/audio_waveform_precise_overlay.v').read_text(encoding='utf-8-sig')
(E/'parent_wave.v').write_text(parent_wave.replace('module audio_waveform_precise_overlay','module temperature_parent_wave'),encoding='utf-8')
files=[R/'B_control/rtl/dual_board_control_top.v',R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/rtl/a_map_route_worker.v',R/'common/distributed_map.v',R/'common/ethernet_mailbox.v',R/'A_display/rtl/text_overlay_8x8.v',E/'parent_text.v',R/'tests/tb_temperature_osd.sv']
files += [R/'tests/tb_temperature_status_pipeline.sv',R/'tests/tb_temperature_emergency_font.sv']
files += [R/'A_display/rtl/audio_waveform_precise_overlay.v',E/'parent_wave.v',R/'tests/tb_temperature_wave_equivalence.sv']
files += [R/'evidence/temperature_osd_20261030/compositor_reference.v',R/'tests/tb_temperature_compositor.sv',R/'tests/tb_temperature_font_bits.sv']
files += [R/'evidence/temperature_osd_20261030/status_reference.v',R/'tests/tb_temperature_status_dynamic.sv']
files += [R/'tests/tb_temperature_integer_lookup.sv']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram32k.v','eg_phy_glbl.v']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
bound=files+[Path(__file__).resolve()];hashes={str(p):sha(p) for p in bound};logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[str(a).replace('\\','/') for a in args]],cwd=E,capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-8500:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_osd','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
assert 'PASS:' in s
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_status_pipeline','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_emergency_font','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_wave_equivalence','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_compositor','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_font_bits','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_status_dynamic','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
s+=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_integer_lookup','glbl','-do','onerror {quit -code 1};run -all;quit -code 0'])
assert hashes=={str(p):sha(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=hashes,observations=obs,physical_test=False,scope='Actual B held sender, A controls/temperature receiver, asynchronous held-bus mailbox and native font text compositor. All representable -55..125C raw values and independent prior-font pixel oracle. No MAC/complete HDMI in this test; covered separately.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
from PIL import Image
for source in E.glob('*_pixels.txt'):
 rows=[v.split() for v in source.read_text().splitlines()];assert len(rows)==320*76
 im=Image.new('RGB',(320,76));pixels=[]
 for rgb,a in rows:
  c=int(rgb,16);a=int(a,16);base=(11,30,48)
  pixels.append(tuple((((c>>shift)&255)*a+b*(255-a))//255 for shift,b in zip([16,8,0],base)))
 im.putdata(pixels);im.resize((640,152),Image.Resampling.NEAREST).save(source.with_suffix('.png'))
