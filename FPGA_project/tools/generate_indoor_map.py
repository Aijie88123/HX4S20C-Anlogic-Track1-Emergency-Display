"""Code-native fixed-camera 3D floor cutaway, exact RGB444 palette/tile source.
Floor graph is the existing 13-node/16-edge graph, embedded in walkable corridors.
No external photograph, colour framebuffer, TF read or new SDRAM transaction.
"""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];P=R/'assets/indoor_map';P.mkdir(parents=True,exist_ok=True)
# Refine2: retain exact16footprints/projection; materials and roof details only.
PAL=[0x001122,0x112233,0x223344,0x112233,0x335566,0x668899,0x99bbcc,0xccddee,
     0xeeffff,0x334455,0x447788,0x223333,0x334444,0x447777,0x88aabb,0x557788]
im=Image.new('P',(640,480),0);im.putpalette(sum([[(c>>16)&255,(c>>8)&255,c&255] for c in PAL],[])+[0]*720)
d=ImageDraw.Draw(im)
font=lambda s:ImageFont.truetype('C:/Windows/Fonts/consola.ttf',s)
cfont=lambda s:ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',s)
namefont=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',13)
building_names=json.loads((R/'assets/building_names.json').read_text(encoding='utf-8'))
visual_geometry={}
def poly(points,c):d.polygon([(round(x),round(y)) for x,y in points],fill=c)
def p(u,v,z=0):return (320+(u-v)/2,94+(u+v)/4-z)
def rect(u0,v0,u1,v1,c,z=0):poly([p(u0,v0,z),p(u1,v0,z),p(u1,v1,z),p(u0,v1,z)],c)
def box(u0,v0,u1,v1,h,top=7,front=6,side=5,z0=0):
 poly([p(u0,v1,z0),p(u1,v1,z0),p(u1,v1,h),p(u0,v1,h)],front)
 poly([p(u1,v0,z0),p(u1,v1,z0),p(u1,v1,h),p(u1,v0,h)],side)
 rect(u0,v0,u1,v1,top,h)
# Top and bottom bars stay in their original screen bands.
d.rectangle((0,0,639,50),fill=1);d.rectangle((20,13,23,36),fill=10)
d.text((34,8),'EMERGENCY CONTROL',font=font(21),fill=8)
d.text((35,32),'校园疏散指挥',font=cfont(12),fill=6)
d.text((495,12),'LEVEL 01',font=font(16),fill=7)
d.line((20,50,619,50),fill=10,width=1)
for recta in [(20,58,204,89),(436,58,619,89)]:d.rectangle(recta,fill=1,outline=2)
# Small generic incident indicator; event-specific text is real scene data.
poly([(28,81),(36,65),(44,81)],10);d.line((36,70,36,75),fill=8);d.point((36,78),fill=8)
d.text((455,64),'应急演练 / 场景联动',font=cfont(13),fill=6)
# Same original ground/plinth geometry and lighting direction.
poly([(320,110),(606,246),(350,397),(52,251)],0)
poly([(320,104),(590,238),(320,382),(50,238)],3)
poly([p(0,512),p(512,512),p(512,512,-38),p(0,512,-38)],5)
poly([p(512,0),p(512,512),p(512,512,-38),p(512,0,-38)],4)
for level in [9,23]:
 for q in range(16,497,40):
  poly([p(q,512,-level),p(q+23,512,-level),p(q+23,512,-level-7),p(q,512,-level-7)],3)
  poly([p(q+3,512,-level-1),p(q+20,512,-level-1),p(q+20,512,-level-3),p(q+3,512,-level-3)],7)
  poly([p(512,q,-level),p(512,q+23,-level),p(512,q+23,-level-7),p(512,q,-level-7)],3)
  poly([p(512,q+3,-level-1),p(512,q+20,-level-1),p(512,q+20,-level-3),p(512,q+3,-level-3)],6)
rect(0,0,512,512,3)
# A single uniform pavement width; subdued kerb instead of bright lattice lines.
for q in [80,256,432]:
 rect(0,q-22,512,q+22,12);rect(q-22,0,q+22,512,12)
 rect(0,q-18,512,q+18,11);rect(q-18,0,q+18,512,11)
