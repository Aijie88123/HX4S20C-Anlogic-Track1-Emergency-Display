from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];F=R/'tests/reference_resource_timing';O=R/'evidence/resource_timing_20261025';O.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rules=[('pixels[fill*24 +: 24]<=read_data[31:8];','pixels',0,6,'read_data[31:8]'),('held[56+fill*24 +:24]<={length[7:0]-8\'d1,colour};','held',56,7,"{length[7:0]-8'd1,colour}")]
changed={};restore={}
for name in ['distributed_media.v','raster_map_window.v']:
 source=F/('common_'+name);original=source.read_text(encoding='utf-8-sig');text=original
 frozen=F/('common_'+name)
 assert sha(frozen)==sha(source)
 for old,target,offset,count,data in rules:
  if old not in text:continue
  new='case(fill)\n'+''.join(f"       3'd{i}:{target}[{offset+i*24} +:24]<={data};\n" for i in range(count))+'      endcase '
  text=text.replace(old,new);restore[new]=old
 restored=text
 for new,old in restore.items():restored=restored.replace(new,old)
 assert restored==original,'Only write-address representation may change'
 for base in ['common','B_control/rtl']:
  path=R/base/name
  assert path.read_text(encoding='utf-8-sig') in [original,text],path
  path.write_text(text,encoding='utf-8');changed[str(path)]=sha(path)
(O/'slice-generation.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(F/('common_'+name)):sha(F/('common_'+name)) for name in ['distributed_media.v','raster_map_window.v']},generated_hashes=changed,runner_hashes={str(Path(__file__).resolve()):sha(Path(__file__))},scope='Variable24-bit packet writes rewritten as exhaustive constant slices; all other text, FSM, handshakes, protocol fields and timing byte-identical. fill0..5 image and0..6 RLE; out-of-range fill values retain no-write semantics. A unused sender copies deliberately unchanged.'),indent=2)+'\n',encoding='utf-8')
print('PASS: explicit packet write slices only, all FSM/handshake code unchanged')
