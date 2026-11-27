"""Offline animation compiler; ANIM02 retains legacy ANIM01 decoder compatibility."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,tempfile
import numpy as np
from PIL import Image

def convert(source,output,ffmpeg='D:/gmt6/bin/ffmpeg.exe',legacy=False):
 source=Path(source);output=Path(output);output.mkdir(parents=True,exist_ok=True)
 im=Image.open(source);frames=[];ends=[];total=0
 for i in range(im.n_frames):
  im.seek(i);frames.append(im.convert('RGB').copy());total+=im.info.get('duration',80);ends.append(total)
 count,width,height,period,block=(40,240,135,113,5632) if legacy else (84,192,108,54,3584)
 if not legacy:
  with tempfile.TemporaryDirectory(prefix='fpga_motion_') as td:
   pattern=str(Path(td)/'%03d.png')
   subprocess.run([str(ffmpeg),'-hide_banner','-loglevel','error','-ignore_loop','1','-i',str(source),'-vf',
    'scale=192:108:flags=lanczos,tpad=stop_mode=clone:stop_duration=0.2,minterpolate=fps=500/27:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1',
    '-frames:v','84','-y',pattern],check=True)
   motion=[Image.open(p).convert('RGB').copy() for p in sorted(Path(td).glob('*.png'))]
  assert len(motion)==84,len(motion)
 words=np.zeros(307200,dtype=np.uint32);previews=[];chosen=[]
 for n in range(count):
  t=n*total/count;idx=next(j for j,e in enumerate(ends) if e>t);chosen.append(idx)
  frame=frames[idx].resize((width,height),Image.Resampling.LANCZOS) if legacy else motion[n]
  q=frame.quantize(colors=16,dither=Image.Dither.NONE);pal=q.getpalette();base=n*block
  words[base:base+4]=[0x414e49,0x4d3031 if legacy else 0x4d3032,(n<<16)|(count<<8)|period,0x0f0087 if legacy else 0x0c006c]
  words[base+4:base+20]=[(pal[j*3]<<16)|(pal[j*3+1]<<8)|pal[j*3+2] for j in range(16)]
  ix=np.asarray(q).reshape(-1).astype(np.uint32).reshape(-1,6)
  words[base+20:base+20+width*height//6]=sum(ix[:,j]<<(4*j) for j in range(6))
  qr=np.asarray(q.convert('RGB'));ys=np.arange(360)*height//360;xs=np.arange(640)//2*width//320
  previews.append(Image.fromarray(qr[ys[:,None],xs[None,:]]))
 rgb=np.stack([(words>>16)&255,(words>>8)&255,words&255],axis=1).astype(np.uint8).reshape(480,640,3)
 dest=output/'04.BMP';Image.fromarray(rgb).save(dest);raw=dest.read_bytes()
 assert raw[:2]==b'BM' and len(raw)==921654 and struct.unpack_from('<iiHHI',raw,18)==(640,480,1,24,0)
 a=np.asarray(Image.open(dest).convert('RGB')).reshape(-1,3).astype(np.uint32)
 assert np.array_equal((a[:,0]<<16)|(a[:,1]<<8)|a[:,2],words)
 previews[0].save(output/'animation_preview.gif',save_all=True,append_images=previews[1:],duration=period,loop=0)
 with (output/'animation_words.hex').open('w') as f:
  for w in words:f.write(f'{int(w)<<8:08x}\n')
 meta={'profile':'ANIM01' if legacy else 'ANIM02','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
  'carrier_sha256':hashlib.sha256(raw).hexdigest(),'source_frames':len(frames),'source_duration_ms':total,
  'frames':count,'width':width,'height':height,'colours_per_frame':16,'period_ms':period,'target_fps':1000/period,
  'carrier_role':5,'carrier_filename':'04.BMP','block_words':block,'used_words':count*block,
  'motion_interpolated':not legacy,'b_sdram_bytes':7833600,'a_sdram_bytes':7372800}
 (output/'animation.json').write_text(json.dumps(meta,indent=2),encoding='utf-8');print(json.dumps(meta),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('output');p.add_argument('--ffmpeg',default='D:/gmt6/bin/ffmpeg.exe');p.add_argument('--legacy',action='store_true');a=p.parse_args();convert(a.source,a.output,a.ffmpeg,a.legacy)
