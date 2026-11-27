"""Generate a world-anchored material/depth mask, never a colour frame.

Existing FPGA geometry, route search, camera, markers and native pixel raster
remain live. This small ROM decorates those surfaces with anonymous architecture.
"""
from pathlib import Path
import json, hashlib
import numpy as np
from PIL import Image

R = Path(__file__).resolve().parents[1]
P = R / 'assets/map_architecture'
P.mkdir(parents=True, exist_ok=True)
SX0, SY0, W, H, STEP = 128, 144, 512, 256, 2
Y, X = np.indices((H, W))
SX, SY = SX0 + STEP * X + 1, SY0 + STEP * Y + 1
GU, GV = (SX + 2 * SY - 940) // 2, (2 * SY - SX + 340) // 2
depth = np.full((H, W), -1.0)
material = np.zeros((H, W), dtype=np.uint8)
feature_ids = np.zeros((H, W), dtype=np.uint16)
features = []
PALETTE = [0x000000, 0x334455, 0xCCDDEE, 0xAA9977,
           0x88BBDD, 0x779966, 0x778899, 0xEEEECC]
BUILDINGS = [(112, 112, 208, 196, 52), (304, 112, 400, 196, 56),
             (112, 304, 208, 388, 50), (304, 304, 400, 388, 58),
             (302, 20, 398, 54, 30), (20, 302, 54, 386, 38),
             (458, 304, 492, 388, 34)]

def box(name, u0, v0, u1, v1, z0, z1, top=6, side=1, opaque=True, base=False):
    t = np.minimum(np.minimum(z1, u1-GU), v1-GV)
    hit = (t >= z0) & (GU+t >= u0) & (GV+t >= v0) & (t >= depth)
    depth[hit] = t[hit]
    if not base:
        ident = len(features)+1
        features.append({'id': ident, 'kind': name, 'bounds': [u0, v0, u1, v1, z0, z1],
                         'top': top, 'side': side, 'blocks_ground_route': opaque})
        c = np.where(t == z1, top, side) + (8 if opaque else 0)
        material[hit] = c[hit]
        feature_ids[hit] = ident

# Seed visibility with the exact seven existing procedural building footprints.
for u0, v0, u1, v1, z in BUILDINGS:
    box('base', u0, v0, u1, v1, 0, z, base=True)

for i, (u0, v0, u1, v1, z) in enumerate(BUILDINGS):
    width, length = u1-u0, v1-v0
    # Small rooftop mechanical penthouse and skylights, clear of building labels.
    if width > 60 and length > 60:
        box('roof_service_room', u0+8, v0+7, u0+30, v0+24, z, z+9, 2, 6)
        box('roof_service_cap', u0+6, v0+5, u0+32, v0+26, z+9, z+11, 6, 2)
        for k in range(3):
            q = u0+48+k*11
            box('skylight_frame', q, v0+10, q+8, v0+30, z, z+3, 2, 6)
            box('skylight_glass', q+1, v0+12, q+7, v0+28, z+3, z+4, 4, 4)
    else:
        box('roof_vent', u0+7, v0+10, min(u0+21, u1-5), v0+28, z, z+7, 2, 6)
    # Both visible facades receive subtle horizontal floor bands.
    for h in range(15, z-2, 16):
        box('floor_band_front', u0+3, v1+0.5, u1-3, v1+1.5, h, h+2, 6, 6)
    # Recessed glazed entrance, projecting canopy and three actual stair tiers.
    mid = (u0+u1)/2
    half = min(15, width/3)
    box('entrance_recess', mid-half, v1+0.5, mid+half, v1+2.5, 0, 24, 1, 1)
    box('entrance_glass', mid-half+3, v1+2.5, mid+half-3, v1+3.5, 3, 21, 4, 4)
    box('entrance_mullion', mid-1, v1+3.5, mid+1, v1+4.5, 3, 21, 2, 2)
    box('entrance_canopy', mid-half-3, v1, mid+half+3, v1+13, 24, 27, 2, 6)
    for j in range(3):
        box('entrance_steps', mid-half-3, v1+3+j*5, mid+half+3, v1+8+j*5,
            0, 6-2*j, 2 if j%2 == 0 else 6, 6)

def gate(name, u, v, axis, height, main=False):
    # Axis0 spans U, axis1 spans V. Opening stays clear of the existing road.
    spread = 40 if main else 34
    def g(kind, a0, b0, a1, b1, z0, z1, top, side):
        if axis == 0:
            box(name+'_'+kind, u+a0, v+b0, u+a1, v+b1, z0, z1, top, side)
        else:
            box(name+'_'+kind, u+b0, v+a0, u+b1, v+a1, z0, z1, top, side)
    for a in [-spread, spread-10]:
        g('pillar', a, -6, a+10, 6, 0, height, 2, 6)
        g('plinth', a-3, -9, a+13, 9, 0, 5, 2, 6)
        g('cap', a-2, -8, a+12, 8, height, height+4, 3, 2)
    g('beam', -spread, -5, spread, 5, height-6, height+1, 2, 6)
    g('blank_fascia', -spread+13, 5, spread-13, 7, height-5, height-1, 4, 4)
    # Short fence wings do not close any route or alter the graph.
    for a0, a1 in [(-spread-46, -spread-3), (spread+3, spread+46)]:
        g('fence_base', a0, -2, a1, 2, 0, 4, 2, 6)
        for a in np.arange(a0, a1, 10):
            g('fence_post', float(a), -2, float(a)+3, 2, 4, 12, 6, 6)

