from pathlib import Path
import hashlib,json,re,subprocess
R=Path(__file__).resolve().parents[1];O=R/'evidence/fast_carousel_20261025/control';O.mkdir(parents=True,exist_ok=True)
text=(R/'A_display/rtl/text_overlay_8x8.v').read_text(encoding='utf-8-sig');fun=re.search(r'    function \[7:0\] period_char;.*?    endfunction',text,re.S)[0]
probe=O/'period_probe.v';probe.write_text('module period_probe #(parameter DEMO_FAST_PERIODS=1,ENABLE_PLAYBACK_OSD=1)(input [1:0] interval_selection,input playback_running);\n'+fun+'\nendmodule\n',encoding='utf-8')
ui=O/'tb_period_probe.v';ui.write_text('''module tb_period_probe;
reg [1:0] mode=0;reg play=1;integer m,i;reg [31:0] expected;reg [7:0] c;
period_probe f(.interval_selection(mode),.playback_running(play));
period_probe #(.DEMO_FAST_PERIODS(0)) old(.interval_selection(mode),.playback_running(play));
initial begin
for(m=0;m<3;m=m+1)begin mode=m;#1;expected=m==0?"TMAX":m==1?"T01S":"T02S";for(i=0;i<4;i=i+1)if(f.period_char(i)!==expected[(3-i)*8+:8])$fatal(1,"fast OSD mismatch");
expected=m==0?"T03S":m==1?"T05S":"T10S";for(i=0;i<4;i=i+1)if(old.period_char(i)!==expected[(3-i)*8+:8])$fatal(1,"legacy OSD mismatch");end
for(i=5;i<10;i=i+1)if(f.period_char(i)!==old.period_char(i))$fatal(1,"PLAY label changed");play=0;#1;for(i=5;i<10;i=i+1)if(f.period_char(i)!==old.period_char(i))$fatal(1,"PAUSE label changed");
$display("PASS: actual period_char fast TMAX/T01S/T02S, legacy T03S/T05S/T10S, PLAY/PAUSE retained");$finish;end
endmodule
''',encoding='utf-8')
files=[R/'B_control/rtl/dual_board_control_top.v',R/'A_display/rtl/a_media_cached_control.v',R/'A_display/rtl/video_scanout_720p.v',R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',R/'tests/tb_fast_carousel_clock.v',R/'tests/tb_fast_carousel_control.v',probe,ui]
files=[p for p in files if p.exists()]
# key_longpress is declared in the existing local controller support source.
if not any('module key_longpress' in p.read_text(encoding='utf-8-sig',errors='replace') for p in files):
 matches=[p for p in (R/'A_display/rtl').glob('*.v') if 'module key_longpress' in p.read_text(encoding='utf-8-sig',errors='replace')]
 files+=matches
bound=files+[R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/rtl/smart_terminal_overlay_pipelined.v',R/'A_display/rtl/text_overlay_8x8.v',Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in bound}
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(x).replace(chr(92),'/') for x in a]],cwd=O,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'fast_carousel',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
obs=[]
for top in ['tb_fast_carousel_clock','tb_fast_carousel_control','tb_period_probe']:
 s=run('vsim',['-modelsimini',I,'-c','fast_carousel.'+top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;obs+=[v for v in s.splitlines() if 'PASS:' in v]
assert h=={str(p):sha(p) for p in bound}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual B millisecond scheduler and production A complete-role controller plus17-phase geometry control at scaled raster timing. Exact timers/ready-ACK holds, first3s,350ms cadence and UI labels. Metadata complete-cache model, not pixel-memory/physical-board measurement.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
