from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1];data=bytearray(1024);used=set()
for row in json.loads((R/'assets/uart/messages.json').read_text()):
 base=row['address'];msg=bytes.fromhex(row['hex'])+b'\0'
 for i,v in enumerate(msg):
  assert base+i<1024 and base+i not in used
  used.add(base+i);data[base+i]=v
s='''// Explicit initialized 8Kb native ROM: no dependency on gate eram_init.
module maintenance_text_rom(input clk,input [9:0] address,output [7:0] q);
 wire [8:0] native_q;
 EG_PHY_BRAM #(.MODE("DP8K"),.DATA_WIDTH_A("9"),.DATA_WIDTH_B("9"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
'''
s+=',\n'.join(f" .INIT_{i:02X}(256'h{int.from_bytes(data[i*32:(i+1)*32],'little'):064x})" for i in range(32))
s+='''
 ) u_rom(.doa(native_q),.dia(9'd0),.addra({address,3'd0}),.csa(3'b111),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),
  .dob(),.dib(9'd0),.addrb(13'd0),.csb(3'b000),.ceb(1'b0),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0));
 assign q=native_q[7:0];
endmodule
'''

p=R/'B_control/rtl/maintenance_text_rom.v'
if '--check' in sys.argv:assert p.read_text()==s,'UART text ROM differs from source messages'
else:p.write_text(s)
E=R/'evidence/uart_service_20261026';E.mkdir(parents=True,exist_ok=True)
expected=''.join(f'{v:02x}\n' for v in data)
if '--check' in sys.argv:assert (E/'text_expected.hex').read_text()==expected
else:(E/'text_expected.hex').write_text(expected)
files=[Path(__file__),R/'assets/uart/messages.json',p,E/'text_expected.hex']
(E/'text-generation.json').write_text(json.dumps(dict(status='PASS',bytes=1024,occupied=len(used),source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}),indent=2))
print('PASS: native UART text ROM reproduced,1024 bytes')
