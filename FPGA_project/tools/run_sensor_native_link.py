from pathlib import Path
import subprocess,hashlib,json,binascii,numpy as np
R=Path(__file__).resolve().parents[1];E=R/'evidence/ds18b20_console_20261029/native_link';E.mkdir(parents=True,exist_ok=True)
PS='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
for name,text in [('caption','紧急通知：请按绿色路线疏散 EXIT A'),('caption2','实验室安全提示：请勿返回危险区域 LAB B')]:
 p=subprocess.run([PS,'-NoProfile','-STA','-File',str(R/'tools/subtitle_sender.ps1'),'-RenderOnly','-Text',text,'-OutputPrefix',str(E/name)],capture_output=True);assert p.returncode==0,(p.stdout+p.stderr).decode(errors='replace')
 data=(E/(name+'.uart')).read_bytes();assert len(data)==4290
 for i in range(130):
  f=data[i*33:i*33+33];assert f[:3]==bytes([27,83,1]) and binascii.crc_hqx(f[3:31],65535)==int.from_bytes(f[31:33],'little')
 (E/('frames.hex' if name=='caption' else 'frames2.hex')).write_text(''.join(f'{v:02x}\n' for v in data))
s=(R/'tests/tb_endpoints.v').read_text();s=s[:s.index('module tb_endpoints')].replace("wire gsrn=1'b1;","wire gsrn=1'b1;wire done_gwe=1'b1;");(E/'phy.v').write_text(s)
files=[*sorted((R/'common').glob('*.v')),*[R/'B_control/rtl'/n for n in ['dual_board_control_top.v','key_remove_shakes.v','audio_fft.v','maintenance_uart.v','maintenance_event_log.v','maintenance_text_rom.v','b_uart_service.v','uart_subtitle_bridge.v','ds18b20_emergency.v','ds18b20_master.v','onewire_slot.v','temperature_alarm.v']],*[R/'A_display/rtl'/n for n in ['smart_terminal_hw_top.v','a_map_route_worker.v','subtitle_display.v','text_overlay_8x8.v']],R/'tests/tb_sensor_native_link.v',E/'phy.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_logic_io.v','eg_phy_bram.v','eg_phy_bram32k.v']]
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(t,a,cwd=E):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=cwd,capture_output=True,timeout=1200);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-6500:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);cases=[]
for baud in [1000000,115200]:
 C=E/str(baud);C.mkdir(exist_ok=True)
 for name in ['frames.hex','frames2.hex']:(C/name).write_bytes((E/name).read_bytes())
 log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_sensor_native_link','glbl','-GTEST_BAUD='+str(baud),'-do','onerror {quit -code 1};run -all;quit -code 0'],C);assert 'PASS:' in log
 replies=bytes(int(v,16) for v in (C/'binary_reply.hex').read_text().split());assert len(replies)%10==0
 for i in range(0,len(replies),10):
  reply=replies[i:i+10];assert reply[:3]==bytes([27,65,1]) and binascii.crc_hqx(reply[:8],65535)==int.from_bytes(reply[8:10],'little')
 images=[];widths=[]
 for name in ['caption','caption2']:
  words=np.frombuffer((E/(name+'.bin')).read_bytes(),'<u2').reshape(16,64);a=np.zeros((16,1024),np.uint8)
  for k in range(16):a[:,k::16]=(words>>(15-k))&1
  images.append(a);widths.append(json.loads((E/(name+'.json')).read_text(encoding='utf-8-sig'))['width'])
 pixels=0
 for line in (C/'subtitle_pixels.txt').read_text().splitlines():
  tag,x,y,en,px,bar,phase,rgb,alpha=line.split();tag,x,y,en,px,bar,phase,alpha=map(int,[tag,x,y,en,px,bar,phase,alpha]);rgb=int(rgb,16)
  top=580 if tag>=2 else 680;im=int(tag==3);rel=x+phase-1280
  expected=int(0<=rel<widths[im]*2 and top<=y<top+32 and images[im][(y-top)//2,rel//2])
  assert en==1 and px==expected and bar==1 and rgb==(0xffffff if expected else 0x12385a) and alpha==(255 if expected else 180),(tag,x,y,phase,px,expected,rgb,alpha)
  pixels+=1
 states={}
 for mark in (C/'marks.txt').read_text().splitlines():
  tag,n=mark.split();wire=[v for v in (C/'wire.txt').read_text().splitlines() if v.strip()]
  if tag.startswith('TEMP_'):
   f=dict(v.split('=',1) for v in wire[int(n)].split());states[tag]=f
 assert states['TEMP_SENSOR_FIRE']['SRC']=='2' and states['TEMP_SENSOR_FIRE']['TA']=='1'
 assert states['TEMP_SENSOR_FAULT']['TV']=='0' and states['TEMP_SENSOR_FAULT']['TA']=='1'
 assert states['TEMP_SENSOR_COOL']['TC']=='1' and states['TEMP_SENSOR_STOP']['ACT']=='0'
 assert states['TEMP_LOCAL_RETAINED']['ACT']=='1' and states['TEMP_LOCAL_RETAINED']['ACK']=='0'
 cases.append(dict(sensor_states=states,baud=baud,reply_frames=len(replies)//10,exact_composited_pixels=pixels,observations=[s for s in log.splitlines() if 'PASS:' in s]))
inputs=files+[E/str(baud)/name for baud in [1000000,115200] for name in ['wire.txt','marks.txt']]+[Path(__file__),R/'tools/subtitle_sender.ps1',R/'tests/tb_endpoints.v']+[E/(n+e) for n in ['caption','caption2'] for e in ['.uart','.bin','.json']]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},cases=cases,hardware_test=False,scope='Sensor decoder outputs modeled as qualified samples; independent true-wire test covers acquisition. Actual B top and original V12 MAC/PHY, A original control/route and new native dual-clock subtitle RAM plus existing text compositor. Bulk media RAM omitted; accelerated PHY boot/heartbeat and optional1M baud test. Production115200 full upload separately exercised. Not complete HDMI/SDRAM scanout or physical COM.'),indent=2));print('PASS: host/nativeMAC/RAM/VS/OSD',cases)
