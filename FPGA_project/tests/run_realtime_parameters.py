"""Run actual adjustment-chain RTL; retain compiled inputs, library and transcript."""
from pathlib import Path
import subprocess, hashlib, json, sys
from datetime import datetime, timezone
R=Path(__file__).resolve().parents[1]
A=R/'A_display'
SD=A/'vendor/user_source/hdl_source/SD'
MS=Path('D:/modelsim/win64')
OUT=R/'tests/realtime_parameters'
files=[A/'rtl/video_palette_lookup.v',A/'rtl/display_parameter_control.v',A/'rtl/smart_terminal_overlay.v',
       A/'rtl/text_overlay_8x8.v',A/'tb/text_overlay_link_baseline.v',
       A/'rtl/bmp_write_scaler.v',A/'vendor/user_source/hdl_source/key_remove_shakes.v']
files += [SD/n for n in ['sd_card_bmp.v','bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']]
files += [R/'tests/tb_realtime_parameters.v']
bound=files+[Path(__file__)]+list((A/'rtl').glob('*.vh'))
def snapshot():
    return {p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in bound}
before=snapshot()
OUT.mkdir(parents=True,exist_ok=True)
commands=[]
if not (OUT/'work').exists():commands.append([str(MS/'vlib.exe'),'work'])
commands += [[str(MS/'vlog.exe'),'-sv','+incdir+'+str(A/'rtl'),*[str(p) for p in files]],
             [str(MS/'vsim.exe'),'-c','-novopt','work.tb_realtime_parameters','-l','transcript.log',
              '-do','onerror {quit -code 1}; run -all; quit -code 0']]
log=''
for cmd in commands:
    p=subprocess.run(cmd,cwd=OUT,capture_output=True,timeout=180)
    log+=(p.stdout+p.stderr).decode('utf-8',errors='replace')
    if p.returncode or '** Error' in log or '** Fatal' in log:break
(OUT/'audit.log').write_text(log,encoding='utf-8')
markers=[line for line in log.splitlines() if 'PASS:' in line or '** Error' in line or '** Fatal' in line]
ok=p.returncode==0 and '** Error' not in log and '** Fatal' not in log and len(markers)==6 and before==snapshot()
result={'status':'PASS' if ok else 'FAIL','markers':markers,'compiled_sources':before,
        'clock_test':'independent 20ns/26ns clocks; production key durations scaled by CLK_FREQ_HZ=1000',
        'fault_injection':'only internal card-ready wire; production decoder, scheduler, CDC, LUT and OSD',
        'completed_utc':datetime.now(timezone.utc).isoformat()}
(OUT/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
sys.exit(0 if ok else 1)
