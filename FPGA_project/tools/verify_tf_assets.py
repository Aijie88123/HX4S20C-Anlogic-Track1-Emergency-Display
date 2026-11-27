"""Validate TF BMP assets without modifying files."""
from pathlib import Path
import argparse, struct, hashlib, json
parser=argparse.ArgumentParser();parser.add_argument('folder',type=Path);parser.add_argument('--competition',action='store_true');args=parser.parse_args()
paths=sorted(p for p in args.folder.iterdir() if p.is_file() and p.suffix.lower()=='.bmp')
if args.competition:assert len(paths)>=4,'Competition profile requires at least four BMP files'
roles=['01.BMP','02.BMP','03.BMP','02INFO.BMP','03INFO.BMP','04INFO.BMP','05.BMP','06.BMP'];rows=[]
for p in paths:
 raw=p.read_bytes();assert len(raw)>=54 and raw[:2]==b'BM',p.name
 size,offset=struct.unpack_from('<I',raw,2)[0],struct.unpack_from('<I',raw,10)[0]
 dib,w,h,planes,bits,compression=struct.unpack_from('<IiiHHI',raw,14)
 assert dib>=40 and offset>=14+dib and planes==1 and bits==24 and compression==0,p.name
 assert 1<=w<=4095 and 1<=h<=4095,p.name
 stride=(w*3+3)&~3
 assert size<=len(raw) and size>=offset+stride*h,p.name
 if args.competition:assert w>=640 and h>=480,p.name
 rows.append({'name':p.name,'width':w,'height':h,'bits':bits,'compression':'BI_RGB','file_bytes':len(raw),'row_stride':stride,'role':roles.index(p.name.upper()) if p.name.upper() in roles else 'ignored by production named scanner','sha256':hashlib.sha256(raw).hexdigest().upper()})
assert rows,'No BMP files'
print(json.dumps({'status':'PASS','competition_profile':args.competition,'files':rows},ensure_ascii=False,indent=2))
