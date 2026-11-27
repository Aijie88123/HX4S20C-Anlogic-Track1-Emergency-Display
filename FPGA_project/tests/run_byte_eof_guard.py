from pathlib import Path
import subprocess, json, hashlib, sys
root=Path(__file__).resolve().parents[1]
modelsim=Path('D:/modelsim/win64')
out=root/'evidence/tf_coldstart_R8_20261016/byte_eof_guard'
out.mkdir(parents=True,exist_ok=True)
work=out/'work'
ini=out/'modelsim.ini'
ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n',encoding='ascii')
required_vectors=[root/'tests/storage_recovery_vectors'/(prefix+'_'+suffix)
    for prefix in ['small','full'] for suffix in ['disk.hex','expected.hex','starts.hex','sizes.hex','manifest.json']]
if not all(path.exists() for path in required_vectors):
    subprocess.run([sys.executable,str(root/'tests/generate_storage_recovery_vectors.py')],check=True)
b=root/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
sources=[sd/name for name in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
sources += [b/'rtl'/name for name in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
sources += [ip/name for name in ['afifo_16_32_256.v','afifo_32_16_256.v']]
sources += [root/'tests/card_spi_storage_recovery.v',root/'tests/tb_byte_eof_guard.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,root/'tests/baseline_R7/bmp_read.v']}
logs=[]
def run(tool,args):
    result=subprocess.run([str(modelsim/(tool+'.exe')),*args],cwd=root/'tests',capture_output=True,timeout=1200)
    text=(result.stdout+result.stderr).decode(errors='replace');logs.append(text)
    if result.returncode or '** Error' in text or '** Fatal' in text:raise RuntimeError(text)
    return text
try:
    if not work.exists():run('vlib',[str(work)])
    run('vmap',['-modelsimini',ini.as_posix(),'storage_recovery_work',str(work)])
    run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',str(work),*map(str,sources)])
    results=[]
    for baseline in [1,0]:
        full=1;faults=0
        current_sources=[root/'tests/baseline_R7/bmp_read.v' if baseline and p==sd/'bmp_read.v' else p for p in sources]
        run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',str(work),*map(str,current_sources)])
        text=run('vsim',['-modelsimini',ini.as_posix(),'-c','-l',str(out/('full_images_live.log' if full else 'recovery_live.log')),
             'storage_recovery_work.tb_byte_eof_guard','-gFULL_IMAGES='+str(full),'-gINJECT_FAULTS='+str(faults),'-gEXPECT_OLD_ABORT='+str(baseline),
             '-do','onerror {quit -code 1}; run -all; quit -code 0'])
        assert 'PASS:' in text
        passes=[line for line in text.splitlines() if 'PASS:' in line]
        print('\n'.join(passes),flush=True);results.extend(passes)
finally:(out/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,root/'tests/baseline_R7/bmp_read.v']},'Sources changed during validation; rerun against final files.'
manifests={name:json.loads((root/'tests/storage_recovery_vectors'/name).read_text()) for name in ['small_manifest.json','full_manifest.json']}
(out/('recovery_result.json' if '--recovery-only' in sys.argv else 'result.json')).write_text(json.dumps({'status':'PASS','source_hashes':hashes,'verified':results,'fixtures':manifests},indent=2),encoding='utf-8')
