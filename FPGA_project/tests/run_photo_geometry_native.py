from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/flip_zoom_20261024/native_geometry';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
V=R/'A_display/vendor/user_source/hdl_source';S=Path('D:/td_extract/5E781D7/sim_release/eg4')
files=[V/'include'/n for n in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]
files += [V/'SD'/n for n in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
files += [V/'IP/afifo_16_32_256.v',V/'IP/afifo_32_16_256.v',S/'eg_logic_bram.v',S/'eg_phy_sdram_2m_32.v',R/'tests/sdram_pin_model.v',R/'A_display/rtl/video_scanout_720p.v',R/'A_display/rtl/distributed_media.v',R/'tests/tb_photo_geometry_native.v',Path(__file__).resolve()]

files += [V/'include/global_def.v',V/'user_source/hdl_source/include/global_def.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in a]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'native_geometry',W]);run('vlog',['-modelsimini',I,'-sv','+define+SIMULATION','+incdir+'+(V/'include').as_posix(),'-work',W,*[p for p in files if p.suffix!='.py' and p.name!='global_def.v']])
s=run('vsim',['-modelsimini',I,'-c','native_geometry.tb_photo_geometry_native','-do','onerror {quit -code 1}; run -all; quit -code 0'])
obs=[v for v in s.splitlines() if 'PASS:' in v];assert len(obs)==39,s[-8000:]
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual encrypted SDRAM, real asynchronous FIFO, real row request/address switch and RGB888 unpack, all 720p geometry pixels across two complete seeded source images, concurrent background writes. Functional digital pin model, no analog margin measurement.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