rooms=[];functions=[]
for v0,v1 in [(0,54),(106,230),(282,406),(458,512)]:
 for u0,u1 in [(0,54),(106,230),(282,406),(458,512)]:rooms.append((u0+3,v0+3,u1-3,v1-3))
for idx,(u0,v0,u1,v1) in sorted(enumerate(rooms),key=lambda q:q[1][2]+q[1][3]):
 # Footprint unchanged. Foundation2px, wall6px, roof cap2px, same proportions.
 box(u0-1,v0-1,u1+1,v1+1,2,3,3,3)
 box(u0,v0,u1,v1,8,7,6,5,z0=2)
 box(u0-1,v0-1,u1+1,v1+1,10,7,6,4,z0=8)
 rect(u0+2,v0+2,u1-2,v0+4,8,10)
 rect(u0+2,v0+4,u0+4,v1-2,8,10)
 # Recessed roof deck and two low parapets establish thickness without a glow.
 rect(u0+8,v0+8,u1-8,v1-8,14,10)
 rect(u0+10,v0+10,u1-10,v1-10,7,10)
 box(u0+4,v0+4,u1-4,v0+7,12,8,6,5,z0=10)
 box(u0+4,v0+7,u0+7,v1-4,12,8,6,5,z0=10)
 # Cyan accents occupy short corners only, leaving architecture quiet.
 rect(u1-14,v1-2,u1-3,v1,10,10)
 # One common window language for every functional building.
 for q in range(int(u0)+8,int(u1)-6,13):
  poly([p(q,v1,4),p(q+7,v1,4),p(q+7,v1,7),p(q,v1,7)],4)
  poly([p(q+1,v1,6),p(q+6,v1,6),p(q+6,v1,7),p(q+1,v1,7)],7)
 for q in range(int(v0)+8,int(v1)-6,13):
  poly([p(u1,q,4),p(u1,q+7,4),p(u1,q+7,7),p(u1,q,7)],4)
  poly([p(u1,q+1,6),p(u1,q+6,6),p(u1,q+6,7),p(u1,q+1,7)],6)
 kind=idx%4;functions.append(dict(id=f'B{idx+1:02}',kind=['主楼','教学楼','实验楼','生活楼'][kind],bounds=[u0,v0,u1,v1]))
 # Subtle roof silhouettes; all structures remain inside original bounds.
 w,l=u1-u0,v1-v0
 if kind==0:
  box(u0+15,v0+16,min(u0+39,u1-10),min(v0+39,v1-10),14,8,14,15,z0=10)
 elif kind==1:
  for q in sorted(set([16,max(16,int(l)-38)])):box(u0+16,v0+q,min(u0+45,u1-10),min(v0+q+18,v1-9),14,8,14,15,z0=10)
 elif kind==2:
  box(u0+16,v0+16,min(u0+42,u1-10),min(v0+39,v1-10),14,8,14,15,z0=10)
  if w>70:box(u0+58,v0+39,u0+83,min(v0+60,v1-10),13,7,14,15,z0=10)
 else:
  box(u0+16,v0+18,min(u0+38,u1-10),min(v0+35,v1-10),13,8,14,15,z0=10)
 # Raised setback floor is inset enough to keep original corridor centres clear.
 inset=18 if w>=80 and l>=80 else 12
 cu0,cv0,cu1,cv1=u0+inset,v0+inset,u1-inset,v1-inset
 upper=16 if w>=80 and l>=80 else 14
 rect(cu0+3,cv0+4,cu1+5,cv1+5,9,10)
 box(cu0,cv0,cu1,cv1,upper,7,6,5,z0=10)
 box(cu0-1,cv0-1,cu1+1,cv1+1,upper+1,7,6,4,z0=upper)
 rect(cu0+1,cv0+1,cu1-1,cv0+3,8,upper+1)
 rect(cu0+1,cv0+3,cu0+3,cv1-1,8,upper+1)
 # Matching glazing on the upper-floor facade with darker window reveals.
 for q in range(int(cu0)+4,int(cu1)-3,11):
  poly([p(q,cv1,upper-4),p(min(q+6,cu1-2),cv1,upper-4),p(min(q+6,cu1-2),cv1,upper-1),p(q,cv1,upper-1)],4)
  poly([p(q+1,cv1,upper-3),p(min(q+5,cu1-2),cv1,upper-3),p(min(q+5,cu1-2),cv1,upper-2),p(q+1,cv1,upper-2)],7)
 for q in range(int(cv0)+4,int(cv1)-3,11):
  poly([p(cu1,q,upper-4),p(cu1,min(q+6,cv1-2),upper-4),p(cu1,min(q+6,cv1-2),upper-1),p(cu1,q,upper-1)],4)
  poly([p(cu1,q+1,upper-3),p(cu1,min(q+5,cv1-2),upper-3),p(cu1,min(q+5,cv1-2),upper-2),p(cu1,q+1,upper-2)],6)
 # Small equipment, skylights and contact shadows share one lighting direction.
 ru0,rv0=cu0+5,cv0+5;ru1,rv1=min(cu0+19,cu1-4),min(cv0+18,cv1-4)
 rect(ru0+3,rv0+3,ru1+3,rv1+3,9,upper+1)
 box(ru0,rv0,ru1,rv1,upper+4,8,14,15,z0=upper+1)
 if cu1-cu0>42:
  rect(cu0+28,cv0+13,cu1-7,cv0+23,14,upper+1)
  rect(cu0+29,cv0+14,cu1-8,cv0+16,8,upper+1)
 if kind==2 and cv1-cv0>42:
  box(cu1-20,cv1-19,cu1-8,cv1-8,upper+3,7,14,15,z0=upper+1)
 ident=f'B{idx+1:02}'
 visual_geometry[ident]=dict(upper_height=upper,maximum_height=upper+4,upper_bounds=[cu0,cv0,cu1,cv1])
 for meta in functions:
  if meta['id']==ident:meta.update(short_name=building_names[ident]['short'],name=building_names[ident]['name'])

