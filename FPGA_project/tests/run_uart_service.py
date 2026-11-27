from pathlib import Path
import subprocess,json,hashlib,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_service_20261026/unit';E.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'B_control/rtl'/n for n in ['maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v']]+[R/'tests/tb_uart_service.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=E,capture_output=True,timeout=600)
 text=(p.stdout+p.stderr).decode(errors='replace');logs.append(text);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in text and '** Fatal' not in text,text[-5000:];return text
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_uart_service','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in log
lines=[s for s in (E/'wire.txt').read_text().splitlines() if s];states={};rows=0
for mark in (E/'marks.txt').read_text().splitlines():
 p=mark.split()
 if p[0]=='LOGROW':
  raw=int(p[2],16);expected=f'MS=0x{raw>>32:08X} TYPE={(raw>>24)&255:02X} CTX={(raw>>16)&255:02X} DATA={raw&65535:04X}'
  assert lines[int(p[1])]==expected,(p,lines[int(p[1])],expected);rows+=1
 else:states[p[0]]=dict(re.findall(r'(\w+)=([^ ]+)',lines[int(p[1])]))
assert states['OFFLINE']['LINK']=='0'
assert states['REQUEST_ONLY']['REQ']=='1' and states['REQUEST_ONLY']['ACT']=='0' and states['REQUEST_ONLY']['ACK']=='0'
assert states['ACTIVE_FIRE']['EXIT']=='1' and states['ACTIVE_FIRE']['CLOSED']=='0080' and states['ACTIVE_FIRE']['APPLY']=='1'
assert states['BARRIER_PENDING']['BAR']=='2' and states['BARRIER_PENDING']['APPLY']=='0'
assert states['BARRIER_APPLIED']['CLOSED']=='C080' and states['BARRIER_APPLIED']['APPLY']=='1'
assert states['NO_ROUTE']['EXIT']=='0' and states['NO_ROUTE']['CLOSED']=='F080'
assert states['CLEARED']['LOG']=='00'
assert states['STALE']['FRESH']=='0' and states['STALE']['EXIT']=='0'
assert states['NORMAL']['REQ']==states['NORMAL']['ACT']=='0' and rows==64
inputs=files+[Path(__file__),E/'wire.txt',E/'marks.txt']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},status_checks=states,exact_snapshot_rows=rows,observations=[l for l in log.splitlines() if 'PASS:' in l],physical_test=False),indent=2));print('PASS UART service:',len(lines),'wire response lines,64snapshot rows and state/error checks.')
