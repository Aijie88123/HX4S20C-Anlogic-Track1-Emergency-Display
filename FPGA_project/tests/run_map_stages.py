from pathlib import Path
import random,subprocess,json,hashlib,sys
from datetime import datetime,timezone
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/zoom_routing_20261012/tests';O.mkdir(parents=True,exist_ok=True)
MS=Path('D:/modelsim/win64');W=O/'work'
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
def golden(root,mask):
    dist=[65535]*13;dist[root]=0;visited=set();prev={}
    for _ in range(13):
        candidates=[n for n in range(13) if n not in visited and dist[n]<65535]
        if not candidates:return 0,0,0,0,True
        n=min(candidates,key=lambda n:(dist[n],n))
        if n>=9:
            end=n;route=dirs=length=0
            while n!=root:
                p,e=prev[n];route|=1<<e
                if (p<n if e<12 else p>=9 if e<14 else p<9):dirs|=1<<e
                n=p;length+=1
            return route,dirs,end,length,False
        visited.add(n)
        for e,(a,b) in enumerate(edges):
            if mask&(1<<e) or n not in (a,b):continue
            nxt=b if n==a else a;cost=176 if e<12 else 80
            if nxt not in visited and dist[n]+cost<dist[nxt]:dist[nxt]=dist[n]+cost;prev[nxt]=(n,e)
    return 0,0,0,0,True
cases=[]
for root in [6,0,2,8]:
    for mask in [0,0xffff,0xf000,*[1<<i for i in range(16)]]:cases.append((root,mask))
rng=random.Random(20261012)
while len(cases)<1088:cases.append((rng.randrange(13),rng.randrange(65536)))
vectors=[]
for root,mask in cases:
    route,dirs,dest,length,no=golden(root,mask)
    vectors.append(root|(mask<<4)|(route<<20)|(dirs<<36)|(dest<<52)|(length<<56)|(int(no)<<60))
(T/'map_solver_vectors.hex').write_text('\n'.join(f'{v:016x}' for v in vectors)+'\n')
sources=list((R/'common').glob('*.v'))+[R/'B_control/rtl/audio_fft.v',T/'audio_fft_reference.v',
 R/'A_display/rtl/emergency_map_top.v',T/'tb_map_solver.v',T/'tb_map_worker_client.v',T/'tb_map_render.v',
 T/'tb_map_endpoints.v',T/'tb_endpoints.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v'),Path(__file__)]
def snapshot():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in sources}
before=snapshot()
def run(tool,args):
    p=subprocess.run([str(MS/(tool+'.exe')),*args],cwd=T,capture_output=True,timeout=600)
    log=(p.stdout+p.stderr).decode(errors='replace')
    if p.returncode or '** Error' in log or '** Fatal' in log:raise RuntimeError(log)
    return log
if not W.exists():run('vlib',[str(W)])
(O/'compile.log').write_text(run('vlog',['-sv','-work',str(W),*map(str,sources[:-1])]))
targets=[('tb_map_solver',None),('tb_map_worker_client',None),('tb_map_render',None)]+[('tb_map_endpoints',i) for i in [1,2,3]]
if len(sys.argv)>1:targets=[(n,None) for n in sys.argv[1:]]
observations=[]
for top,delay in targets:
    args=['-c','-novopt','-t','1ps','-lib',str(W),top]
    if delay is not None:args+=['glbl','-gRX_DELAY='+str(delay)]
    log=run('vsim',args+['-do','onerror {quit -code 1}; run -all; quit -code 0'])
    (O/(top+str(delay)+'.log')).write_text(log)
    assert 'PASS:' in log
    rows=[l for l in log.splitlines() if 'PASS:' in l];observations+=rows;print('\n'.join(rows),flush=True)
    if top=='tb_map_render':
        from PIL import Image
        for i in range(5):
            data=bytes.fromhex((T/f'map_render_{i}.rgb').read_text())
            assert len(data)==1280*720*3
            Image.frombytes('RGB',(1280,720),data).save(O/f'map_preview_{i}.png')
assert before==snapshot(),'Inputs changed during simulation'
(O/'result.json').write_text(json.dumps({'status':'PASS','completed_utc':datetime.now(timezone.utc).isoformat(),
 'observations':observations,'compiled_sources':before},indent=2))
