from pathlib import Path
import subprocess, hashlib, json
R = Path(__file__).resolve().parents[1]
O = R / 'evidence/audio_visual_seamless_20261022/handoff'
O.mkdir(parents=True, exist_ok=True)
M = Path('D:/modelsim/win64'); W = O / 'work'; I = O / 'modelsim.ini'
I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
names = ['smart_terminal_hw_top.v','alpha_blend.v','audio_bars_overlay.v',
 'audio_envelope.v','audio_fft.v','audio_spectrum_overlay.v',
 'audio_spectrum_precise_overlay.v','audio_waveform_precise_overlay.v',
 'audio_label_font_fast.v','chinese_title_overlay.v','chinese_title_rom.v',
 'text_overlay_8x8.v','transition_fx.v','video_palette_lookup.v',
 'smart_terminal_overlay.v','smart_terminal_overlay_pipelined.v','video_scanout_720p.v']
files = [R/'A_display/rtl'/n for n in names] + [
 R/'A_display/vendor/user_source/hdl_source/video_rgb_to_axis_720p.v',
 R/'tests/tb_startup_seamless.v', R/'tests/tb_startup_handoff_controls.v']
bound = files + [Path(__file__).resolve()]
def hashes(): return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
before = hashes(); logs=[]
def run(tool,args):
 if tool != 'vlib': args=['-modelsimini', I.as_posix(), *args]
 p=subprocess.run([str(M/(tool+'.exe')),*map(str,args)],cwd=O,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace'); logs.append(s)
 (O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s: raise RuntimeError(s[-6500:])
 return s
if not W.exists(): run('vlib',[W.as_posix()])
run('vmap',['startup_seamless',W.as_posix()])
run('vlog',['-sv','-timescale','1ns/1ps','-work',W.as_posix(),*[p.as_posix() for p in files]])
observations=[]
for top in ['tb_startup_handoff_controls','tb_startup_seamless']:
 s=run('vsim',['-c','startup_seamless.'+top,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s
 observations += [v for v in s.splitlines() if 'PASS:' in v]
assert hashes()==before
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=before,
 observations=observations,scope='Production720p scanout/compositor/converter/qualification with behavioral SDRAM and injected ready/lock; physical HDMI sink not modeled'),indent=2),encoding='utf-8')
print('\n'.join(observations),flush=True)
