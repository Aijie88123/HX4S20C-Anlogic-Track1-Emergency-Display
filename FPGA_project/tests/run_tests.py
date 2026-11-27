import json, pathlib, subprocess, sys, zlib, hashlib
from datetime import datetime, timezone
ROOT = pathlib.Path(__file__).resolve().parents[1]
SIM = pathlib.Path('D:/modelsim/win64')
WORK = ROOT / 'tests' / 'work'
def run(tool, args):
    p = subprocess.run([str(SIM / (tool+'.exe')), *args], cwd=ROOT/'tests', capture_output=True, text=True, errors='replace')
    (ROOT/'tests'/f'{tool}-last.log').write_text(p.stdout+p.stderr, encoding='utf-8')
    if p.returncode or '** Error' in p.stdout+p.stderr or '** Fatal' in p.stdout+p.stderr:
        raise RuntimeError(p.stdout+p.stderr)
    return p.stdout+p.stderr
if not WORK.exists(): run('vlib', ['work'])
sources = [str(x) for x in sorted((ROOT/'common').glob('*.v'))]
sources += [str(ROOT/'tests'/x) for x in ['tb_frames.v','tb_emergency_control.v']]
if (ROOT/'tests'/'tb_endpoints.v').exists():
    sources += [str(ROOT/'tests'/'tb_endpoints.v'), 'D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v']
bound = sources+[str(ROOT/'tests'/'golden_frames.hex'),str(pathlib.Path(__file__))]
snapshot = {p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in bound}
run('vlog', ['-sv', *sources])
results=[]
tops = ['tb_frames','tb_emergency_control']
if (ROOT/'tests'/'tb_endpoints.v').exists(): tops.append('tb_endpoints')
for top,delay in [('tb_frames',None),('tb_emergency_control',None)]+([('tb_endpoints',d) for d in (1,2,3)] if 'tb_endpoints' in tops else []):
    args=['-c','-novopt','-t','1ps','work.'+top]
    if top == 'tb_endpoints': args += ['work.glbl','-gRX_DELAY='+str(delay)]
    args += ['-do','onerror {quit -code 1}; run -all; quit -code 0']
    log=run('vsim',args)
    (ROOT/'tests'/f'{top}{"_"+str(delay) if delay else ""}.log').write_text(log,encoding='utf-8')
    if 'PASS:' not in log: raise RuntimeError(log)
    results.append({'test':top,'rx_delay_ns':delay,'passed':True})
def validate_stream(path, continuous=False):
    data=path.read_text().strip()
    frames=[data[i:i+144] for i in range(0,len(data),144)] if continuous else data.splitlines()
    assert frames and all(len(s)==144 for s in frames)
    for s in frames:
        packet=bytes(int(s[i+1]+s[i],16) for i in range(0,len(s),2))
        assert packet[:8]==b'\x55'*7+b'\xd5'
        frame=packet[8:]
        assert frame[:6]==b'\xff'*6 and frame[12:17]==bytes.fromhex('88b5485801')
        assert int.from_bytes(frame[-4:],'little')==zlib.crc32(frame[:-4]),'independent TX FCS failed'
    return len(frames)
results.append({'test':'independent_python_zlib_tx_fcs','passed':True,
    'core_frames':validate_stream(ROOT/'tests'/'tx_nibbles.hex',True),
    'endpoint_frames':validate_stream(ROOT/'tests'/'endpoint_tx_nibbles.hex')})
assert snapshot=={p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in bound}
report={'tests':results,'compiled_sources':snapshot,'completed_utc':datetime.now(timezone.utc).isoformat()}
(ROOT/'tests'/'results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(results))
