"""Independent FAT32 disk and normalized-pixel reference from saved TF assets."""
from pathlib import Path
import hashlib, json, random, struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/storage_recovery_vectors'
OUT.mkdir(exist_ok=True)
FAT_BASE, FAT_SECTORS, DATA_BASE, SPC, CLUSTERS = 2, 512, 514, 8, 65525
NAMES = ['05.BMP', '06.BMP', '01.BMP', '02.BMP', '03.BMP', '04.BMP']

def create(small):
    disk = {}
    def sec(lba): return disk.setdefault(lba, bytearray(512))
    mbr = sec(0)
    mbr[450] = 0x0c
    struct.pack_into('<II', mbr, 454, 1, DATA_BASE-1+CLUSTERS*SPC)
    mbr[510:] = b'\x55\xaa'
    bpb = sec(1)
    bpb[:11] = b'\xeb\x58\x90MSDOS5.0'
    struct.pack_into('<H', bpb, 11, 512)
    bpb[13] = SPC
    struct.pack_into('<H', bpb, 14, 1)
    bpb[16], bpb[21] = 1, 0xf8
    struct.pack_into('<I', bpb, 32, DATA_BASE-1+CLUSTERS*SPC)
    struct.pack_into('<I', bpb, 36, FAT_SECTORS)
    struct.pack_into('<I', bpb, 44, 2)
    bpb[510:] = b'\x55\xaa'
    fat = [0] * (CLUSTERS+2)
    fat[:3] = [0x0ffffff8, 0x0fffffff, 0x0fffffff]
    available = list(range(3, 1592))
    random.Random(20261014).shuffle(available)
    starts, dimensions, sources, metadata = [], [], [], []
    prefix = 'small' if small else 'full'
    with (OUT / (prefix+'_expected.hex')).open('w', encoding='ascii') as ref:
        for role, name in enumerate(NAMES):
            asset = ROOT / 'A_display/assets/tf_card_six' / name
            if small:
                w, h = 640, 1
                stride = w*3
                raw = bytearray(54+stride)
                struct.pack_into('<2sIHHI', raw, 0, b'BM', len(raw), 0, 0, 54)
                struct.pack_into('<IiiHHIIiiII', raw, 14, 40, w, h, 1, 24, 0, stride, 2835, 2835, 0, 0)
                for x in range(w): raw[54+x*3:57+x*3] = bytes([(x+role)&255, role*19, (x^role)&255])
            else:
                raw = bytearray(asset.read_bytes())
                w, h = struct.unpack_from('<ii', raw, 18)
                assert w>0 and h>0 and struct.unpack_from('<HI', raw, 28)==(24, 0)
                stride = (w*3+3)&~3
            offset = struct.unpack_from('<I', raw, 10)[0]
            dimensions.append((h<<16)|w)
            sources.append({'name': name, 'width': w, 'height': h, 'sha256': hashlib.sha256(raw).hexdigest()})
            # Source rows are bottom-up. The RAM writer reverses the 480
            # normalized rows; horizontal reduction has a two-sample mean.
            for out_y in range(480):
                sy = (479-out_y)*h//480
                for out_x in range(640):
                    sx = out_x*w//640
                    at = offset+sy*stride+sx*3
                    b, g, r = raw[at:at+3]
                    if w>640 and sx:
                        pb, pg, pr = raw[at-3:at]
                        b, g, r = (b+pb+1)//2, (g+pg+1)//2, (r+pr+1)//2
                    ref.write(f'{(r<<24)|(g<<16)|(b<<8):08x}\n')
            count = (len(raw)+SPC*512-1)//(SPC*512)
            chain = [available.pop() for _ in range(count)]
            starts.append(DATA_BASE+(chain[0]-2)*SPC)
            for j, c in enumerate(chain):
                fat[c] = chain[j+1] if j+1<len(chain) else 0x0fffffff
                for off in range(SPC):
                    start = (j*SPC+off)*512
                    sec(DATA_BASE+(c-2)*SPC+off)[:] = raw[start:start+512].ljust(512, b'\0')
            metadata.append((chain[0], len(raw)))
    root = sec(DATA_BASE)
    for i, role in enumerate([5, 2, 0, 4, 3, 1]):
        name = NAMES[role].split('.')[0].encode().ljust(8)+b'BMP'
        root[i*32:i*32+11] = name
        root[i*32+11] = 0x20
        cluster, size = metadata[role]
        struct.pack_into('<H', root, i*32+20, cluster>>16)
        struct.pack_into('<H', root, i*32+26, cluster&65535)
        struct.pack_into('<I', root, i*32+28, size)
    for page in range(FAT_SECTORS):
        d = sec(FAT_BASE+page)
        for i in range(128):
            idx = page*128+i
            if idx<len(fat): struct.pack_into('<I', d, i*4, fat[idx])
    with (OUT / (prefix+'_disk.hex')).open('w', encoding='ascii') as f:
        for lba, d in sorted(disk.items()):
            f.write(f'@{lba*512:08x}\n')
            f.write('\n'.join(f'{value:02x}' for value in d)+'\n')
    for name, values in [('starts', starts), ('sizes', dimensions)]:
        (OUT / (prefix+'_'+name+'.hex')).write_text('\n'.join(f'{v:08x}' for v in values)+'\n', encoding='ascii')
    (OUT / (prefix+'_manifest.json')).write_text(json.dumps({'status': 'generated', 'source_assets': sources,
       'fat32_cluster_count': CLUSTERS, 'sectors_per_cluster': SPC, 'fragmented': True,
       'pixels_independently_derived': 1843200, 'highest_materialized_lba': max(disk)}, indent=2), encoding='utf-8')

if __name__ == '__main__':
    create(True)
    create(False)
    print('Generated full saved six-picture FAT32 fixture (800x600 06), independent 1,843,200-pixel reference and small fault-recovery fixture.')