# Same four exits. Stair textures share walkable material classes, so the safe
# route can remain continuous to the terminal marker without crossing walls.
for u0,v0,u1,v1 in [(236,0,276,48),(0,236,48,276),(464,236,512,276),(236,464,276,512)]:
 rect(u0,v0,u1,v1,11)
 for j,q in enumerate(range(v0+3,v1,6)):box(u0+4,q,u1-4,min(q+4,v1-1),max(1,7-j),12,11,12)
 rect(u0,v0,u0+2,v1,10,7);rect(u1-2,v0,u1,v1,10,7)
for u,v in [(256,8),(8,256),(504,256),(256,504)]:rect(u-9,v-6,u+9,v+6,13)
# Readable13px nameplates, placed without touching walkable materials or HUD.
road_guard=np.isin(np.asarray(im),[11,12,13]);np.save(P/'labels_road_guard.npy',road_guard)
nameplates=[];used=[]
for idx,(u0,v0,u1,v1) in sorted(enumerate(rooms),key=lambda q:q[1][2]+q[1][3]):
 ident=f'B{idx+1:02}';short=building_names[ident]['short'];geom=visual_geometry[ident]
 ax,ay=p((u0+u1)/2,(v0+v1)/2,geom['upper_height']+1)
 width=int(np.ceil(namefont.getlength(short)))+8;height=19
 # The fire building name stays below its existing particle anchors.
 py=ay+(20 if ident=='B10' else 0)
 candidates=[]
 for dy in [0,6,12,-6,18,24,-12]:
  for dx in [0,-8,8,-20,20,-38,38]:
   x0=round(ax+dx-width/2);y0=round(py+dy-height/2);x1=x0+width-1;y1=y0+height-1
   if x0<5 or x1>634 or y0<55 or y1>401:continue
   if y0<90 and y1>=58 and (x0<210 or x1>=430):continue
   area=lambda b:max(0,min(x1,b[2])-max(x0,b[0])+1)*max(0,min(y1,b[3])-max(y0,b[1])+1)
   roads=int(road_guard[y0:y1+1,x0:x1+1].sum());overlap=sum(area(b) for b in used)
   fire=area((220,202,244,214)) if ident=='B10' else 0
   if roads or overlap or fire:continue
   candidates.append((dx*dx+dy*dy,(x0,y0,x1,y1)))
 assert candidates,('No clear nameplate placement',ident)
 _,bbox=min(candidates,key=lambda q:q[0]);x0,y0,x1,y1=bbox
 # Thin leaders are clipped around roads; labels themselves never cover a road.
 tx,ty=(x0+x1)/2,(y0+y1)/2
 if abs(tx-ax)+abs(ty-ay)>10:
  steps=max(1,int(abs(tx-ax)+abs(ty-ay)))
  for t in range(steps+1):
   xx,yy=round(ax+(tx-ax)*t/steps),round(ay+(ty-ay)*t/steps)
   if 0<=xx<640 and 0<=yy<410 and not road_guard[yy,xx]:d.point((xx,yy),fill=10)
 d.rectangle(bbox,fill=1,outline=2)
 d.line((x0+3,y1-1,x1-3,y1-1),fill=10,width=1)
 d.text((x0+4,y0+1),short,font=namefont,fill=8)
 used.append(bbox);nameplates.append(dict(id=ident,short_name=short,name=building_names[ident]['name'],anchor=[ax,ay],box=list(bbox)))
