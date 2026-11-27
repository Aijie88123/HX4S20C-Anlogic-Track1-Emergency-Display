from pathlib import Path
import subprocess,hashlib,json,zlib,sys
from datetime import datetime,timezone

R=Path(__file__).resolve().parents[1];T=R/'tests'
O=R/'evidence/spectrum_offload_20261012/external_display';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work'

sources=[R/'A_display/rtl/audio_spectrum_overlay.v',T/'audio_spectrum_reference.v',T/'tb_external_spectrum_display.v',Path(__file__)]
def snapshot():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in sources}
before=snapshot()
def run(tool,args):
    p=subprocess.run([str(M/(tool+'.exe')),*args],cwd=T,capture_output=True,timeout=300)
    log=(p.stdout+p.stderr).decode(errors='replace')
    if p.returncode or '** Error' in log or '** Fatal' in log:raise RuntimeError(log)
    return log
if not W.exists():run('vlib',[str(W)])
log=run('vlog',['-sv','-work',str(W),*map(str,sources[:-1])]);(O/'compile.log').write_text(log)
observations=[]
targets=[('tb_external_spectrum_display',None)]
if len(sys.argv)>1:
    targets=[(name,None) for name in sys.argv[1:]]
for top,delay in targets:
    args=['-c','-novopt','-t','1ps','-lib',str(W),top]
    if delay is not None:args+=['glbl','-gRX_DELAY='+str(delay)]
    log=run('vsim',args+['-do','onerror {quit -code 1}; run -all; quit -code 0'])
    (O/(top+str(delay)+'.log')).write_text(log)
    assert 'PASS:' in log
    obs=[l for l in log.splitlines() if 'PASS:' in l]
    observations+=obs;print('\n'.join(obs),flush=True)
    if top=='tb_spectrum_endpoints':
        frames=(T/'spectrum_endpoint_tx_nibbles.hex').read_text().splitlines()
        pcm_count=0
        for n in frames:
            b=bytes(int(n[i+1]+n[i],16) for i in range(0,len(n),2));f=b[8:]
            assert len(f)==64 and b[:8]==bytes.fromhex('55555555555555d5')
            assert f[12:17]==bytes.fromhex('88b5485803')
            assert int.from_bytes(f[-4:],'little')==zlib.crc32(f[:-4])
            if f[23]==1:pcm_count+=1;assert f[39:60]==bytes(21)
        assert pcm_count==1536,pcm_count
        observations.append(f'PASS: independent zlib CRC and v3 padding, 1536 PCM frames, RX delay={delay}')
assert before==snapshot(),'Inputs changed during testing'
(O/'result.json').write_text(json.dumps({'status':'PASS','completed_utc':datetime.now(timezone.utc).isoformat(),
    'observations':observations,'compiled_sources':before},indent=2))
