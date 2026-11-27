from pathlib import Path
import zlib,hashlib,subprocess,json
from datetime import datetime,timezone
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/zoom_routing_20261012/wire_flags';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work'
payload=3|(0x10<<8)|(123<<16)|(400000<<32)|(350000<<56)|(2458<<80)|(0x8010<<92)|(0x8010<<108)|(0x80<<124)|(464<<140)|(480<<152)|(384<<164)|(534<<176)
base=bytearray(60);base[:17]=bytes.fromhex('ffffffffffff0248583400b188b5485804');base[17:23]=bytes([1,3,2,1,1,0x22]);base[23:51]=payload.to_bytes(28,'little')
def frame(body):return bytes.fromhex('55555555555555d5')+body+zlib.crc32(body).to_bytes(4,'little')
def nib(f):return [n for b in f for n in [b&15,b>>4]]
rows=[]
def add(body,accept=True):rows.append((nib(frame(body)),accept,int.from_bytes(body[23:51],'little')))
add(base);b=base.copy();b[24]=0x22;add(b)
for pos,value in [(16,3),(11,0xa1),(12,0x89),(23,1),(24,0x30),(24,0x40),(22,0x80)]:
 b=base.copy();b[pos]=value;add(b,False)
f=bytearray(frame(base));f[-1]^=1;rows.append((nib(f),False,payload))
rows+=[(nib(frame(base))[:-2],False,payload),(nib(frame(base)+b'\x00'),False,payload),(nib(frame(base))[:-1],False,payload),(nib(frame(base)),False,payload)]
b=base.copy();b[23:51]=bytes(28);add(b)
b=base.copy();b[23]=2;b[24]=1;add(b)
for pos,value in [(59,1),(0,0),(23,4)]:b=base.copy();b[pos]=value;add(b,False)
b=base.copy();b[24]|=1;add(b)
assert len(rows)==20 and sum(x[1] for x in rows)==5
(T/'map_wire_nibbles.hex').write_text('\n'.join(f'{v:x}' for ns,_,_ in rows for v in ns)+'\n')
for name,data,width in [('lengths',[len(ns) for ns,_,_ in rows],4),('accept',[int(a) for _,a,_ in rows],2),('payload',[p for _,_,p in rows],56)]:
 (T/f'map_wire_{name}.hex').write_text('\n'.join(f'{v:0{width}x}' for v in data)+'\n')
sources=[R/'common/ethernet_frame_rx.v',R/'common/distributed_map.v',R/'common/ethernet_mailbox.v',T/'tb_map_wire_flags.v',Path(__file__)]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in sources}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*args],cwd=T,capture_output=True,timeout=180);log=(p.stdout+p.stderr).decode(errors='replace')
 if p.returncode or '** Error' in log or '** Fatal' in log:raise RuntimeError(log)
 return log
if not W.exists():run('vlib',[str(W)])
(O/'compile.log').write_text(run('vlog',['-sv','-work',str(W),*map(str,sources[:-1])]))
obs=[]
for top in ['tb_map_wire_flags','tb_map_button']:
 log=run('vsim',['-c','-novopt','-t','1ps','-lib',str(W),top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);(O/(top+'.log')).write_text(log)
 assert 'PASS:' in log;obs += [l for l in log.splitlines() if 'PASS:' in l]
(O/'result.json').write_text(json.dumps({'status':'PASS','observations':obs,'compiled_sources':hashes,'completed_utc':datetime.now(timezone.utc).isoformat()},indent=2))
print('\n'.join(obs))
