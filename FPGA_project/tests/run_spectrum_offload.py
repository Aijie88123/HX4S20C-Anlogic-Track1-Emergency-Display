from pathlib import Path
import subprocess,hashlib,json,zlib,sys
from datetime import datetime,timezone

R=Path(__file__).resolve().parents[1];T=R/'tests'
O=R/'evidence/3d_ui_smooth_20261018/spectrum';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work_blue_ribbons'

base=bytearray(60)
base[:17]=bytes.fromhex('ffffffffffff0248583400a188b5485803')
base[17:23]=bytes([0,17,19,1,0,0x1e])
base[23:27]=bytes([1,1,0x34,0x12])
base[27:39]=bytes.fromhex('010000563412ffffff010080')
def frame(body):return bytes.fromhex('55555555555555d5')+body+zlib.crc32(body).to_bytes(4,'little')
frames=[frame(base)]
for pos,value in [(16,2),(11,0xb1),(23,2),(24,0x80),(22,0x80),(59,1)]:
    b=base.copy();b[pos]=value;frames.append(frame(b))
b=bytearray(frame(base));b[-1]^=1;frames.append(bytes(b))
frames.extend([frame(base)[:-1],frame(base)+b'\x00',frame(base),frame(base)])
nibbles=[]
for f in frames:
    for b in f:nibbles.extend([b&15,b>>4])
(T/'spectrum_rx_vectors.hex').write_text('\n'.join(f'{n:x}' for n in nibbles))
(T/'spectrum_rx_lengths.hex').write_text('\n'.join(f'{len(f)*2:04x}' for f in frames))
(T/'spectrum_rx_expected.hex').write_text('\n'.join('01' if i in [0,11] else '00' for i in range(len(frames))))

sources=list((R/'common').glob('*.v'))+[R/'B_control/rtl/audio_fft.v',T/'audio_fft_reference.v',
    T/'tb_spectrum_frames.v',T/'tb_spectrum_faults.v',T/'tb_spectrum_endpoints.v',T/'tb_endpoints.v',
    Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v'),Path(__file__)]
def snapshot():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in sources}
before=snapshot()
INI3D=O/'modelsim.ini';INI3D.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(tool,args):
    if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI3D.as_posix(),*args]
    p=subprocess.run([str(M/(tool+'.exe')),*args],cwd=T,capture_output=True,timeout=300)
    log=(p.stdout+p.stderr).decode(errors='replace')
    if p.returncode or '** Error' in log or '** Fatal' in log:raise RuntimeError(log)
    return log
if not W.exists():run('vlib',[str(W)])
log=run('vlog',['-sv','-work',str(W),*map(str,sources[:-1])]);(O/'compile.log').write_text(log)
observations=[]
targets=[('tb_spectrum_frames',None),('tb_spectrum_faults',None)]+[('tb_spectrum_endpoints',i) for i in [1,2,3]]
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
