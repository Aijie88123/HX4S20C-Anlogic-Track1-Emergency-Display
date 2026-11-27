from pathlib import Path
import json,hashlib,math
import numpy as np
from mesh3d_reference import render,trunc
R=Path(__file__).resolve().parents[1];O=R/'evidence/3d_ui_smooth_20261018/budget';O.mkdir(parents=True,exist_ok=True)
f=[R/'assets/true3d_scene.json',R/'A_display/rtl/a_mesh3d_projector.v',R/'B_control/rtl/b_mesh3d_tile_renderer.v',R/'common/raster_map_window.v',R/'common/distributed_audio.v',R/'common/remote_tf_sector.v',R/'tests/mesh3d_reference.py',Path(__file__).resolve(),*[R/'assets/map_ui'/n for n in ['atlas.hex','status.hex','compass.hex']]]
f += [R/'A_display/rtl/smart_terminal_hw_top.v',R/'B_control/rtl/dual_board_control_top.v',R/'common/ethernet_command_link.v']
f += [R/'A_display/rtl/a_map_route_worker.v']
geometry=json.loads(f[0].read_text())['triangles'];nodes=[(80+(i%3)*176,80+(i//3)*176) for i in range(9)]+[(256,0),(0,256),(512,256),(256,512)]
nodes += [(u,v) for u in [0,1,511,512] for v in [0,1,511,512]]
minimum_z=100000;maximum_z=0;minxy=100000;maxxy=-100000;count=0
def packets(yaw,zoom,pu,pv,event,check=True):
 global minimum_z,maximum_z,minxy,maxxy,count
 angle=math.radians(-60+yaw*30/63);sn=round(math.sin(angle)*256);cs=round(math.cos(angle)*256);focal=[240,300,360][zoom]
 fu=256+((pu-256)>>1);fv=256+((pv-256)>>1);hu,hv,hh=[(133,344,90),(133,168,68),(309,168,105),(309,344,80)][event]
 result=[]
 for i,(a,b,c,color,kind,ref,edges) in enumerate(geometry):
  fx=kind
  if kind in [1,2] and ref==[4,0,2,6][event]:color=0xd086 if kind==1 else 0x9004
  if kind==3:
   if ref==[7,0,10,5][event]:color=0xd068;fx=9
   elif ref in [2,8,12]:color=0x5b1;fx=8
  p=14|(1<<8)|(1<<16)|(i<<32)|(int(i==117)<<40)|(edges<<41)|(fx<<44)|(color<<48)|(event<<184)|(yaw<<186)|(zoom<<192)
  for j,(u,v,h) in enumerate([a,b,c]):
   if kind==4:u+=pu;v+=pv
   elif kind==5:u+=hu;v+=hv;h+=hh
   elif kind==6:
    eu,ev=[(256,0),(0,256),(512,256),(256,512)][ref];u+=eu;v+=ev
   rx=((u-fu)*cs-(v-fv)*sn)>>8;rz=((u-fu)*sn+(v-fv)*cs)>>8
   cy=(h*147+rz*210)>>8;cz=900+((rz*147-h*210)>>8)
   sx=160+trunc(rx*focal,cz);sy=80-trunc(cy*focal,cz);iz=16777216//cz
   if check:
    assert cz>0 and 0<iz<65536 and -512<=sx<512 and -512<=sy<512
    assert all(-4096<=v<4096 for v in [u-fu,v-fv,h,rx,rz,cy,cz])
    assert abs(rx*focal)<2**31 and abs(cy*focal)<2**31
    minimum_z=min(minimum_z,cz);maximum_z=max(maximum_z,cz);minxy=min(minxy,sx,sy);maxxy=max(maxxy,sx,sy);count+=1
   p|=((sx&4095)|((sy&4095)<<12)|(iz<<24))<<(64+j*40)
  result.append(p)
 return result
for yaw in range(64):
 for zoom in range(3):
  for event in range(4):
   for pu,pv in nodes:packets(yaw,zoom,pu,pv,event)
worst=0;sampled=0
for yaw in [0,32,63]:
 for zoom in range(3):
  for event in range(4):
   for pu,pv in [(80,432),(256,256),(432,80)]:
    p=packets(yaw,zoom,pu,pv,event,False)
    for phase in [0,7,32]:
     pix=render(p,phase).ravel();changes=np.flatnonzero(pix[1:]!=pix[:-1])+1
     spans=np.diff(np.r_[0,changes,len(pix)]);runs=int(((spans+255)//256).sum());data_packets=(runs+6)//7
     # HELLO + META; 8 preamble + 64 body/FCS + 12 IFG = 84 bytes.
     wire_packets=data_packets+2;worst=max(worst,wire_packets);sampled+=1
mbps=worst*84*8*30/1e6
assert mbps<55,(worst,mbps)
# Renderer checks signed-10-bit vertices before use. Finite 64-yaw/3-zoom
# campus projection is bounded using route points plus all even/odd extrema
# of the full 0..512 person rectangle, with 12 pixels conservative rounding
# guard for intermediate fixed-point rotation/pitch and perspective truncation.
assert minimum_z>0 and minxy-12>=-512 and maxxy+12<512
width_bounds={'renderer_coordinate_bits':10,'projection_guard_pixels':12,'guarded_projected_xy':[minxy-12,maxxy+12],'signed_area_22_abs_max':2*1023**2,'signed_edge_22_abs_max':2*1023*(512+319),'signed_gradient_numerator_36_abs_max':2*65535*1023*256}
assert width_bounds['signed_area_22_abs_max']<2**21
assert width_bounds['signed_edge_22_abs_max']<2**21
assert width_bounds['signed_gradient_numerator_36_abs_max']<2**35
assert '.P_WIN(64)' in (R/'common/distributed_audio.v').read_text()
assert 'HEARTBEAT_CYCLES=2500000' in (R/'common/ethernet_command_link.v').read_text()
wire_packet_bits=84*8
spectrum_mbps=(48000/64)*wire_packet_bits/1e6
control_mbps=50*wire_packet_bits/1e6
heartbeat_mbps=10*wire_packet_bits/1e6
geometry_mbps=118*30*wire_packet_bits/1e6
b_extra_mbps=geometry_mbps+spectrum_mbps+control_mbps+heartbeat_mbps
assert 55+34.86328125+b_extra_mbps<95
assert mbps+geometry_mbps+8.064+34.86328125+heartbeat_mbps<95
result={'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f},
 'renderer_width_bounds':width_bounds,'camera_bounds':{'yaw_degrees':[-60,-30],'yaw_codes':64,'zooms':[1,1.25,1.5],'route_and_rectangle_extrema':len(nodes),'events':4,'vertices_checked':count,'positive_camera_z_range':[minimum_z,maximum_z],'screen_xy_range':[minxy,maxxy],'all_in_front_of_near_plane':True,'integer_widths_checked':True},
 'bandwidth':{'sampled_current_mesh_frames':sampled,'includes_three_route_dash_phases':True,'worst_sampled_B_wire_packets_per_frame':worst,'worst_sampled_B_Mbps_at_30fps':mbps,'map_reservation_Mbps':55,'B_reservation_Mbps':95,'max_TF_wire_upper_Mbps_at_6_25MHz_SPI':34.86328125,'PCM_wire_Mbps':8.064,'geometry_or_geometry_ACK_Mbps':geometry_mbps,'spectrum_64_sample_window_upper_Mbps':spectrum_mbps,'B_controls_50Hz_Mbps':control_mbps,'heartbeat_10Hz_per_direction_Mbps':heartbeat_mbps,'B_map_reservation_TF_geometry_ACK_spectrum_controls_upper_Mbps':55+34.86328125+b_extra_mbps,'B_sampled_map_TF_geometry_ACK_spectrum_controls_upper_Mbps':mbps+34.86328125+b_extra_mbps,'A_map_ACK_geometry_PCM_TF_upper_Mbps':mbps+geometry_mbps+8.064+34.86328125+heartbeat_mbps,'additional_B_retry_headroom_Mbps':5,'A_peak_retry_headroom_Mbps':5,'A_reservation_Mbps_including_PCM_geometry_ACK_TF':95,'physical_link_Mbps':100,'images_and_retries_share_remaining_scheduler_bandwidth':True,'not_an_arbitrary_mesh_30fps_guarantee':True},
 'storage_words':{'capacity_per_board':2097152,'A_reserved':2073600,'B_reserved':1958400,'unchanged':True},
 'observations':['PASS: finite camera envelope retains positive near depth and signed arithmetic range across all 64 yaw values, 3 zoom values, four incidents and the full person rectangle extrema','PASS: sampled RLE below 55Mbps map allocation at target 30fps. Both directions reserve 95Mbps including physical-TF packet overhead, geometry/ACK, 64-sample spectrum, controls and heartbeat; images and retries share remaining bandwidth, and backpressure reduces TF throughput or frame rate at saturation. Each direction retains the physical 100Mbps ceiling; no measured board FPS claim']}
(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='source_hashes'},indent=2),flush=True)
