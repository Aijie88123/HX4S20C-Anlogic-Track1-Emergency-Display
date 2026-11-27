# 未随仓库发布的大体积测试向量

为控制仓库体积，`FPGA_project/tests` 下大于 512 KB 的 golden 向量/抓取数据未纳入 Git；
对应的测试脚本、RTL 测试平台和小体积向量均已保留。原始完整快照仍保存在作者本地。

| 文件 | 体积 |
|---|---:|
| `FPGA_project/tests/animation_pixel0.hex` | 1.3 MB |
| `FPGA_project/tests/animation_v2_pixel0.hex` | 1.3 MB |
| `FPGA_project/tests/blue_smooth_reference.hex` | 84.4 MB |
| `FPGA_project/tests/map_r7_words.hex` | 1.1 MB |
| `FPGA_project/tests/media_vectors/disk.hex` | 16.7 MB |
| `FPGA_project/tests/media_vectors_small/disk.hex` | 1.1 MB |
| `FPGA_project/tests/mesh3d_frame0_words.hex` | 1.1 MB |
| `FPGA_project/tests/mesh3d_steady_words.hex` | 6.6 MB |
| `FPGA_project/tests/mesh3d_tiles_rtl.hex` | 3.3 MB |
| `FPGA_project/tests/min640_vectors/disk.bin` | 1 MB |
| `FPGA_project/tests/min640_vectors/pixels.hex` | 2.3 MB |
| `FPGA_project/tests/native_map_words.hex` | 1.1 MB |
| `FPGA_project/tests/native_particle_words.hex` | 1.1 MB |
| `FPGA_project/tests/native_steady_last.hex` | 1.1 MB |
| `FPGA_project/tests/native_steady_map.hex` | 6.6 MB |
| `FPGA_project/tests/native_steady_particles.hex` | 6.6 MB |
| `FPGA_project/tests/native_vga_particle.hex` | 1.1 MB |
| `FPGA_project/tests/real_card_vectors/sectors.bin` | 5.8 MB |
| `FPGA_project/tests/realtime_reference.hex` | 10.5 MB |
| `FPGA_project/tests/reference_resource_timing/B_control_b_particle_shader.v` | 1.6 MB |
| `FPGA_project/tests/six_vectors_small/disk.hex` | 1.1 MB |
| `FPGA_project/tests/smooth_map_pixels.hex` | 1.8 MB |
| `FPGA_project/tests/smooth_particle_pixels.hex` | 1.8 MB |
| `FPGA_project/tests/visual_display_rtl.hex` | 7 MB |
