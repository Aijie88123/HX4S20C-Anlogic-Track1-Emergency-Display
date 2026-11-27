from pathlib import Path
import subprocess,hashlib,json,zlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/media_offload_20261013/controls_wire';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[r/'common'/n for n in ['ethernet_frame_tx.v','ethernet_frame_rx.v']]+[r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'B_control/rtl/dual_board_control_top.v',r/'tests/tb_media_carousel.v',r/'tests/tb_media_mac.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=180);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s)
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vlog',['-sv','-work',str(w),*map(str,f)])
 for top in ['tb_media_carousel','tb_media_mac']:
  s=run('vsim',['-c','-novopt','-lib',str(w),top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;print('\n'.join(l for l in s.splitlines() if 'PASS:' in l))
finally:(o/'audit.log').write_text('\n'.join(logs))
s=(r/'tests/media_tx_nibbles.hex').read_text().strip();assert len(s)==12*144
for j in range(12):
 n=s[j*144:(j+1)*144];raw=bytes(int(n[k+1]+n[k],16) for k in range(0,144,2));body=raw[8:]
 assert body[16]==5 and int.from_bytes(body[60:64],'little')==zlib.crc32(body[:60])
print('PASS: independent Python zlib FCS verification of twelve protocol-v5 media/map/spectrum/status frames')
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'independent_FCS':True},indent=2))
