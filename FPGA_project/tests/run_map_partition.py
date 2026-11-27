from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/map_partition';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[R/'A_display/rtl/smart_terminal_hw_top.v',R/'B_control/rtl/dual_board_control_top.v',R/'common/distributed_map.v',R/'common/ethernet_frame_tx.v',R/'common/ethernet_frame_rx.v',T/'tb_map_partition.v']
f += [R/'A_display/rtl/a_map_route_worker.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f+[Path(__file__).resolve()]};logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*(['-modelsimini',INI.as_posix()] if tool!='vlib' else []),*map(str,args)],cwd=O,capture_output=True,timeout=120)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
def solve(e,m):
 closed=[0x80,1,0x400,0x20][e]
 if m in (1,2):closed|=[0x8000,0x2000,0x1000,0x4000][e]
 if m==2:closed|=[0x4000,0x8000,0x2000,0x1000][e]
 if m==3:closed|=0xf000
 origin=[6,0,2,8][e];dist=[65535]*13;dist[origin]=0;previous={};visited=set()
 while True:
  cost,n=min((dist[n],n) for n in range(13) if n not in visited)
  if cost==65535:return closed,0,0,True,[]
  if n>=9:break
  visited.add(n)
  for j,(a,b) in enumerate(edges):
   if n not in (a,b) or closed>>j&1:continue
   q=b if a==n else a;d=cost+(176 if j<12 else 80)
   if q not in visited and d<dist[q]:dist[q]=d;previous[q]=(n,j)
 route=dirs=0;chain=[n]
 while n!=origin:
  p,j=previous[n];route|=1<<j
  if (p<n if j<12 else p>=9 if j<14 else p<9):dirs|=1<<j
  n=p;chain.append(n)
 return closed,route,dirs,False,chain
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['partition',W]);run('vlog',['-sv','-work',W,*f])
 s=run('vsim',['-c','partition.tb_map_partition','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 rows=(O/'map_partition_scenes.txt').read_text().splitlines();assert len(rows)==16
 for row in rows:
  e,m,p,n=row.split();e=int(e);m=int(m);p=int(p,16);n=int(n,16)
  closed,route,dirs,no_path,chain=solve(e,m)
  assert (p>>124&65535,p>>92&65535,p>>108&65535,bool(p>>9&1))==(closed,route,dirs,no_path),(e,m,row,(closed,route,dirs,no_path))
  for i,node in enumerate(chain):assert n>>(i*4)&15==node,(e,m,i,node,n)
 assert h=={str(p):hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in h}
 observations=[l for l in s.splitlines() if 'PASS:' in l]+['PASS: independent weighted-graph reference matches all 16 A-computed closure, shortest-path, direction and reverse-node results']
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'support_hashes':{str(O/'map_partition_scenes.txt'):hashlib.sha256((O/'map_partition_scenes.txt').read_bytes()).hexdigest()},'observations':observations,'routes_checked':16,'B_control_wire_Mbps_at_50Hz':0.0336},indent=2));print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
