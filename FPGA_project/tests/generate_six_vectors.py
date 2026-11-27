"""Generate a sparse FAT32 disk with shuffled directory entries and fragmented files."""
from pathlib import Path
import random, struct, hashlib, json, sys
ROOT=Path(__file__).resolve().parents[1]
small='--small' in sys.argv
OUT=ROOT/('tests/six_vectors_small' if small else 'tests/six_vectors')
OUT.mkdir(exist_ok=True)
FAT_BASE=2
FAT_SECTORS=512
DATA_BASE=514
CLUSTERS=65525
disk={}
def sector(lba):return disk.setdefault(lba,bytearray(512))
boot=sector(0);boot[446+4]=0x0c
struct.pack_into('<II',boot,446+8,1,CLUSTERS+513);boot[510:]=b'\x55\xaa'
bpb=sector(1);bpb[:3]=b'\xeb\x58\x90';bpb[3:11]=b'MSDOS5.0'
struct.pack_into('<H',bpb,11,512);bpb[13]=1
struct.pack_into('<H',bpb,14,1);bpb[16]=1;bpb[21]=0xf8
struct.pack_into('<I',bpb,32,CLUSTERS+513);struct.pack_into('<I',bpb,36,FAT_SECTORS)
struct.pack_into('<I',bpb,44,2);bpb[510:]=b'\x55\xaa'
fat=[0]*(CLUSTERS+2);fat[0]=0x0ffffff8;fat[1]=0x0fffffff
fat[2]=200;fat[200]=300;fat[300]=0x0fffffff
for cluster in [2,200]:
 d=sector(DATA_BASE+cluster-2)
 for i in range(16):d[i*32]=0xe5
available=[c for c in range(3,CLUSTERS+2) if c not in [200,300]]
random.Random(20261013).shuffle(available)
starts=[];seconds=[];files=[]
for slot in range(6):
 w,h=(427,321) if slot==4 else (640,480)
 if small:
  w=800 if slot==3 else 1280 if slot==4 else 640
  h=1
 stride=(w*3+3)&~3;size=54+stride*h
 raw=bytearray(size)
 struct.pack_into('<2sIHHI',raw,0,b'BM',size,0,0,54)
 struct.pack_into('<IiiHHIIiiII',raw,14,40,w,h,1,24,0,stride*h,2835,2835,0,0)
 for y in range(h):
  for x in range(w):
   pos=54+y*stride+x*3
   raw[pos:pos+3]=bytes([(x+y+slot)&255,y&255,(x^slot)&255])
  raw[54+y*stride+w*3:54+(y+1)*stride]=b'\xe7'*(stride-w*3)
 count=(size+511)//512
 chain=[available.pop() for _ in range(count)]
 starts.append(chain[0]);seconds.append(chain[1])
 for i,c in enumerate(chain):
  fat[c]=chain[i+1] if i+1<len(chain) else 0x0fffffff
  sector(DATA_BASE+c-2)[:]=raw[i*512:(i+1)*512].ljust(512,b'\0')
 files.append({'slot':slot,'width':w,'height':h,'bytes':size,'first_cluster':chain[0],'clusters':count})
names=[b'05      BMP',b'06      BMP',b'01      BMP',b'02      BMP',b'03      BMP',b'04      BMP']
root=sector(DATA_BASE+300-2)
order=[5,2,0,4,3,1]
for pos,slot in enumerate(order):
 entry=pos*32;root[entry:entry+11]=names[slot];root[entry+11]=0x20
 struct.pack_into('<H',root,entry+20,starts[slot]>>16)
 struct.pack_into('<H',root,entry+26,starts[slot]&65535)
 struct.pack_into('<I',root,entry+28,files[slot]['bytes'])
# A duplicate valid alarm entry must not replace the earlier slot.
root[192:224]=root[64:96]
for page in range(FAT_SECTORS):
 d=sector(FAT_BASE+page)
 for i in range(128):
  idx=page*128+i
  if idx<len(fat):struct.pack_into('<I',d,i*4,fat[idx])
path=OUT/'disk.hex'
with path.open('w',encoding='ascii') as out:
 for lba,d in sorted(disk.items()):
  out.write(f'@{lba*512:08x}\n')
  out.write('\n'.join(f'{b:02x}' for b in d)+'\n')
for name,values in [('starts',starts),('seconds',seconds)]:
 (OUT/(name+'.hex')).write_text('\n'.join(f'{v:08x}' for v in values)+'\n',encoding='ascii')
(OUT/'manifest.json').write_text(json.dumps({'filesystem':'FAT32','cluster_count':CLUSTERS,
 'sectors_per_cluster':1,'directory_chain':[2,200,300],'directory_order':order,
 'files':files,'sparse_sectors':len(disk),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper()},indent=2),encoding='utf-8')
print('Generated valid-sized FAT32 volume; all six file chains fragmented; root spans three nonadjacent clusters.')
