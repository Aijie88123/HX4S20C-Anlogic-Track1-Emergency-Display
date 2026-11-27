# 第三方组件与素材说明

本仓库的 **MIT License** 仅覆盖项目作者原创的 RTL、软件、脚本和文档。以下内容版权归各自权利人所有，不在 MIT 许可范围内。

## 1. 开发板厂商 IP（`vendor/`）

`FPGA_project/A_display/vendor/` 与 `FPGA_project/B_control/vendor/` 来自 HX4S20C 开发板配套资料包，包含但不限于：

- HDMI 1.4b Transmitter Core（`hdmi_1_4b_transmitter_core_wrapper.enc.v`，加密源码）；
- SDRAM 控制器与初始化逻辑（`sdr_*.enc.v`）；
- HDMI PHY、LVDS、I2S、SD 卡、BMP 读取、PLL/ROM 等参考设计；
- 厂商提供的 `.ipc` / `.tcl` / `.v` / `.vhd` IP 配置与仿真文件。

这些文件仅用于让本工程能够按原样综合、复现作者发布时的 bit/bin。**它们的版权归 HX4S20C 开发板厂商或原始 IP 提供方所有**，本仓库不声称对其拥有任何权利，也不对其授予 MIT 许可。

如果你要复用、再分发或商业使用这些文件，请先核对开发板厂商资料包中的授权条款。若权利人认为本仓库的分发方式不合适，请提 Issue 或联系作者，我们会移除对应文件。

## 2. 演示素材（`assets/`）

- `FPGA_project/assets/tf_card/PREV_BMP/`：用于 TF 卡播放的 24 位 BMP 演示图；
- `FPGA_project/assets/` 下的预览 PNG/GIF、地图场景图、建筑名称、UI 图集；
- `FPGA_project/assets/audio_visual/` 与音频相关资源。

这些素材由项目作者制作或从公开素材整理。如果其中包含第三方图片、字体、音乐或图标，其版权归原权利人所有；公开发布或商业使用前请替换为你有权使用的素材。

## 3. 字模与字体

`chinese_title_rom.v`、HDMI 字幕字模、建筑名称字模等由项目脚本生成。若字模位图来源于 Windows 系统字体或其他第三方字体，商用前请确认相应字体授权。PC 控制台在运行时调用系统字体渲染预览，不随仓库分发字体文件。

## 4. 工具链

本工程使用安路科技 TD（Tang Dynasty）2026.1 SP2 进行综合、布局布线与 bit 生成，使用 ModelSim/QuestaSim 进行 RTL 仿真。这些工具需自行安装并遵守其许可协议，本仓库不包含工具本体。

## 5. 引用与致谢

工程中的以太网 MAC/PHY、SD 卡、HDMI 发送、音频等底层参考设计来自开发板厂商资料与公开参考实现；项目作者完成了地图渲染、寻路、双板协议、温度联动、字幕、PC 控制台及系统集成。具体修改范围与验证边界见 `FPGA_project/README.md` 及各阶段报告。
