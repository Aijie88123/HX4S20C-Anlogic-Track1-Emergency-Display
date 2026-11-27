from pathlib import Path
import subprocess,json,hashlib,math,sys
import numpy as np
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/audio_visual_20261021/numeric';O.mkdir(parents=True,exist_ok=True)
freqs=[261.63,293.66,329.63,349.23,392,440,493.88,523.25,800,1000,1200,1600]
inc=np.array([round(f*2**32/48000) for f in freqs],np.uint64)
phase=(np.arange(2048,dtype=np.uint64)[:,None]*inc[None,:])&0xffffffff
quarter=np.array([round(2047*math.sin(math.pi*k/512)) for k in range(257)],np.int64)
window=np.array([round(255*(.54-.46*math.cos(2*math.pi*k/63))) for k in range(64)],np.int64)[np.arange(2048)//32]
def sine(p):
 q=(p>>22).astype(np.int64);n=q&255;addr=np.where((q&256)!=0,256-n,n)
 return quarter[addr]*np.where((q&512)!=0,-1,1)
def code(p):
 if not p:return 0
 e=int(p).bit_length()-1;s=int(p)>>(e-6) if e>=6 else int(p)<<(6-e)
 return e*64+(s&63)
def original_tone(length):
 out=[];p=0;env=0
 for n in range(length):
  t=p>>24;tri=(383-2*t) if t&128 else (2*t-128)
  e=env>>24;v=(~e&127) if e&128 else e&127
  amp=1000000+(2000000*v>>8)
  out.append(tri*amp>>7)
  p=(p+23409862)&0xffffffff;env=(env+107374)&0xffffffff
 return np.array(out,np.int64)
si=sine(phase);co=sine((phase+0x40000000)&0xffffffff);n=np.arange(2048)
vectors=[];expected=[];checks=[]
for case in range(17):
 if case<12:samples=np.rint(1700000*np.sin(2*np.pi*freqs[case]*n/48000)).astype(np.int64)
 elif case==12:samples=np.zeros(2048,np.int64)
 elif case==13:samples=np.full(2048,1048576,np.int64)
 elif case==14:samples=np.rint(1700000*np.sin(2*np.pi*(4000+freqs[0])*n/48000)).astype(np.int64)
 elif case==15:samples=np.rint(900000*np.sin(2*np.pi*freqs[0]*n/48000)+1100000*np.sin(2*np.pi*1200*n/48000)).astype(np.int64)
 else:samples=original_tone(2048)
 x=((samples>>8)*window)>>8
 ii=(x[:,None]*si).sum(axis=0)>>20;qq=(x[:,None]*co).sum(axis=0)>>20
 powers=ii*ii+qq*qq;codes=[code(v) for v in powers]
 if case<12:assert int(np.argmax(powers))==case
 if case==14:assert max(powers)*10000<checks[0]['powers'][0],'4262Hz folded response must be at least40dB below the true C4 input'
 checks.append({'case':case,'peak_index':int(np.argmax(powers)),'powers':powers.tolist(),'log_powers':codes})
 vectors.extend(samples);expected.extend(codes)
(T/'visual_dft_samples.hex').write_text(''.join(f'{int(v)&0xffffff:06x}\n' for v in vectors))
(T/'visual_dft_expected.hex').write_text(''.join(f'{int(v):04x}\n' for v in expected))
(T/'visual_wave_samples.hex').write_text(''.join(f'{int(v)&0xffffff:06x}\n' for v in original_tone(16384)))
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'common/audio_dft12.v',R/'common/distributed_audio.v',R/'B_control/rtl/audio_fft.v']+[R/'A_display/rtl'/f for f in ['audio_label_font_fast.v','audio_waveform_precise_overlay.v','audio_spectrum_precise_overlay.v']]+[T/f for f in ['tb_visual_dft12.v','tb_visual_packet12.v','tb_visual_display.v']]
bound=files+[Path(__file__).resolve(),R/'tools/generate_audio_dft12.py',R/'tools/audio_dft12.template']+[T/f for f in ['visual_dft_samples.hex','visual_dft_expected.hex','visual_wave_samples.hex']]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 text=(p.stdout+p.stderr).decode(errors='replace');logs.append(text);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in text or '** Fatal' in text:raise RuntimeError(text[-6500:])
 return text
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);obs=[]
for top in (sys.argv[1:] or ['tb_visual_dft12','tb_visual_packet12','tb_visual_display']):
 text=run('vsim',['-modelsimini',I,'-c','-novopt','-lib',W,top,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in text
 lines=[v for v in text.splitlines() if 'PASS:' in v];obs+=lines;print('\n'.join(lines),flush=True)
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':obs,'independent_numeric':checks},indent=2))
