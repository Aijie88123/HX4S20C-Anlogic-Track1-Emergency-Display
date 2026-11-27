"""Production SDRAM/FIFO/RGB888/720p scanout regression for the current project.

Three complete frames: concurrent writes during the first frames, then the same
photo continuously scanned with writes quiet. The second top also injects 300us
of midframe upstream starvation and random short supply stalls; unready pixels
must stay black and every ready pixel must match independent bilinear math.
"""
from pathlib import Path
import subprocess
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/scan_trace_20261024/qualified_scanout'
MODELSIM = Path('D:/modelsim/win64')
VENDOR = ROOT / 'A_display/vendor/user_source/hdl_source'
TD_SIM = Path('D:/td_extract/5E781D7/sim_release/eg4')
OUT.mkdir(parents=True, exist_ok=True)
INI = OUT / 'modelsim.ini'
INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n', encoding='utf-8')
WORK = OUT / 'work'

FILES = [VENDOR / 'include' / name for name in ['sdr_init_ref.enc.v', 'sdr_wrrd.enc.v', 'sdr_as_ram.enc.v']]
FILES += [VENDOR / 'SD' / name for name in ['sdram.v', 'frame_fifo_read.v', 'frame_fifo_write.v', 'frame_read_write.v']]
FILES += [VENDOR / 'IP/afifo_16_32_256.v', VENDOR / 'IP/afifo_32_16_256.v', TD_SIM / 'eg_logic_bram.v', TD_SIM / 'eg_phy_sdram_2m_32.v',
          ROOT / 'tests/sdram_pin_model.v', ROOT / 'A_display/rtl/distributed_media.v', ROOT / 'A_display/rtl/video_scanout_720p.v',
          ROOT / 'A_display/rtl/smart_terminal_hw_top.v', ROOT / 'tests/tb_scan_qualified.v', ROOT / 'tests/tb_scan_qualified_starve.v']
SOURCES = FILES + [VENDOR / 'include/global_def.v', VENDOR / 'user_source/hdl_source/include/global_def.v', Path(__file__).resolve()]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
INITIAL_HASHES = {path.as_posix(): sha(path) for path in SOURCES}
LOGS = []

def run(tool, args):
    if tool != 'vlib':
        args = ['-modelsimini', INI.as_posix(), *args]
    command = [str(MODELSIM / (tool + '.exe')), *[value.as_posix() if isinstance(value, Path) else str(value) for value in args]]
    process = subprocess.run(command, cwd=ROOT / 'tests', capture_output=True, timeout=600)
    output = (process.stdout + process.stderr).decode(errors='replace')
    LOGS.append(output)
    (OUT / 'audit.log').write_text('\n'.join(LOGS), encoding='utf-8')
    if process.returncode or '** Error' in output or '** Fatal' in output:
        raise RuntimeError(output[-10000:])
    return output

REPORT = {'status': 'FAIL', 'project_root': ROOT.as_posix(), 'source_hashes': INITIAL_HASHES,
          'physical_silicon_test': False, 'pin_model': 'independent functional BL4/CL3, no analog fault model',
          'scope': 'Encrypted SDRAM + real asynchronous FIFOs + production RGB888 unpack + production 720p bilinear scanout; full-photo RGB correctness with background dynamic-region writes and final quiet static frame; independent starvation case must be exact or black.',
          'observations': []}
try:
    if not WORK.exists():
        run('vlib', [WORK])
    run('vmap', ['sdram_stable_scanout', WORK])
    run('vlog', ['-sv', '+define+SIMULATION', '+incdir+' + (VENDOR / 'include').as_posix(), '-work', WORK, *FILES])
    for top in ['tb_scan_qualified', 'tb_scan_qualified_starve']:
        output = run('vsim', ['-c', 'sdram_stable_scanout.' + top, '-do', 'onerror {quit -code 1}; run -all; quit -code 0'])
        assert 'PASS:' in output, output[-10000:]
        observations = [line for line in output.splitlines() if 'PASS:' in line or 'TRACE:' in line]
        REPORT['observations'].extend(observations)
        print('\n'.join(observations), flush=True)
    assert INITIAL_HASHES == {path.as_posix(): sha(path) for path in SOURCES}, 'Source changed during verification'
    REPORT['status'] = 'PASS'
except Exception as error:
    REPORT['error'] = str(error)
    raise
finally:
    (OUT / 'result.json').write_text(json.dumps(REPORT, indent=2), encoding='utf-8')

