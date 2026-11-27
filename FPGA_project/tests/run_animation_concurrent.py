from pathlib import Path
import subprocess,json,hashlib,zlib
r=Path(__file__).resolve().parents[1];t=r/'tests';m=Path('D:/modelsim/win64');o=r/'evidence/gif_sequence_20261015/concurrent';o.mkdir(parents=True,exist_ok=True);w=o/'work';sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_command_link.v','ethernet_mdio.v','distributed_audio.v','distributed_media.v']]+[r/'B_control/rtl/audio_fft.v']+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v']]+[t/'card_spi_storage.v',t/'tb_endpoints.v',t/'tb_animation_concurrent.v',t/'tb_tf_protocol9_boundary.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v')]
production=[r/'A_display/rtl/smart_terminal_hw_top.v',r/'B_control/rtl/dual_board_control_top.v']
a,b=[p.read_text(encoding='utf-8') for p in production]
assert 'assign net_stream_valid=pcm_stream_valid || raster_ack_valid || media_ack_valid || tf_stream_valid;' in a
assert 'assign net_stream_out=pcm_stream_valid?pcm_stream_data:raster_ack_valid?raster_ack:media_ack_valid?{96\'d0,media_ack_net}:tf_stream_data;' in a
assert 'assign tf_stream_ready=net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid;' in a
assert 'assign media_ack_ready=net_stream_ready && !pcm_stream_valid && !raster_ack_valid;' in a
assert '.tf_stream_ready(stream_ready&&!spectrum_valid&&(!map_valid||ENABLE_RASTER))' in b
assert '.stream_ready(stream_ready&&!spectrum_valid&&!tf_valid&&!raster_valid&&(!map_valid||ENABLE_RASTER))' in b
assert 'online&&peer[0]&&feedback[5]' in b
assert '.RAW_TF_VERSION(9)' in a and '.RAW_TF_VERSION(9)' in b
for p in f:
 if p.parent==r/'common':
  for board in ['A_display','B_control']:
   mirror=r/board/'rtl'/p.name
   assert mirror.read_bytes()==p.read_bytes(),f'Production mirror differs: {mirror}'
   production.append(mirror)
sources=[*f,*production,Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=t,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['tf_concurrent_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 s=run('vsim',['-c','tf_concurrent_work.tb_animation_concurrent','tf_concurrent_work.glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 print('\n'.join(x for x in s.splitlines() if 'PASS:' in x),flush=True)
 boundary=run('vsim',['-c','tf_concurrent_work.tb_tf_protocol9_boundary','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in boundary
 print('\n'.join(x for x in boundary.splitlines() if 'PASS:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
observations=[x for x in (s+boundary).splitlines() if 'PASS:' in x];counts={}
for side in ['a','b']:
 src=t/f'tf_concurrent_{side}.hex';dest=o/src.name;dest.write_bytes(src.read_bytes());frames=src.read_text().splitlines();kinds={};ready_kinds={}
 for n in frames:
  assert len(n)==144,(side,len(n))
  packet=bytes(int(n[i+1]+n[i],16) for i in range(0,len(n),2));body=packet[8:]
  assert packet[:8]==bytes.fromhex('55555555555555d5') and len(body)==64
  assert body[12:17]==bytes.fromhex('88b5485809')
  assert int.from_bytes(body[-4:],'little')==zlib.crc32(body[:-4])
  kind=body[23];kinds[kind]=kinds.get(kind,0)+1
  if side=='a' and body[22]&0x20:ready_kinds[kind]=ready_kinds.get(kind,0)+1
 counts[side]={'frames':len(frames),'kinds':kinds,'kinds_with_map_ready_bit5':ready_kinds}
assert counts['a']['kinds'].get(1,0)>300 and counts['a']['kinds'].get(10,0)>=7*32 and counts['a']['kinds'].get(5,0)>100
assert counts['b']['kinds'].get(2,0)>=2 and counts['b']['kinds'].get(4,0)>100 and counts['b']['kinds'].get(11,0)>=7*32
ready=counts['a']['kinds_with_map_ready_bit5'];assert ready.get(1,0)>0 and ready.get(5,0)>=100 and ready.get(10,0)>=32
observations.append(f'PASS: independent zlib checks both v9 MAC directions, frames A={counts["a"]["frames"]}, B={counts["b"]["frames"]}; packet classes={counts}')
print(observations[-1],flush=True)
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'Sources changed during test; rerun final source'
(o/'result.json').write_text(json.dumps({'status':'PASS','sample_rate_hz':48000,'sector_retry_ms':2,'bounded_image_pixels':600,'arbitration_checked_against_production':True,'source_hashes':h,'observations':observations,'wire_counts':counts},indent=2))
