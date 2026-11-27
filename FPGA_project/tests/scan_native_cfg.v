config scan_native_cfg;
 design work.tb_control25_chain;
 default liblist work;
 instance tb_control25_chain.a_frames use A_native.frame_read_write;
 instance tb_control25_chain.a_ram use A_native.sdram;
 instance tb_control25_chain.b_storage.u_frames use B_native.frame_read_write;
 instance tb_control25_chain.b_storage.U3 use B_native.sdram;
 endconfig
