"""Verify the stage-4 B button, scheduler, real Ethernet and unchanged A OSD."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, subprocess, sys, importlib.util, shutil

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / 'tests'
OUT = ROOT / 'evidence/period_button_20261013/tests'
SIM = Path('D:/modelsim/win64')
OUT.mkdir(parents=True, exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def run(tool, args, library):
    result = subprocess.run([str(SIM / (tool + '.exe')), *args], cwd=TEST,
                            capture_output=True, timeout=300)
    log = (result.stdout + result.stderr).decode('utf-8', errors='replace')
    if result.returncode or '** Error' in log or '** Fatal' in log:
        (OUT / (library + '-failure.log')).write_text(log, encoding='utf-8')
        raise RuntimeError(log)
    return log

sources = [ROOT / 'B_control/rtl/dual_board_control_top.v',
           ROOT / 'B_control/rtl/key_remove_shakes.v',
           ROOT / 'B_control/rtl/audio_fft.v',
           *sorted((ROOT / 'common').glob('*.v')),
           ROOT / 'A_display/rtl/text_overlay_8x8.v',
           ROOT / 'A_display/tb/text_overlay_link_baseline.v',
           TEST / 'tb_endpoints.v',
           Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v'),
           TEST / 'period_button_link_models.v',
           TEST / 'tb_period_button.v', TEST / 'tb_period_button_top.v',
           TEST / 'tb_period_button_wire.v', Path(__file__)]

def snapshot():
    return {p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p): sha(p)
            for p in sources}

original = snapshot()
observations = []
for library, benches, models in [
    ('controls', ['tb_period_button', 'tb_period_button_top'],
     [TEST / 'period_button_link_models.v']),
    ('wire', ['tb_period_button_wire'],
     [*sorted((ROOT / 'common').glob('*.v')), TEST / 'tb_endpoints.v',
      Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v')])]:
    work = OUT / library / 'work'
    work.parent.mkdir(exist_ok=True)
    if not work.exists():
        run('vlib', [str(work)], library)
    files = [ROOT / 'B_control/rtl/dual_board_control_top.v',
             ROOT / 'B_control/rtl/key_remove_shakes.v',
             ROOT / 'B_control/rtl/audio_fft.v',
             *([ROOT / 'common/distributed_map.v', ROOT / 'common/distributed_audio.v',
                ROOT / 'common/ethernet_mailbox.v'] if library == 'controls' else []),
             ROOT / 'A_display/rtl/text_overlay_8x8.v',
             ROOT / 'A_display/tb/text_overlay_link_baseline.v', *models]
    log = run('vlog', ['-work', str(work), *map(str, files)], library)
    log += run('vlog', ['-sv', '-work', str(work),
                        *[str(TEST / (top + '.v')) for top in benches]], library)
    (work.parent / 'compile.log').write_text(log, encoding='utf-8')
    for top in benches:
        for skew in ([1, 2, 3] if library == 'wire' else [None]):
            args = ['-c', '-novopt', '-t', '1ps', '-lib', str(work), top]
            if skew is not None:
                args += ['glbl', '-gRX_DELAY=' + str(skew)]
            log = run('vsim', args + ['-do', 'onerror {quit -code 1}; run -all; quit -code 0'], library)
            (work.parent / (top + str(skew) + '.log')).write_text(log, encoding='utf-8')
            assert 'PASS:' in log, log
            rows = [line for line in log.splitlines() if 'PASS:' in line]
            observations.extend(rows)
            print('\n'.join(rows), flush=True)
assert original == snapshot(), 'Sources changed during simulation'
(OUT / 'result.json').write_text(json.dumps({
    'status': 'PASS', 'observations': observations, 'compiled_sources': original,
    'completed_utc': datetime.now(timezone.utc).isoformat(),
    'model_boundaries': 'Control test scales elapsed time and models PLL/peer telemetry; wire tests use real v4 MAC, CRC, DDR, MDIO and mailbox with 1/2/3ns skews; A OSD pixels are compared to frozen font reference.'
}, indent=2), encoding='utf-8')

# The existing complete FAT/BMP/scaler bench checks actual visible intervals
# and every one of 307200 output pixels. Select periods using button pulses.
spec = importlib.util.spec_from_file_location('chain', ROOT / 'A_display/sim/run_chain_regression.py')
chain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chain)
chain.tests['button_carousel_real'] = ('tb_button_carousel_real',
    [*chain.tests['uniform'][1][:-1], ROOT / 'B_control/rtl/dual_board_control_top.v',
     TEST / 'tb_button_carousel_real.v'])
assert chain.run('button_carousel_real'), 'Button-selected FAT/BMP display test failed'
for name in ['result.json', 'audit.log']:
    target = OUT / 'button_carousel_real' / name
    target.parent.mkdir(exist_ok=True)
    shutil.copy2(chain.OUT / 'button_carousel_real' / name, target)
