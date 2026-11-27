from native_vga_reference import pack
from refine2_reference import render as draw
def render(flow):
 out,_=draw(0,0,0,flow,False)
 rgb565=(((out>>19)&31)<<11)|(((out>>10)&63)<<5)|((out>>3)&31)
 return pack(rgb565)
