from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_service_20261026/rom';E.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'B_control/rtl/maintenance_text_rom.v',R/'tests/tb_uart_rom.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=E,capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-3000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_uart_rom','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
inputs=files+[Path(__file__),E.parent/'text_expected.hex']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},native_ROM_bytes=1024,observations=[l for l in s.splitlines() if 'PASS:' in l]),indent=2));print('PASS1024native UART text-ROM bytes.')