gate('south_main_gate', 256, 510, 0, 44, True)
gate('east_gate', 510, 256, 1, 36)
gate('north_gate', 256, 2, 0, 32)
gate('west_gate', 2, 256, 1, 32)

# Flush ground paint; all dynamic route arrows remain above it.
for axis, fixed, start in [(0, 256, 460), (1, 256, 460), (0, 256, 28), (1, 256, 28)]:
    for k in range(5):
        q = start+k*7
        if axis == 0:
            box('crosswalk', fixed-15, q, fixed+15, q+3, 0, 0.2, 7, 7, False)
        else:
            box('crosswalk', q, fixed-15, q+3, fixed+15, 0, 0.2, 7, 7, False)

for u, v in [(178, 450), (330, 450), (210, 210), (450, 200), (38, 180), (176, 32)]:
    box('planter_curbs', u-9, v-15, u+9, v+15, 0, 4, 2, 6)
    box('planter_shrubs', u-6, v-12, u+6, v+12, 4, 9, 5, 5)

for u, v in [(34, 190), (34, 450), (188, 34), (450, 150), (470, 448), (130, 466)]:
    box('tree_trunk', u-2, v-2, u+2, v+2, 0, 14, 3, 3)
    box('tree_crown_low', u-9, v-9, u+9, v+9, 11, 21, 5, 5)
    box('tree_crown_top', u-5, v-5, u+5, v+5, 21, 27, 5, 5)

flat = material.ravel()
(P/'materials.hex').write_text(''.join(f'{int(x):x}\n' for x in flat))
(P/'feature_ids.hex').write_text(''.join(f'{int(x):04x}\n' for x in feature_ids.ravel()))
# Static material tiles only. Ethernet RLE and packet replay are unchanged.
tiles = material.reshape(H//4,4,W//4,4).transpose(0,2,1,3).reshape(-1,16)
unique, index = np.unique(tiles, axis=0, return_inverse=True)
assert len(unique)<=512, 'Rebudget ROM before adding more tile types'
atlas = np.zeros((512,16), np.uint8)
atlas[:len(unique)] = unique
assert np.array_equal(atlas[index].reshape(H//4,W//4,4,4).transpose(0,2,1,3).reshape(H,W), material)
(P/'tile_index.hex').write_text(''.join(f'{int(x):03x}\n' for x in index))
(P/'tile_atlas.hex').write_text(''.join(f'{int(x):x}\n' for x in atlas.ravel()))
manifest = {'texture_kind': '4-bit material/ground-occlusion mask, not a colour frame',
            'dimensions': [W,H], 'canonical_origin': [SX0,SY0], 'canonical_step': STEP,
            'tile_shape': [4,4], 'tile_types': len(unique), 'index_bits': 8192*9,
            'atlas_bits': 8192*4, 'stored_bits': 8192*13,
            'palette_rgb888': PALETTE, 'building_footprints': BUILDINGS, 'features': features,
            'nonzero_texels': int(np.count_nonzero(flat)), 'unique_identity_text': [],
            'materials_sha256': hashlib.sha256((P/'materials.hex').read_bytes()).hexdigest()}
(P/'scene.json').write_text(json.dumps(manifest,indent=2))

def rom(name,bits,a):
    n=len(a);aw=(n-1).bit_length()
    text=f'// Anonymous surface material lookup; no colour framebuffer.\nmodule {name}(input clk,input [{aw-1}:0] address,output reg [{bits-1}:0] value);\n'
    text+=f' reg [{bits-1}:0] data[0:{n-1}]; /* fehdl force_ram=1, ram_style="bram" */\n integer i;\n initial begin\n'
    text+=f'  for(i=0;i<{n};i=i+1)data[i]=0;\n'
    text+=''.join(f"  data[{i}]={bits}'d{int(v)};\n" for i,v in enumerate(a) if v)
    return text+' end\n always @(posedge clk)value<=data[address];\nendmodule\n'
generated=rom('map_architecture_index_rom',9,index)+rom('map_architecture_material_rom',4,atlas.ravel())
target=R/'B_control/rtl/emergency_map_top.v';s=target.read_text(encoding='utf-8')
marker='// BEGIN GENERATED ANONYMOUS ARCHITECTURE ROM'
if marker in s:s=s[:s.index(marker)]
target.write_text(s.rstrip()+'\n\n'+marker+'\n'+generated,encoding='utf-8')
colors=np.array([[(v>>16)&255,(v>>8)&255,v&255] for v in PALETTE],np.uint8)
Image.fromarray(colors[material&7]).resize((1024,512),Image.Resampling.NEAREST).save(P/'material_mask.png')
print('Generated',len(features),'anonymous details;',len(unique),'unique4x4 tiles;',manifest['stored_bits'],'bits; canonical2-pixel materials, no new pixel pipeline stage',flush=True)
