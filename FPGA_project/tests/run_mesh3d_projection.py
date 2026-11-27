from pathlib import Path
import subprocess,json,hashlib,math
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/projection';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common/mesh3d_divider.v',R/'A_display/rtl/a_mesh3d_projector.v',T/'tb_mesh3d_projection.v'];logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
def trunc(a,b):return abs(a)//abs(b)*(-1 if (a<0)!=(b<0) else 1)
def signed(v,n):return v-(1<<n) if v>>(n-1) else v
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'mesh_projection',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 s=run('vsim',['-modelsimini',INI,'-c','mesh_projection.tb_mesh3d_projection','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 records=[int(x,16) for x in (T/'mesh3d_projected.hex').read_text().splitlines()]
 geometry=json.loads((R/'assets/true3d_scene.json').read_text())['triangles']
 poses=[(32,0,80,432,0,2),(0,1,432,80,0,1),(63,2,80,80,1,3)]
 errors=[]
 for frame,(yaw,zoom,pu,pv,event,mode) in enumerate(poses):
  angle=math.radians(-60+yaw*30/63);sn=round(math.sin(angle)*256);cs=round(math.cos(angle)*256);f=[240,300,360][zoom]
  fu=256+((pu-256)>>1);fv=256+((pv-256)>>1);hu,hv,hh=[(133,344,90),(133,168,68),(309,168,105),(309,344,80)][event]
  for idx,(a,b,c,color,kind,ref,edges) in enumerate(geometry):
   p=records[frame*118+idx]
   assert p&65535==0x010e and (p>>16)&65535==frame+1 and (p>>32)&255==idx
   for j,(u,v,h) in enumerate([a,b,c]):
    if kind==4:u+=pu;v+=pv
    elif kind==5:u+=hu;v+=hv;h+=hh
    elif kind==6:
     eu,ev=[(256,0),(0,256),(512,256),(256,512)][ref];u+=eu;v+=ev
    rx=((u-fu)*cs-(v-fv)*sn)>>8;rz=((u-fu)*sn+(v-fv)*cs)>>8
    cy=(h*147+rz*210)>>8;cz=900+((rz*147-h*210)>>8)
    expected=(160+trunc(rx*f,cz),80-trunc(cy*f,cz),min(65535,16777216//cz))
    word=p>>(64+j*40);actual=(signed(word&4095,12),signed((word>>12)&4095,12),(word>>24)&65535)
    if actual!=expected:errors.append((frame,idx,j,actual,expected,(u,v,h),cz))
   assert (p>>184)&3==event and (p>>186)&63==yaw and (p>>192)&3==zoom
  assert (records[(frame+1)*118-1]>>40)&1
 assert not errors,errors[:12]
 print('\n'.join(l for l in s.splitlines() if 'PASS:' in l));print('PASS: 1062 vertices exactly match independent signed integer 3D projection and inverse-depth model')
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[Path(__file__).resolve(),R/'assets/true3d_scene.json']},'vertices_checked':1062,'triangles_checked':354},indent=2))
finally:(O/'audit.log').write_text('\n'.join(logs))
