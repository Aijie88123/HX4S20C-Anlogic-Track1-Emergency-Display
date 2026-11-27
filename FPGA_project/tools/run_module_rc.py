from pathlib import Path
import subprocess,json,hashlib,math
R=Path(__file__).resolve().parents[1];E=R/'evidence/modulefit_20261030/rc';E.mkdir(exist_ok=True);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
files=[R/'B_control/rtl/onewire_slot.v',R/'B_control/rtl/ds18b20_master.v',R/'tests/ds18b20_rc_model.sv',R/'tests/tb_ds18b20_module_rc.sv'];bound=files+[Path(__file__)];hashes={p.relative_to(R).as_posix():h(p) for p in bound}
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in args]],cwd=E,capture_output=True,timeout=600);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-6000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);cases=[]
for clk,c in [(1000000,25),(1000000,100),(1000000,220),(1000000,470),(25000000,470)]:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_ds18b20_module_rc','-GCLK_HZ='+str(clk),'-GC_PF='+str(c),'-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in s
 cases.append(dict(clk_hz=clk,r_ohm=10000,c_pf=c,rise_ns=math.ceil(10000*c*0.001*math.log(5)),observations=[l for l in s.splitlines() if 'PASS:' in l]));print(cases[-1],flush=True)
assert hashes=={p.relative_to(R).as_posix():h(p) for p in bound}
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=hashes,cases=cases,physical_test=False,scope='Delayed weak pullup model R10k with ideal instantaneous low, conservative selected80% threshold and assumed total C25/100/220/470pF. Device model sees bus edges; slave guard extended through RC rise, no DUT state access. True760ms wait. Not SPICE, actual cable capacitance/threshold or physical electrical validation.'),indent=2))
