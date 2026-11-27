from pathlib import Path
import subprocess,json,hashlib,zlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/map_detail_20261020/wire';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'common/ethernet_raster_burst.v',T/'tb_raster_burst_wire.v']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_raster_burst_wire','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
lines=(T/'burst_wire_nibbles.hex').read_text().splitlines();good=bad=0;hist={}
for line in lines:
 raw=bytes(int(line[k+1]+line[k],16) for k in range(0,len(line),2));assert raw[:8]==b'\x55'*7+b'\xd5'
 body=raw[8:];assert len(body)>=64 and body[16]==12
 crc=int.from_bytes(body[-4:],'little')==zlib.crc32(body[:-4])
 if not crc:bad+=1;continue
 good+=1
 if body[23]==16:
  n=body[24];assert 1<=n<=4 and len(body)==max(60,25+n*28)+4
  hist[n]=hist.get(n,0)+1
assert good>20 and bad==1 and hist.get(4,0)>10,(good,bad,hist)
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
result={'status':'PASS','source_hashes':hashes,'observations':[v for v in s.splitlines() if 'PASS:' in v], 'independent_zlib_FCS':True,'batch_histogram':hist,'bad_FCS_rejected':bad}
(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