(P/'building_catalog.json').write_text(json.dumps(nameplates,ensure_ascii=False,indent=2),encoding='utf-8')

# Four restrained data panels. Values are drawn from current V12 scene fields.
for x,label in [(20,'事件状态'),(170,'当前路线'),(320,'危险建筑'),(470,'出口状态')]:
 d.rectangle((x,412,x+148,477),fill=1,outline=2)
 d.text((x+9,420),label,font=cfont(13),fill=6)
 d.line((x+9,437,x+138,437),fill=2,width=1)
entries=['火灾','地震','实验室事故','演练','出口 01','出口 02','出口 03','出口 04','无可用路线',
         *[building_names[k]['short']+' '+k for k in ['B10','B06','B07','B11']],'开放 0/4','开放 1/4','开放 2/4','开放 3/4','开放 4/4',
         '火灾演练','地震演练','实验室演练','应急演练']
hud=np.zeros((32,16,128),np.uint8)
for i,t in enumerate(entries):
 bm=Image.new('1',(128,16),0);ImageDraw.Draw(bm).text((0,-2),t,font=cfont(16),fill=1);hud[i]=np.asarray(bm,dtype=np.uint8)
np.save(P/'hud_bits.npy',hud)
(P/'hud_entries.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf-8')
im.convert('RGB').save(P/'architecture.png')
a=np.asarray(im).copy();np.save(P/'palette_indices.npy',a)
# Use 4x4 dictionary tiles; padded640x512 gives simple bit concatenation address.
pad=np.zeros((512,640),dtype=np.uint8);pad[:480]=a
tiles=pad.reshape(128,4,160,4).transpose(0,2,1,3).reshape(-1,16)
unique,index=np.unique(tiles,axis=0,return_inverse=True)
ib=max(1,(len(unique)-1).bit_length());atlas=np.zeros((1<<ib,16),np.uint8);atlas[:len(unique)]=unique
assert np.array_equal(atlas[index].reshape(128,160,4,4).transpose(0,2,1,3).reshape(512,640),pad)
(P/'index.hex').write_text(''.join(f'{v:03x}\n' for v in index))
(P/'atlas.hex').write_text(''.join(f'{v:x}\n' for v in atlas.ravel()))
assert len(unique)<=2048,'Rebudget before exceeding15/16 largeRAM including particle index'
manifest=dict(width=640,height=480,tile=4,unique_tiles=len(unique),index_bits=ib,index_entries=len(index),index_storage_bits=32768*ib,atlas_storage_bits=atlas.size*4,palette=PAL,graph='Unchanged13nodes16edges; world coordinates80/256/432, terminal512/0; rooms placed strictly outside corridor centreline',projection='x=320+(u-v)/2,y=94+(u+v)/4-z',rooms=rooms,functions=functions,visual_geometry=visual_geometry,nameplates=nameplates,static_rgb444=True,hud_entries=entries,hud_bits=65536,native_map_roms=10+atlas.size//8192)
(P/'scene.json').write_text(json.dumps(manifest,indent=2))
# Synchronous ROMs infer native memory; timing/address latency verified by pixel test.
def rom(name,bits,data,n):
 aw=(n-1).bit_length();s=f'\nmodule {name}(input clk,input [{aw-1}:0] address,output reg [{bits-1}:0] q);\nreg [{bits-1}:0] data[0:{n-1}]; /* fehdl force_ram=1, ram_style="bram" */\ninteger i;initial begin\nfor(i=0;i<{n};i=i+1)data[i]=0;\n'
 s+=''.join(f"data[{i}]={bits}'d{int(v)};\n" for i,v in enumerate(data) if v)
 return s+'end\nalways @(posedge clk) q<=data[address];\nendmodule\n'
template=(R/'tools/indoor_renderer_template.v').read_text()
template=template.replace('@INDEX_BITS@',str(ib)).replace('@ATLAS_AW@',str(ib+4))
palette='\n'.join(f"4'd{i}:palette=24'h{c:06x};" for i,c in enumerate(PAL))
template=template.replace('@PALETTE@',palette)
def native_rom(name,bits,data,n):
 # Native32Kb ROM, one synchronous read, no output register. Pack narrow pixels.
 pack=4 if bits==4 else 1;shift=2 if pack==4 else 0;words=[]
 for i in range(0,len(data),pack):words.append(sum(int(data[i+j])<<(bits*j) for j in range(min(pack,len(data)-i))))
 banks=(len(words)+2047)//2048;aw=(n-1).bit_length();ba=aw-shift-11
 s=f'\nmodule {name}(input clk,input [{aw-1}:0] address,output [{bits-1}:0] q);\n'
 s+=f'reg [{ba-1}:0] bank;always @(posedge clk)bank<=address[{aw-1}:{11+shift}];\n'
 if shift:s+='reg [1:0] subword;always @(posedge clk)subword<=address[1:0];\n'
 for k in range(banks):
  w=words[k*2048:(k+1)*2048]+[0]*max(0,(k+1)*2048-len(words))
  s+=f'wire [15:0] r{k};\nEG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),\n'
  for j in range(128):
   val=sum(w[j*16+i]<<(16*i) for i in range(16));s+=f".INIT_{j:02X}(256'h{val:064x}),\n"
  s+=f'.SRMODE("SYNC")) ram{k}(.doa(r{k}),.dia(16\'d0),.addra(address[{10+shift}:{shift}]),.bytea(1\'b0),.bytewea(1\'b0),.csa(1\'b1),.wea(1\'b0),.clka(clk),.rsta(1\'b0),.ocea(1\'b1),.dob(),.dib(16\'d0),.addrb(11\'d0),.byteb(1\'b0),.byteweb(1\'b0),.csb(1\'b0),.web(1\'b0),.clkb(clk),.rstb(1\'b0),.oceb(1\'b1));\n'
 s+='reg [15:0] selected;always @* begin case(bank)\n'+''.join(f'{ba}\'d{k}:selected=r{k};\n' for k in range(banks))+"default:selected=0;endcase end\n"
 s+=("assign q=selected >> {subword,2'b00};\n" if shift else f'assign q=selected[{bits-1}:0];\n')+'endmodule\n'
 return s
hud_bytes=np.packbits(hud.reshape(-1,8)[:,::-1],axis=1).ravel()
(P/'hud.hex').write_text(''.join(f'{v:02x}\n' for v in hud_bytes))
hudrtl=rom('refine2_hud_bytes_rom',8,hud_bytes,8192)
rtl=template+hudrtl+native_rom('indoor_index_rom',ib,index,32768)+native_rom('indoor_palette_rom',4,atlas.ravel(),atlas.size)
(R/'B_control/rtl/emergency_map_top.v').write_text(rtl)
v=R/'B_control/rtl/b_map_frame_renderer_vga.v';s=v.read_text();s=s.replace("wire [11:0] scene_x={1'b0,cx,1'b0};","wire [11:0] scene_x={2'd0,cx};").replace("wire [11:0] scene_y={3'd0,cy}+{4'd0,cy[8:1]};","wire [11:0] scene_y={3'd0,cy};")
v.write_text(s)
print(json.dumps(manifest,indent=2))
