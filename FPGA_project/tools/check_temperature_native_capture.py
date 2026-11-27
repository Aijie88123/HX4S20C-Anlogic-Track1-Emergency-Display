from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_osd_20261030/native_link'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
inputs=[Path(__file__),R/'tests/tb_temperature_native_link.v'];cases=[]
for baud in [1000000,115200]:
 p=E/str(baud)/'temperature_wire.txt';inputs.append(p);rows=p.read_text().splitlines();assert len(rows)>6
 for row in rows:
  tag,status,integer,fraction,valid,warn,alarm=row.split();status=int(status,16);raw=status&65535;raw=raw-65536 if raw>=32768 else raw
  flags=status>>16
  assert int(valid)==(int(bool(flags&64)) if tag!='OFFLINE' else 0)
  assert int(warn)==int(bool(flags&32)) and int(alarm)==int(bool(flags&16))
  if int(valid):assert int(integer,10)==abs(raw)//16 and int(fraction,10)==((abs(raw)%16)*625+50)//100,(tag,row)
 cases.append(dict(baud=baud,checked_snapshots=len(rows),checks='native-MAC actual flags; frame-latched signed magnitude integer and fractional BCD independently decoded'))
out=E/'capture-check.json';out.write_text(json.dumps(dict(status='PASS',source_hashes={str(p):h(p) for p in inputs},cases=cases,physical_test=False),indent=2))
print('PASS:',cases)
