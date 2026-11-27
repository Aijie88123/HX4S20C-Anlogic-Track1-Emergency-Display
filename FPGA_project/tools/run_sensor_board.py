from pathlib import Path
import hashlib,json,subprocess,shutil
R=Path(__file__).resolve().parents[1];E=R/'evidence/ds18b20_console_20261029/wire_board';E.mkdir(parents=True,exist_ok=True);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
model=E/'ds18b20_model.sv';shutil.copy2(R/'evidence/ds18b20_console_20261029/standalone_module/tests/ds18b20_model.sv',model)
files=[R/'B_control/rtl'/n for n in ['dual_board_control_top.v','key_remove_shakes.v','audio_fft.v','maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v','ds18b20_emergency.v','ds18b20_master.v','onewire_slot.v','temperature_alarm.v']]+[R/'common'/n for n in ['distributed_map.v','distributed_audio.v','ethernet_mailbox.v','particle_transition.v','audio_dft12.v']]+[R/'tests/period_button_link_models.v',model,R/'tests/tb_sensor_board.sv']+[Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram.v','eg_phy_glbl.v']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();bound=files+[Path(__file__)];h={str(p):sha(p) for p in bound};logs=[]
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(a).replace(chr(92),'/') for a in args]],cwd=E,capture_output=True,timeout=1800)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-8000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_sensor_board','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
assert h=={str(p):sha(p) for p in bound}
lines=[v for v in (E/'wire.txt').read_text().splitlines() if v.strip()];marks={tag:int(n) for tag,n in (row.split() for row in (E/'marks.txt').read_text().splitlines())};cases={}
for tag,n in marks.items():
 f=dict(v.split('=',1) for v in lines[n].split());assert f['SENSOR']=='DS18B20';raw=int(f['TRAW'],16);raw=raw-65536 if raw>=32768 else raw
 cases[tag]=dict(raw=raw,valid=int(f['TV'],16),warning=int(f['TW'],16),alarm=int(f['TA'],16),clear=int(f['TC'],16),fault=int(f['TF'],16),source=int(f['SRC'],16),line=lines[n])
assert cases['NORMAL']['raw']==401 and cases['NORMAL']['valid']==1
assert cases['NEGATIVE']['raw']==-162 and cases['NEGATIVE']['valid']==1
assert cases['CRC']['valid']==0 and cases['CRC']['fault']==3
assert cases['WARNING']['warning']==1 and cases['WARNING']['alarm']==0
assert cases['SENSOR_FIRE']['source']==2 and cases['SENSOR_FIRE']['alarm']==1
assert cases['DISCONNECTED_LOCKED']['alarm']==1 and cases['DISCONNECTED_LOCKED']['valid']==0
assert cases['CLEAR_ALLOWED']['clear']==1 and cases['STOPPED']['alarm']==0
assert any('TYPE=13' in s for s in lines) and any('TYPE=70' in s for s in lines)
inputs={str(p):sha(p) for p in [E/'wire.txt',E/'marks.txt']}
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,generated_hashes=inputs,cases=cases,observations=[v for v in s.splitlines() if 'PASS:' in v],physical_test=False,scope='Actual default-enabled B top, real DS18B20 RTL with1MHz clock parameter and true760ms protocol wait, independent time/event-driven DQ device and real UART100k8N1. PLL/peer telemetry modeled, no A HDMI/media memory. Separate25MHz module qualification and nativeMAC/actual A chain bound independently.'),ensure_ascii=False,indent=2),encoding='utf-8');print('\n'.join(v for v in s.splitlines() if 'PASS:' in v),flush=True)
