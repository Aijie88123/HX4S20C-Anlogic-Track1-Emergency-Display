from pathlib import Path
import math,json,sys
R=Path(__file__).resolve().parents[1]
def emit(path,text):
 if '--check' in sys.argv:assert path.read_text()==text,str(path)
 else:path.write_text(text)
triangles=[]
def tri(a,b,c,color,kind,ref=0,edges=7):triangles.append((a,b,c,color,kind,ref,edges))
def quad(a,b,c,d,color,kind,ref=0):
 tri(a,b,c,color,kind,ref,3);tri(a,c,d,color,kind,ref,6)
quad((-32,-32,0),(544,-32,0),(544,544,0),(-32,544,0),0x0023,0)
buildings=[]
for block,(u,v) in enumerate([(168,168),(344,168),(168,344),(344,344)]):
 for part in range(2):
  x=u-56+part*62;z=v-46;w=42;d=92;h=[68,95,105,60,90,68,80,110][block*2+part]
  buildings.append([x,z,w,d,h]);i=block*2+part
  quad((x,z,h),(x+w,z,h),(x+w,z+d,h),(x,z+d,h),0x12ab,1,i)
  quad((x+w,z,0),(x+w,z+d,0),(x+w,z+d,h),(x+w,z,h),0x018a,2,i)
  quad((x,z,0),(x+w,z,0),(x+w,z,h),(x,z,h),0x0107,2,i)
nodes=[(u,v) for v in [80,256,432] for u in [80,256,432]]+[(256,0),(0,256),(512,256),(256,512)]
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
for i,(a,b) in enumerate(edges):
 u,v=nodes[a];s,t=nodes[b];w=9
 if u==s:quad((u-w,v,2),(u+w,v,2),(s+w,t,2),(s-w,t,2),0x0252,3,i)
 else:quad((u,v-w,2),(s,t-w,2),(s,t+w,2),(u,v+w,2),0x0252,3,i)
def marker(kind,ref,color,r=8,base=23,top=68):
 a=(-r,0,base);b=(0,-r,base);c=(r,0,base);d=(0,r,base);tip=(0,0,7);head=(0,0,top)
 for p,q in [(a,b),(b,c),(c,d),(d,a)]:tri(p,q,head,color,kind,ref)
 tri(a,c,tip,color,kind,ref);tri(a,tip,d,color,kind,ref)
marker(4,0,0x07ff)
marker(5,0,0xf94a,r=12,base=18,top=45)
for i in range(4):marker(6,i,0xffa4,r=7,base=13,top=40)
assert len(triangles)==118
triangles=[(*row[:-1],0) if row[4]==0 else row for row in triangles]
words=[]
for a,b,c,color,kind,ref,mask in triangles:
 for u,v,h in [a,b,c]:
  packed=(u&2047)|((v&2047)<<11)|((h&1023)<<22)
  words.extend([packed&65535,packed>>16])
 words.extend([color,(kind<<12)|(ref<<8)|(mask<<1)])
words += [0]*(1024-len(words))
emit(R/'tests/true3d_geometry.hex',''.join(f'{v:04x}\n' for v in words))
emit(R/'assets/true3d_scene.json',json.dumps({'triangles':triangles,'buildings':buildings,'nodes':nodes,'edges':edges,'native_raster':[320,180],'transport_frame':[640,360]},indent=2))
initial='\n'.join(f"  geometry[{i}]=16'h{v:04x};" for i,v in enumerate(words))
trig='\n'.join(f"   6'd{i}:trig=20'h{(((round(math.sin(math.radians(-60+i*30/63))*256))&1023)<<10)|(round(math.cos(math.radians(-60+i*30/63))*256)&1023):05x};" for i in range(64))
template=(Path(__file__).parent/'a_mesh3d_projector_template.v').read_text()
emit(R/'A_display/rtl/a_mesh3d_projector.v',template.replace('GEOMETRY_INITIAL',initial).replace('TRIG_CASE',trig))
print('Generated 118 true XYZ triangles, geometry ROM and perspective projector')
