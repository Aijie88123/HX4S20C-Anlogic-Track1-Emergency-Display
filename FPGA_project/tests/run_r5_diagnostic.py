from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];o=r/'evidence/tf_link_R6_20261016/diagnostic';o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
rtl=r/'A_display/rtl/smart_terminal_hw_top.v';s=rtl.read_text();block=s[s.index('    // Fault pages:'):s.index('    wire [31:0] normal_pixel_data;')];assert block in (r/'tests/tb_r5_diagnostic.v').read_text()
sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['distributed_media.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_mailbox.v']]+[sd/'seg_scan.v',sd/'seg_decoder.v',r/'tests/tb_r5_diagnostic.v'];bound=f+[rtl,r/'B_control/rtl/dual_board_control_top.v',r/'B_control/rtl/b_media_storage.v'];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound};logs=[]
def run(t,args):
 p=subprocess.run([str(m/(t+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=120);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Fatal' in s or '** Error' in s:raise RuntimeError(s[-9000:])
 return s
try:
 if not w.exists():run('vlib',[w.as_posix()])
 run('vmap',['-modelsimini',ini.as_posix(),'r5_diag',w.as_posix()]);run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',w.as_posix(),*map(str,f)])
 observations=[]
 for pre in [0,1]:
  s=run('vsim',['-modelsimini',ini.as_posix(),'-c','r5_diag.tb_r5_diagnostic','-gPREPIXEL='+str(pre),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;observations.extend(l for l in s.splitlines() if 'PASS:' in l)
 print('\n'.join(observations))
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'actual_A_fault_page_block_matches':True},indent=2))
