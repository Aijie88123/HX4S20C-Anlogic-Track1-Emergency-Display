from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/legacy_transitions';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work_blue_ribbons';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')

def texel(a):
 x=a%128;y=a//128;tx=x//8;ty=y//8;lx=x%8;ly=y%8
 h=((tx<<4)|(ty<<1)|1)^((ty<<5)|(tx<<1))^((tx&3)<<6|ty<<3|tx>>1)^0xb5
 cx=2+(h&3);cy=2+((h>>2)&3);distance=abs(lx-cx)+abs(ly-cy)
 glow=0
 if h>>6:
  glow={0:7,1:5,2:2}.get(distance,0)
 if 36<=y+(abs(x-70)>>1)<=39 or 42<=y+(abs(x-70)>>2)<=43:
  glow=max(glow,2)
  if lx==cx:glow=max(glow,6)
 phase=(((h>>1)&15)<<1|((h>>7)&1))^19
 return min(29,max(2,phase))*8+glow

(T/'particle_reference.hex').write_text(''.join(f'{texel(i):02x}\n' for i in range(8192)))
files=[R/'common'/n for n in ['particle_transition.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]+[T/'tb_particle_wire.v']
files += [R/'A_display/rtl'/n for n in ['alpha_blend.v','audio_bars_overlay.v','audio_envelope.v','audio_fft.v','audio_spectrum_overlay.v','chinese_title_overlay.v','chinese_title_rom.v','text_overlay_8x8.v','transition_fx.v','video_palette_lookup.v','smart_terminal_overlay.v','smart_terminal_overlay_pipelined.v']]+[T/'tb_particle_compositor.v',T/'tb_particle_machine.v']
logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=T,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'particle_work',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 observations=[]
 for bench in ['tb_particle_wire','tb_particle_machine','tb_particle_compositor']:
  s=run('vsim',['-modelsimini',INI,'-c','particle_work.'+bench,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s
  rows=[l for l in s.splitlines() if 'PASS:' in l];observations+=rows
  print('\n'.join(rows),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'observations':observations},indent=2))
