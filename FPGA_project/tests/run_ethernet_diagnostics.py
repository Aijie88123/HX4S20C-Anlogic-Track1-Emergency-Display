from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];o=r/'evidence/eth_diag_R11_20261016/diagnostics';o.mkdir(parents=True,exist_ok=True)
m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[r/'A_display/rtl/ethernet_link_diagnostics.v',r/'A_display/rtl/ethernet_mailbox.v',r/'tests/tb_ethernet_diagnostics.v'];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',ini,*args]
 p=subprocess.run([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=r/'tests',capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not w.exists():run('vlib',[w])
 run('vlog',['-sv','-work',w,*f]);s=run('vsim',['-c','-lib',w,'tb_ethernet_diagnostics','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations=[v for v in s.splitlines() if 'PASS:' in v];print('\n'.join(observations),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'limits':'RX_CTL count is sampled activity, not a CRC-qualified packet count; valid packet count increments only on production peer_packet.'},indent=2))
