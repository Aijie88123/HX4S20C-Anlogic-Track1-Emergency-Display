"""Check v4 Ethernet TX captures independently of the RTL CRC implementation."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import zlib

ROOT = Path(__file__).resolve().parents[1]
counts, hashes = {}, {}
for board in ['a', 'b']:
    capture = ROOT / 'tests' / f'map_endpoint_{board}_nibbles.hex'
    hashes[capture.name] = hashlib.sha256(capture.read_bytes()).hexdigest().upper()
    counter = Counter()
    for nibbles in capture.read_text(encoding='ascii').splitlines():
        assert len(nibbles) == 144
        wire = bytes(int(nibbles[i + 1] + nibbles[i], 16)
                     for i in range(0, len(nibbles), 2))
        assert wire[:8] == bytes.fromhex('55555555555555d5')
        frame = wire[8:]
        assert len(frame) == 64
        assert frame[12:17] == bytes.fromhex('88b5485804')
        assert int.from_bytes(frame[-4:], 'little') == zlib.crc32(frame[:-4])
        kind = frame[23]
        assert kind in ([0, 1] if board == 'a' else [0, 2, 3])
        counter[kind] += 1
        if kind == 1:
            assert frame[39:60] == bytes(21)
        elif kind == 3:
            scene = int.from_bytes(frame[23:51], 'little')
            assert scene >> 188 == 0 and frame[51:60] == bytes(9)
            assert (scene >> 14) & 3 == 0
            assert (scene >> 12) & 3 in [0, 1, 2]
            assert (scene >> 80) & 4095 in [3072, 2458, 2048]
            route, closed = (scene >> 92) & 65535, (scene >> 124) & 65535
            assert route & closed == 0
            if scene & (1 << 9):
                assert route == 0
    counts[board] = dict(counter)
assert counts['a'][1] == 1536
assert counts['b'][2] == 8 and counts['b'][3] > 0
report = {'status': 'PASS',
          'checker': 'independent Python zlib over v4 TX captures, RX skew=3ns',
          'frames_by_kind': counts, 'captures': hashes,
          'checker_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper()}
output = ROOT / 'evidence/zoom_routing_20261012/wire-capture-check.json'
output.write_text(json.dumps(report, indent=2), encoding='utf-8')
print('PASS: independent v4 frame lengths, headers, CRC32, padding, scene flags, '
      'open routes and concurrent audio counts.', counts)
