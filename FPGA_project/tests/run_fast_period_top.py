from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/fast_carousel_20261025/period_top';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
files=[R/'B_control/rtl/dual_board_control_top.v',R/'B_control/rtl/key_remove_shakes.v',R/'B_control/rtl/audio_fft.v',*[R/'common'/n for n in ['distributed_map.v','distributed_audio.v','ethernet_mailbox.v','particle_transition.v','audio_dft12.v']],R/'tests/period_button_link_models.v',R/'tests/tb_period_button_top.v']
files += [R/'B_control/rtl'/n for n in ['maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v']]+[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
bound=files+[Path(__file__).resolve()];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in bound}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'fast_period_top',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','fast_period_top.tb_period_button_top','fast_period_top.glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;assert h=={str(p):sha(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual production B top default FAST_DEMO parameters350/1000/2000/startup3000 asserted, real S2 debounce/release/long-press and emergency command/closure gates. Elapsed-time divider scaled; PLL and peer telemetry modeled. Exact pacing/full17 effects and labels separately covered by fast control test.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
