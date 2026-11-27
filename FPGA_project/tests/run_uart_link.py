from pathlib import Path
import subprocess,hashlib,json,re,zlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_service_20261026/link';E.mkdir(parents=True,exist_ok=True)
s=(R/'tests/tb_endpoints.v').read_text();s=s[:s.index('module tb_endpoints')].replace("wire gsrn=1'b1;","wire gsrn=1'b1;wire done_gwe=1'b1;");(E/'phy.v').write_text(s)
files=[*sorted((R/'common').glob('*.v')),*[R/'B_control/rtl'/n for n in ['dual_board_control_top.v','key_remove_shakes.v','audio_fft.v','maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v','uart_subtitle_bridge.v']],R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/rtl/a_map_route_worker.v',R/'tests/tb_uart_link.v',E/'phy.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_logic_io.v','eg_phy_bram.v']]
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in args]],cwd=E,capture_output=True,timeout=1200);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-6500:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_uart_link','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in log
lines=[s for s in (E/'wire.txt').read_text().splitlines() if s];states={}
for mark in (E/'marks.txt').read_text().splitlines():
 name,i=mark.split();states[name]=dict(re.findall(r'(\w+)=([^ ]+)',lines[int(i)]))
for name,state,closed in [('FIRE','1','0080'),('QUAKE','3','0001'),('LAB','5','0400'),('DRILL','7','0020'),('RECONNECTED','5','0400')]:
 d=states[name];assert d['REQ']==d['ACT']==state and d['ACK']==d['APPLY']==d['FRESH']=='1' and d['CLOSED']==closed,(name,d)
assert states['BARRIER2']['CLOSED']=='C080' and states['BARRIER2']['APPLY']=='1'
assert states['NO_ROUTE']['EXIT']=='0' and states['NO_ROUTE']['CLOSED']=='F080'
assert states['STOP']['ACT']=='0' and states['LOCAL_RETAINED']['ACT']=='1' and states['LOCAL_RETAINED']['REQ']==states['LOCAL_RETAINED']['ACK']=='0'
assert states['OFFLINE']['LINK']==states['OFFLINE']['FRESH']=='0'
frames=[]
for nibbles in (E/'mac.hex').read_text().splitlines():
 if not nibbles:continue
 raw=bytes(int(nibbles[i+1]+nibbles[i],16) for i in range(0,len(nibbles),2))
 assert raw[:8]==b'\x55'*7+b'\xd5'
 frame=raw[8:];assert zlib.crc32(frame[:-4])==int.from_bytes(frame[-4:],'little')
 assert frame[16]==12 and frame[11]==0xb1
 frames.append(frame.hex())
assert len(frames)==3
inputs=files+[Path(__file__),R/'tests/tb_endpoints.v',E/'wire.txt',E/'marks.txt',E/'mac.hex']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},states=states,independently_checked_V12_MAC_FCS_frames=frames,observations=[s for s in log.splitlines() if 'PASS:' in s],scope='Actual B control top with media disabled; actual native MAC/PHY and original A CDC/emergency controller and map/camera solver. UART baud1M and heartbeat/PHY boot counters accelerated only in test. Production115200 validated separately. Does not prove pixel display or physical CH340.',physical_test=False),indent=2));print('PASS: UART/nativeMAC/A-control-route/B-status integration',len(states),'snapshots')
