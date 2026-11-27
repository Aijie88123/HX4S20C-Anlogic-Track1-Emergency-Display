from pathlib import Path
import hashlib,json,re,subprocess
R=Path(__file__).resolve().parents[1]; O=R/'evidence/slow_carousel_20261029/simulation'; O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64'); I=O/'modelsim.ini'; I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n'); W=O/'work'; logs=[]; obs=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
text=(R/'A_display/rtl/text_overlay_8x8.v').read_text(encoding='utf-8-sig')
fun=re.search(r'    function \[7:0\] period_char;.*?    endfunction',text,re.S)[0]
probe=O/'period_probe.v'; probe.write_text('`timescale 1ns/1ps\nmodule period_probe #(parameter DEMO_FAST_PERIODS=1,ENABLE_PLAYBACK_OSD=1)(input [1:0] interval_selection,input playback_running);\n'+fun+'\nendmodule\n')
ui=O/'tb_slow_period_probe.v'; ui.write_text('''`timescale 1ns/1ps
module tb_slow_period_probe;
reg [1:0] mode=0;reg play=1;integer m,i;reg [31:0] expected;
period_probe f(.interval_selection(mode),.playback_running(play));
period_probe #(.DEMO_FAST_PERIODS(0)) legacy(.interval_selection(mode),.playback_running(play));
initial begin
for(m=0;m<3;m=m+1)begin mode=m;#1;expected=m==0?"T03S":m==1?"T05S":"T08S";
for(i=0;i<4;i=i+1)if(f.period_char(i)!==expected[(3-i)*8+:8])$fatal(1,"slow OSD mismatch");
expected=m==0?"T03S":m==1?"T05S":"T10S";
for(i=0;i<4;i=i+1)if(legacy.period_char(i)!==expected[(3-i)*8+:8])$fatal(1,"legacy OSD mismatch");end
for(i=5;i<10;i=i+1)if(f.period_char(i)!==legacy.period_char(i))$fatal(1,"PLAY label changed");
play=0;#1;for(i=5;i<10;i=i+1)if(f.period_char(i)!==legacy.period_char(i))$fatal(1,"PAUSE label changed");
$display("PASS: actual production period_char T03S/T05S/T08S; legacy T03S/T05S/T10S and PLAY/PAUSE retained");$finish;end
endmodule
''')
files=[R/'B_control/rtl/dual_board_control_top.v',R/'A_display/rtl/a_media_cached_control.v',R/'A_display/rtl/video_scanout_720p.v',R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',R/'B_control/rtl/key_remove_shakes.v',R/'B_control/rtl/audio_fft.v',*[R/'common'/n for n in ['distributed_map.v','distributed_audio.v','ethernet_mailbox.v','particle_transition.v','audio_dft12.v']],R/'tests/period_button_link_models.v',*[R/'B_control/rtl'/n for n in ['maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v','ds18b20_emergency.v','ds18b20_master.v','onewire_slot.v','temperature_alarm.v']],Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v'),*[R/'tests'/n for n in ['tb_slow_period_top.v','tb_slow_carousel_clock.v','tb_slow_carousel_control.v']],probe,ui]
if not any('module key_longpress' in p.read_text(encoding='utf-8-sig',errors='replace') for p in files):
 files += [p for p in (R/'A_display/rtl').glob('*.v') if 'module key_longpress' in p.read_text(encoding='utf-8-sig',errors='replace')]
bound=list(dict.fromkeys(files+[R/'A_display/rtl/text_overlay_8x8.v',R/'A_display/rtl/smart_terminal_hw_top.v',Path(__file__).resolve()]))
h={str(p):sha(p) for p in bound}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[str(v).replace(chr(92),'/') for v in args]],cwd=O,capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'slow_carousel',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
for top,parameters in [('tb_slow_carousel_clock',[]),('tb_slow_period_top',[]),('tb_slow_period_probe',[])]+[('tb_slow_carousel_control',['-gSELECTED_MS='+str(ms)]) for ms in [3000,5000,8000]]:
 s=run('vsim',['-modelsimini',I,'-c','slow_carousel.'+top,'slow_carousel.glbl',*parameters,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s,top
 rows=[v for v in s.splitlines() if 'PASS:' in v];obs+=rows;print('\n'.join(rows),flush=True)
assert h=={str(p):sha(p) for p in bound},'Inputs changed during simulation'
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual production scheduler at scaled divider; precise3/5/8s, first3s, all switch codes, S2 debounce and emergency gates, pause/link/ready/ACK holds; actual A cached controller and all8 complete roles at scaled raster, both flip/zoom full17 phases at all3 selections. Production OSD function extracted verbatim. PLL/peer and complete-cache metadata modeled; no physical timing or HDMI acceptance.'),ensure_ascii=False,indent=2),encoding='utf-8')
