from pathlib import Path
import subprocess,json,hashlib,zlib
import numpy as np
from native_vga_reference import pack,render
R=Path(__file__).resolve().parents[1];T=R/'tests';M=Path('D:/modelsim/win64');O=R/'evidence/map_detail_20261020/concurrent';O.mkdir(parents=True,exist_ok=True)
W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
for name in ['particle','map']:
 words=np.loadtxt(T/f'native_{name}_words.hex',dtype=np.uint32,converters={0:lambda v:int(v,16)})
 if name=='particle':assert np.array_equal(words,pack(render(0)))
 w=words.reshape(-1,3)
 q=np.stack((w[:,0]&4095,(w[:,0]>>12)&4095,(w[:,0]>>24)|((w[:,1]&15)<<8),(w[:,1]>>4)&4095,(w[:,1]>>16)&4095,(w[:,1]>>28)|((w[:,2]&255)<<4),(w[:,2]>>8)&4095,(w[:,2]>>20)&4095),axis=1).ravel()
 c=((q>>8)<<12)|(((q>>8)&15)>>3<<11)|(((q>>4)&15)<<7)|(((q>>4)&15)>>2<<5)|((q&15)<<1)|((q&15)>>3)
 (T/f'smooth_{name}_pixels.hex').write_text(''.join(f'{v:04x}\n' for v in c))
sd=R/'A_display/vendor/user_source/hdl_source/SD'
files=[R/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_raster_burst.v','ethernet_command_link.v','ethernet_mdio.v','distributed_audio.v','distributed_media.v','raster_map_transport.v','raster_map_window.v']]+[R/'B_control/rtl/audio_fft.v',R/'common/audio_dft12.v']+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v']]+[T/'card_spi_storage.v',T/'tb_endpoints.v',T/'tb_native_burst_concurrent.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v')]
provenance=[R/'A_display/rtl/smart_terminal_hw_top.v',R/'B_control/rtl/dual_board_control_top.v',Path(__file__).resolve(),T/'native_vga_reference.py',T/'blue_particle_model.py',T/'smooth_particle_pixels.hex',T/'smooth_map_pixels.hex',T/'native_particle_words.hex',T/'native_map_words.hex']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+provenance}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-8000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'burst_concurrent',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
observations=[];wire_counts={}
for kind in [0,1]:
 s=run('vsim',['-modelsimini',I,'-c','burst_concurrent.tb_native_burst_concurrent','burst_concurrent.glbl',f'-GKIND={kind}','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 rows=[v for v in s.splitlines() if 'PASS:' in v or 'MEASURE:' in v];observations+=rows;print('\n'.join(rows),flush=True)
 for side in ['a','b']:
  src=T/f'tf_concurrent_{side}.hex';dest=O/f'kind{kind}_{side}.hex';dest.write_bytes(src.read_bytes());counts={};batches=0
  for line in src.read_text().splitlines():
   wire=bytes(int(line[j+1]+line[j],16) for j in range(0,len(line),2));body=wire[8:]
   assert wire[:8]==b'\x55'*7+b'\xd5' and body[12:17]==bytes.fromhex('88b548580c')
   assert int.from_bytes(body[-4:],'little')==zlib.crc32(body[:-4])
   if body[23]==16:
    batches+=1;n=body[24];assert 1<=n<=4 and len(body)==max(60,25+28*n)+4
    for j in range(n):k=body[25+j*28];counts[k]=counts.get(k,0)+1
   else:assert len(body)==64;k=body[23];counts[k]=counts.get(k,0)+1
  wire_counts[f'{kind}_{side}']={'streams':counts,'burst_frames':batches}
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+provenance}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':hashes,'observations':observations,'wire_counts':wire_counts,'independent_zlib_FCS':True},indent=2))
