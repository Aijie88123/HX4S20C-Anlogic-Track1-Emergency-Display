from pathlib import Path
import hashlib
import json
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
SIM = Path('D:/modelsim/win64')
TEST = ROOT/'tests'
LIBRARY = TEST/'work_b_role'
SOURCES = [ROOT/'B_control/rtl/dual_board_control_top.v',
           ROOT/'B_control/rtl/key_remove_shakes.v', TEST/'tb_b_role_display.v',
           ROOT/'B_control/rtl/distributed_audio.v',ROOT/'B_control/rtl/audio_fft.v',ROOT/'B_control/rtl/distributed_map.v',ROOT/'B_control/rtl/ethernet_mailbox.v',Path(__file__)]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

snapshot = {p.relative_to(ROOT).as_posix(): sha(p) for p in SOURCES}

def run(name, args):
    result = subprocess.run([str(SIM/(name+'.exe')), *args], cwd=TEST,
                            capture_output=True, text=True, errors='replace')
    log = result.stdout+result.stderr
    (TEST/(name+'-b-role-last.log')).write_text(log, encoding='utf-8')
    if result.returncode or '** Error' in log or '** Fatal' in log:
        raise RuntimeError(log)
    return log

if not LIBRARY.exists():
    run('vlib', [str(LIBRARY)])
run('vlog', ['-work', str(LIBRARY), *map(str, SOURCES[:2]+SOURCES[3:7])])
run('vlog', ['-sv', '-work', str(LIBRARY), str(SOURCES[2])])
log = run('vsim', ['-c', '-novopt', '-t', '1ps', '-lib', str(LIBRARY), 'tb_b_role_display',
                  '-do', 'onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in log, log
assert snapshot == {p.relative_to(ROOT).as_posix(): sha(p) for p in SOURCES}
report = {'status': 'PASS', 'completed_utc': datetime.now(timezone.utc).isoformat(),
          'compiled_sources': snapshot, 'observations': [line for line in log.splitlines() if 'PASS:' in line],
          'model_boundaries': 'Real B top and key debouncers; controllable PLL/link models. Actual Ethernet endpoints verified by run_tests.py.'}
(TEST/'b_role_display_results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
