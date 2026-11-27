from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/temperature_large_20261031/pipeline';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'A_display/rtl'/n for n in ['alpha_blend.v','audio_bars_overlay.v','audio_envelope.v','audio_fft.v','audio_spectrum_overlay.v','audio_spectrum_precise_overlay.v','audio_waveform_precise_overlay.v','audio_label_font_fast.v','chinese_title_overlay.v','chinese_title_rom.v','text_overlay_8x8.v','transition_fx.v','video_palette_lookup.v','smart_terminal_overlay.v','smart_terminal_overlay_pipelined.v','video_scanout_720p.v']]+[R/'A_display/rtl/subtitle_display.v',R/'common/ethernet_mailbox.v',T/'tb_temperature_pipeline.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram32k.v','eg_phy_glbl.v']]
import shutil
for n in ['words.hex','digests.hex']:shutil.copy2(R/'evidence/uart_subtitle_20261026/display'/n,O/n)
bound=files+[Path(__file__).resolve()];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=O,capture_output=True,timeout=600)
 text=(p.stdout+p.stderr).decode(errors='replace');logs.append(text);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in text or '** Fatal' in text:raise RuntimeError(text[-6000:])
 return text
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
text=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_pipeline','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in text
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
obs=[l for l in text.splitlines() if 'PASS:' in l];print('\n'.join(obs),flush=True)
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':obs,'full_overlay_subtitle_RGB_timing_compared':True,'hardware_test':False},indent=2))

from PIL import Image
im=Image.new('RGB',(320,76));n=0
for row in (O/'pipeline_header.txt').read_text().splitlines():
 x,y,rgb=row.split();x,y,rgb=int(x),int(y),int(rgb,16);im.putpixel((x,y),((rgb>>16)&255,(rgb>>8)&255,rgb&255));n+=1
assert n==320*76
im.resize((640,152),Image.Resampling.NEAREST).save(O/'pipeline_header.png')
