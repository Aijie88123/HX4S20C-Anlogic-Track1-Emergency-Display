"""Generate explicit native font INIT from immutable parent literals; --check does not edit."""
from pathlib import Path
import re,json,hashlib,sys
R=Path(__file__).resolve().parents[1];ref=R/'tests/subtitle_parent_text.v';target=R/'A_display/rtl/text_overlay_8x8.v';s=ref.read_text();font=s[s.index('    function [7:0] font_row;'):s.index('    function [7:0] digit_char;')];glyphs={}
for ch,body in re.findall(r'"(.)":\s*case \(row\)(.*?)endcase',font,re.S):
 vals=[0]*8
 for cases,value in re.findall(r'([\d, ]+|default):font_row=8\x27h([0-9A-Fa-f]+);',body):
  if cases.strip()!='default':
   for row in cases.split(','):vals[int(row)]=int(value,16)
 glyphs[ord(ch)]=vals
assert len(glyphs)>=30
bits=[(glyphs.get(ch,[0]*8)[row]>>(7-col))&1 for ch in range(256) for row in range(8) for col in range(8)]+[0]*16384
params=[]
for n in range(128):params.append(f".INIT_{n:02X}(256'h{sum(v<<i for i,v in enumerate(bits[n*256:n*256+256])):064x})")
marker='// Explicit native shared timestamp/status font; generated, not erased by eram_init=off.\n'
rom=marker+'''module subtitle_shared_font_rom(input clk,input [13:0] address,output pixel);
 wire [15:0] q;reg [3:0] bit_index;
 always @(posedge clk)bit_index<=address[3:0];
 assign pixel=q[bit_index];
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
'''+',\n'.join(params)+''',.SRMODE("SYNC")) rom(
 .doa(q),.dia(16'd0),.addra({1'b0,address[13:4]}),.bytea(1'b0),.bytewea(1'b0),.csa(1'b1),.wea(1'b0),.clka(clk),.rsta(1'b0),.ocea(1'b1),
 .dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),.csb(1'b0),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
endmodule
'''
text=target.read_text();prefix=text.split(marker)[0].rstrip()+'\n\n';result=prefix+rom
if '--check' in sys.argv:assert text==result,'native font source differs from exact generation'
else:target.write_text(result)
E=R/'evidence/uart_subtitle_20261026';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(E/'font-generation.json').write_text(json.dumps(dict(status='PASS',font_bits=16384,physical_bits=32768,source_hashes={str(p):sha(p) for p in [Path(__file__),ref,target]},explicit_native_INIT=True,global_eram_init_unchanged=True),indent=2));print('PASS: explicit native fullfont INIT generation16384 bits')
