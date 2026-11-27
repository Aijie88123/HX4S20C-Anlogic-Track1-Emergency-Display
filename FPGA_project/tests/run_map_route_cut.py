from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];o=r/'evidence/map_route_minimal_R2_20261023/control';o.mkdir(parents=True,exist_ok=True);w=o/'work';m=Path('D:/modelsim/win64');ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
f=[r/'A_display/rtl/map_received_scanout.v',r/'tests/tb_animation_kind.v',r/'tests/map_parent_reference.v',r/'tests/tb_route_boot_equivalence.v']
for tool,args in [('vlib',[w]),('vlog',['-modelsimini',ini,'-sv','-work',w,*f]),('vsim',['-modelsimini',ini,'-c','-lib',w,'tb_animation_kind','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
 p=subprocess.run([str(m/(tool+'.exe')),*[x.as_posix() if isinstance(x,Path) else x for x in args]],capture_output=True);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s
assert 'PASS:' in s
p=subprocess.run([str(m/'vsim.exe'),'-modelsimini',ini.as_posix(),'-c','-lib',w.as_posix(),'tb_route_boot_equivalence','-do','onerror {quit -code 1}; run -all; quit -code 0'],capture_output=True);s2=(p.stdout+p.stderr).decode(errors='replace');logs.append(s2);assert p.returncode==0 and '** Fatal' not in s2 and 'PASS:' in s2,s2
print(s2)
(o/'audit.log').write_text('\n'.join(logs));(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in f}},indent=2));print(s)
