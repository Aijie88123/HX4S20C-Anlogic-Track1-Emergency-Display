from pathlib import Path
import math
R=Path(__file__).resolve().parents[1]
frequencies=[261.63,293.66,329.63,349.23,392,440,493.88,523.25,800,1000,1200,1600]
t=(R/'tools/audio_dft12.template').read_text(encoding='utf-8-sig')
t=t.replace('@INCREMENTS@','\n'.join(f"    4'd{n}: increment=32'd{round(f*2**32/48000)}; // nominal{f}Hz" for n,f in enumerate(frequencies)))
t=t.replace('@SINE@','\n'.join(f"  sine_mem[{n}]=12'd{round(2047*math.sin(math.pi*n/512))};" for n in range(257)))
t=t.replace('@WINDOW@','\n'.join(f"    6'd{n}: window_coefficient=8'd{round(255*(.54-.46*math.cos(2*math.pi*n/63)))};" for n in range(64)))
for p in [R/'common/audio_dft12.v',R/'A_display/rtl/audio_dft12.v',R/'B_control/rtl/audio_dft12.v']:p.write_text(t)
print('Generated12 full-rate DFT probes; original audio generator/sample clock unchanged')
