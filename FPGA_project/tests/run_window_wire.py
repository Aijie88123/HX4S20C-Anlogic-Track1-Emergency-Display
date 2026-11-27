from pathlib import Path
import subprocess,json,hashlib,zlib
r=Path(__file__).resolve().parents[1];t=r/'tests';m=Path('D:/modelsim/win64');o=r/'evidence/tf_coldstart_R8_20261016/wire';o.mkdir(parents=True,exist_ok=True);w=o/'work';sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_command_link.v','ethernet_mdio.v','distributed_audio.v','distributed_media.v','raster_map_transport.v','raster_map_window.v']]+[r/'B_control/rtl/audio_fft.v']+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v']]+[t/'card_spi_storage.v',t/'tb_endpoints.v',t/'tb_window_wire.v',t/'tb_tf_protocol9_boundary.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v')]
production=[r/'A_display/rtl/smart_terminal_hw_top.v',r/'B_control/rtl/dual_board_control_top.v']
a,b=[p.read_text(encoding='utf-8') for p in production]
assert 'assign net_stream_valid=pcm_stream_valid || raster_ack_valid || media_ack_valid || tf_stream_valid || particle_ack_valid;' in a
assert 'assign net_stream_out=pcm_stream_valid?pcm_stream_data:raster_ack_valid?raster_ack:media_ack_valid?{96\'d0,media_ack_net}:tf_stream_valid?tf_stream_data:particle_ack;' in a
assert 'assign tf_stream_ready=net_stream_ready&&!pcm_stream_valid&&!raster_ack_valid&&!media_ack_valid;' in a
assert 'assign media_ack_ready=net_stream_ready && !pcm_stream_valid && !raster_ack_valid;' in a
assert '.tf_stream_ready(stream_ready&&!spectrum_valid&&(!map_valid||ENABLE_RASTER))' in b
assert '.stream_ready(stream_ready&&!spectrum_valid&&!tf_valid&&!raster_valid&&(!map_valid||ENABLE_RASTER))' in b
assert 'online&&((peer[0]&&feedback[5])||animation_enabled)' in b
assert '.RAW_TF_VERSION(9)' in a and '.RAW_TF_VERSION(9)' in b
for p in f:
 if p.parent==r/'common':
  for board in ['A_display','B_control']:
   mirror=r/board/'rtl'/p.name
   assert mirror.read_bytes()==p.read_bytes(),f'Production mirror differs: {mirror}'
   production.append(mirror)
sources=[*f,*production,Path(__file__).resolve(),r/'tests/animation_v2_pixel0.hex',r/'tests/map_r7_words.hex']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')

def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',ini.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=t,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['tf_concurrent_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 observations=[];wire_counts={}
 for kind in [0,1]:
  s=run('vsim',['-c','tf_concurrent_work.tb_window_wire','tf_concurrent_work.glbl','-gKIND='+str(kind),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s;rows=[x for x in s.splitlines() if 'PASS:' in x or 'MEASURE:' in x];observations+=rows;print('\n'.join(rows),flush=True)
  for side in ['a','b']:
   src=t/f'tf_concurrent_{side}.hex';dest=o/f'kind{kind}_{side}.hex';dest.write_bytes(src.read_bytes());counts={}
   for line in src.read_text().splitlines():
    assert len(line)==144
    wire=bytes(int(line[i+1]+line[i],16) for i in range(0,len(line),2));body=wire[8:]
    assert wire[:8]==bytes.fromhex('55555555555555d5') and body[12:17]==bytes.fromhex('88b5485809')
    assert int.from_bytes(body[-4:],'little')==zlib.crc32(body[:-4])
    k=body[23];counts[k]=counts.get(k,0)+1
   wire_counts[f'{kind}_{side}']=counts
  observations.append(f'PASS: independent zlib FCS verification on captured real MAC frames kind={kind}, A={wire_counts[str(kind)+"_a"]}, B={wire_counts[str(kind)+"_b"]}')

finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(o/'result.json').write_text(json.dumps({'status':'PASS','sample_rate_hz':48000,'source_hashes':h,'observations':observations,'wire_counts':wire_counts},indent=2))
