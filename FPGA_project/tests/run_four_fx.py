"""Production transition selection regression; self-contained frozen parent RTL."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/flip_zoom_20261024/selection'
REFERENCE = ROOT / 'tests/reference_four_fx'
MODELSIM = Path('D:/modelsim/win64')
OUT.mkdir(parents=True, exist_ok=True)
WORK = OUT / 'work'
INI = OUT / 'modelsim.ini'
INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n', encoding='utf-8')
LOGS = []

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(tool, args):
    cmd = [str(MODELSIM / (tool + '.exe'))] + [a.as_posix() if isinstance(a, Path) else str(a) for a in args]
    proc = subprocess.run(cmd, cwd=ROOT / 'tests', capture_output=True, timeout=600)
    output = (proc.stdout + proc.stderr).decode(errors='replace')
    LOGS.append(output)
    if proc.returncode or '** Error' in output or '** Fatal' in output:
        raise RuntimeError(output[-10000:])
    return output

provenance_file = REFERENCE / 'parent_provenance.json'
provenance = json.loads(provenance_file.read_text(encoding='utf-8'))
# Verify references from the bundled exact original bytes. Replay does not read
# the historical parent directory or regenerate references from external files.
for name, expected_hash in provenance['bundled_reference_hashes'].items():
    assert sha(REFERENCE / name) == expected_hash, f'Frozen parent reference changed: {name}'
reference_files = []
for name in ['smart_terminal_overlay_pipelined.v', 'transition_fx.v']:
    original = REFERENCE / ('parent_original_' + name)
    expected_hash = next(value for path, value in provenance['parent_original_source_hashes'].items() if path.endswith('/' + name))
    assert sha(original) == expected_hash, f'Captured original hash differs: {name}'
    source = original.read_text(encoding='utf-8-sig')
    for before, after in provenance['renaming_map'].items():
        source = re.sub(r'\b' + before + r'\b', after, source)
    reference = REFERENCE / ('parent_reference_' + name)
    assert reference.read_text(encoding='utf-8') == source, f'Reference contains changes beyond module renaming: {name}'
    reference_files.append(reference)

names = ['alpha_blend.v', 'audio_bars_overlay.v', 'audio_envelope.v', 'audio_fft.v',
         'audio_spectrum_overlay.v', 'chinese_title_overlay.v', 'chinese_title_rom.v',
         'text_overlay_8x8.v', 'transition_fx.v', 'video_palette_lookup.v',
         'smart_terminal_overlay.v', 'smart_terminal_overlay_pipelined.v', 'video_scanout_720p.v']
files = [ROOT / 'A_display/rtl' / name for name in names] + reference_files + [ROOT / 'tests/tb_four_fx.v']
initial_hashes = {p.as_posix(): sha(p) for p in files}
for path, expected_hash in provenance['shared_parent_dependencies'].items():
    local = ROOT / 'A_display/rtl' / Path(path).name
    # This test drives RGB directly into both real compositors. Scanout is
    # compiled and source-bound, but no scanout instance is elaborated here;
    # its permitted changes are verified by the geometry/native/compat tests.
    # The new text parameter defaults to the legacy labels in both instances.
    # Its fast/legacy glyph values are separately asserted by run_fast_carousel.
    if local.name in ['video_scanout_720p.v', 'text_overlay_8x8.v']:
        continue
    assert sha(local) == expected_hash, f'Unbound shared dependency differs: {local.name}'
support_files = [provenance_file] + [REFERENCE / name for name in provenance['bundled_reference_hashes'] if name.startswith('parent_original_')]
support_hashes = {p.as_posix(): sha(p) for p in support_files}
runner = Path(__file__).resolve()
report = {
    'status': 'FAIL',
    'source_hashes': initial_hashes,
    'support_hashes': support_hashes,
    'runner_hashes': {runner.as_posix(): sha(runner)},
    'parent_provenance': provenance,
    'scope': 'Real compositor normal transition selection; full pipeline parent equivalence for retained modes; independent /255 emergency pixels for all 16 switch states with particle not ready; original ready-particle emergency priority separately preserved.',
    'observations': [],
}
try:
    if not WORK.exists():
        run('vlib', [WORK])
    run('vmap', ['-modelsimini', INI, 'transition_trim', WORK])
    run('vlog', ['-modelsimini', INI, '-sv', '-work', WORK, *files])
    output = run('vsim', ['-modelsimini', INI, '-c', 'transition_trim.tb_four_fx',
                          '-do', 'onerror {quit -code 1}; run -all; quit -code 0'])
    observations = [line for line in output.splitlines() if 'PASS:' in line]
    assert len(observations) == 4, output[-10000:]
    assert initial_hashes == {p.as_posix(): sha(p) for p in files}, 'Source changed during regression'
    assert support_hashes == {p.as_posix(): sha(p) for p in support_files}, 'Frozen reference inputs changed during regression'
    report.update(status='PASS', observations=observations)
    print('\n'.join(observations), flush=True)
except Exception as exc:
    report['error'] = str(exc)
    raise
finally:
    (OUT / 'audit.log').write_text('\n'.join(LOGS), encoding='utf-8')
    (OUT / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
