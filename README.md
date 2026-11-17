# Pocket Motion（Pocket 4P 实况转换与播放器）

专为 **DJI Osmo Pocket 4P** 打造的桌面端实况照片（Live Photo）批量导出、机型水印叠印与跨格式实况播放工具。  
支持从 USB 相机存储卡或电脑本地文件夹读取原始实况素材，一键封装为 **百度网盘 `.livp`**、**Apple 实况 (`.HEIC + .MOV`)** 与 **Android 动态照片 (`.jpg`)**，并提供内置实况播放器直接在电脑上预览和验收成品。

> **下载即用（Windows 10 / 11 64 位免安装版）**  
> 前往 **[GitHub Releases 发布页](https://github.com/happyfox-dot/Pocket-Motion/releases)** 下载最新版本的 `PocketMotion-x.x.x-windows-x64.zip`，**完整解压整个压缩包**后双击 **`PocketMotion.exe`** 即可运行（已内置播放组件、`ffmpeg` / `ffprobe` 与 VC++ 运行库，无需安装任何环境）。

> [!IMPORTANT]
> **版本状态说明**：本项目基于 [MicageEritc/Pocket-Motion](https://github.com/MicageEritc/Pocket-Motion) 独立改造维护（仓库：[happyfox-dot/Pocket-Motion](https://github.com/happyfox-dot/Pocket-Motion)）。当前已完成本地编码、容器结构、水印像素与配对元数据自动校验；不同版本百度网盘客户端及 iPhone、小米、vivo、OPPO 手机相册的端到端表现，建议首次使用时先导出 **1～3 张** 验证。

---

## 一、核心功能一览

- **双源导入，只读不伤原片**：支持自动查找 USB 连接的相机 / 存储卡（`DCIM/DJI_*`），也支持直接选择已复制到电脑任意目录的素材文件夹；全程只读源文件。
- **精准识别相机实况**：基于相机原片 `TPLG_VIDEO_LIVEPHOTO` 标记自动归类「实况 / 视频 / 照片」，不会把普通短视频误判为实况。
- **我该选哪种导出格式？（一目了然）**

| 你的分享 / 导入目标 | 推荐点击的导出按钮 | 输出目录与格式 | 说明 |
| :--- | :--- | :--- | :--- |
| **通过百度网盘发给 iPhone / iPad / Android 手机保存** | **导出百度网盘实况 (.livp)** | `baidu_live/*.livp` | **最常用**。单文件内含真 UUID 配对的 `HEIC + MOV` 及百度 `1000LIVP` 索引尾注，手机网盘 App 下载可直接合成系统相册实况 |
| **Mac 电脑「照片」App 导入，或 Mac 隔空投送 (AirDrop) 给 iPhone** | **导出 Apple 实况 (.HEIC + .MOV)** | `live/*.HEIC` + `*.MOV` | 原生配对双文件（切勿通过手机网盘分开下载这两个文件，否则在手机上会拆成 1 张静态图 + 1 段独立视频） |
| **Android 本地动态照片（试验）** | **导出 Android 动态照片 (.jpg)** | `live/*_MP.jpg` | Google Motion Photo 1.0 单文件封装（各品牌原生相册识别度因系统版本而异） |
| **普通视频 / 静态照片备份** | **导出视频 / 导出照片** | `movie/` · `photo/` | 原样复制源文件并保留原始拍摄时间 |

- **DJI Mimo 官方字标机型水印**：支持一键为实况封面和完整动态画面同步叠印 **DJI 图形标志 + OSMO POCKET 4P** 官方原始字标（四角位置可选，自动探测 NVIDIA / AMD / Intel / Apple GPU 硬件编码加速）。
- **内置跨格式实况与视频播放器**：Windows 无需额外装插件，直接在软件内有声播放相机原片、已导出的 **`.livp`**、**`.HEIC + .MOV`**、**Android 动态照片**与常规视频，支持悬停 `LIVE` 徽标重播与静态封面对比。
- **批量高速导出与增量管理**：支持多路并发导出、同名文件策略（跳过已有 / 覆盖更新 / 自动重命名）、已导出绿标提示、一键「仅选未导出」以及队列**暂停 / 取消**。

---

## 二、3 分钟快速上手（Windows）

### 第 1 步：解压并启动程序
1. 在 [Releases 页面](https://github.com/happyfox-dot/Pocket-Motion/releases) 下载 `PocketMotion-版本号-windows-x64.zip`（注意不要下成底部的 `Source code` 源码包）。
2. **右键解压全部文件到本地文件夹**（不要直接在压缩软件预览窗口内双击，且务必保留 `PocketMotion.exe` 同级的全部 `.dll`、`.exe` 和 `data` 文件夹）。
3. 双击运行 **`PocketMotion.exe`**。

### 第 2 步：导入素材并挑片
- **方式 A（直连相机 / 读卡器）**：用数据线连接 Pocket 4P 并在相机屏幕选择 **「文件传输 / U 盘模式」**（电脑出现盘符），点击左侧 **「查找 USB 相机 / 存储卡」**。
- **方式 B（电脑本地文件夹）**：点击左侧 **「选择本地素材文件夹」**，选择之前从相机拷贝到电脑的文件夹。
- **浏览与选片**：
  - 右上角可切换 **列表视图 / 网格视图**，支持按拍摄时间、文件大小排序或搜索文件名。
  - **网格卡片直播**：点击卡片左下角 `LIVE 播放` 可直接在卡片内播放；点击卡片主体打开大屏播放器（支持 `空格` 播放/暂停、`←` / `→` 切换上一项/下一项、`S` 键快捷勾选导出）。
  - 勾选需要导出的素材（按住 `Shift` 点击可连续多选；老素材较多的目录可点 **「仅选未导出」**）。

### 第 3 步：设置水印与导出
1. 在左侧「2 导出目录」确认保存位置（不能选在相机或源素材文件夹内部）。
2. 如需叠印机型水印，在「3 导出格式与控制」打开 **「添加机型水印」** 并选择角落位置；可按需调整同名处理方式与并发路数。
3. 点击 **「导出百度网盘实况 (.livp)」**（或你需要的其他格式）。
4. 导出完成后，可点击状态条上的 **「播放已导出」** 先在电脑上核对封面、水印、动态与声音，确认无误再点 **「打开目录」**。

---

## 三、如何通过百度网盘让 Apple（iPhone / iPad / Mac）用户查看并下载可播放实况？

软件右上角内置了 **「网盘交付指南」** 按钮，可**一键复制发给接收方的操作步骤**。完整流程如下：

### 1. 发送方（你的上传注意事项）
- 打开导出目录下的 `baidu_live` 文件夹，将里面的 **`*.livp` 文件（或整个文件夹）原样上传到百度网盘** 并创建分享链接。
- **切勿在外层再打包成 `.zip` / `.7z` / `.rar`**：一旦套了普通压缩包，百度网盘将无法在线识别实况，手机端也无法直接存入系统相册。

### 2. iPhone / iPad 接收方操作步骤
1. **用「百度网盘 App」转存**：在手机上用百度网盘 App 打开分享链接，先点击 **「保存到网盘」**（不要在微信内置网页或 Safari 浏览器里直接点下载，网页下载只会变成普通文件存进「文件」App，进不了相册）。
2. **在线查看实况**：在自己的网盘目录中点开该 `.livp` 文件，建议先点底部 **「查看原图」**，界面出现 **「实况 / LIVE」** 标识即可在线有声播放预览。
3. **下载到系统相册**：
   - 首次使用请在 iPhone **「设置 → 百度网盘 → 照片」** 中授予 **「完全访问 / 所有照片」** 权限，并建议关闭手机低电量模式。
   - 点击底部 **「下载 / 保存到相册」**（若新版网盘弹出格式选择，请选 **「实况格式」**，新版网盘同样支持主流 Android 手机按此方式保存实况）。
4. **在苹果「照片」App 中找到并验收**：
   - **重要找图提示**：由于导出的实况完整保留了相机**原始拍摄日期**，iOS「照片」主时间线按拍摄日期排列，几天前拍的素材会归位到拍摄当天，**不一定在相册最底部**！
   - 请直接进入「照片」App 的 **「最近保存（最近项目）」** 或下滑打开 **「媒体类型 → 实况照片」** 相簿，即可在最前面找到它；左上角带 `实况 / LIVE` 角标且长按能流畅有声播放即为成功。

### 3. Mac 电脑接收方操作步骤
- **方式 A（推荐）**：用本软件导出 `live/*.HEIC` + `*.MOV`，Mac 下载后在访达（Finder）中**同时选中同名的一对 `.HEIC` 和 `.MOV`**，一起拖入系统 **「照片 (Photos)」App**（或同时右键隔空投送 AirDrop 给 iPhone），苹果系统会自动根据内部配对 UUID 合并为单张实况照片。
- **方式 B（仅下载了 `.livp`）**：在 Mac 上将 `.livp` 后缀改为 `.zip` 双击解压，把解压出的 `.heic` 和 `.mov` 同时拖入 Mac「照片」App 即可恢复实况。

---

## 四、内置实况与视频播放器说明

本程序内置跨格式实况播放器（交互设计参考 Apple `LivePhotosKit JS`、`JarkViewer` 与 `ente/motion_photos`），即便不连接相机，也可作为 Windows 桌面端实况查看器独立使用：

- 点击窗口右上角 **「实况播放器 → 打开本地实况 / 视频文件…」**，可直接打开电脑任意位置的 `.livp`、`.heic`（自动关联同目录 `.mov`）、Android 动态照片（`*_MP.jpg` / `MVIMG_*.jpg`）或 `.mp4` / `.mov` 视频。
- 在播放器窗口左上角，鼠标**悬停或点击 `LIVE 实况` 徽标**（或长按画面）即可触发带微缩放过渡的实况重播；点击旁边的 **「对比静态封面」** 可随时切换查看封装在内部的静态封面帧；底部支持 `0.5x–2.0x` 倍速与音量调节。

---

## 五、常见问题（FAQ）

<details>
<summary><b>Q1：为什么有些相机拍的 MP4 视频没有出现在「实况」分类，而是在「视频」分类？</b></summary>

只有在 Pocket 4P 实况照片模式下拍摄、文件头带有 `TPLG_VIDEO_LIVEPHOTO` 标记的原始 MP4 才会进入「实况」分类。普通录像或经过第三方剪辑软件重导出丢失标记的视频会归入「视频」分类（支持播放与原文件复制，不会强行转成实况）。
</details>

<details>
<summary><b>Q2：开启「添加机型水印」后导出变慢正常吗？</b></summary>

正常。关闭水印时动态视频流直接无损复制（极快）；开启水印需要将图形水印逐帧合成到动态视频中重新编码。程序已默认启用 GPU 硬件 HEVC 编码加速（NVIDIA NVENC / Intel QSV / AMD AMF / Apple VideoToolbox，不兼容时自动回退 CPU `libx265`），并会在生成新文件名（如 `_WM_DJI1_BR`）时不覆盖无水印版本。
</details>

<details>
<summary><b>Q3：连接相机后点「查找 USB 相机 / 存储卡」提示没找到怎么办？</b></summary>

请确认：① 使用支持数据传输的 USB 线（非纯充电线）；② 在相机屏幕上选择了文件传输 / U 盘模式，且在「此电脑」中能看到带盘符的驱动器（暂不支持无盘符的纯 MTP 模式）；③ 也可以直接点「选择本地素材文件夹」手动指定相机盘符或 `DCIM` 目录。
</details>

---

## 六、技术细节与已知边界

- **水印来源与排版范围**：水印图像直接取自 [DJI 官网 Mimo 2.12.8 安装包](https://www.dji.com/cn/downloads/djiapp/dji-mimo) 中的 `pic_watermark_op4p_1` 原始字标资源（校验记录见 [assets/SOURCES.md](assets/SOURCES.md)）。本程序按视频短边的 50% 缩放画布并锚定所选角落，属于本工具预设布局，未宣称与 Mimo 全模式成片逐像素一致。
- **封面时刻与编码说明**：正常素材取 1.5 秒处作为封面帧，短于 3 秒的素材取中点，封面与 MOV `still-image-time` 轨道严格对齐；静态 `.HEIC` 封面由视频抽帧编码生成，动态视频在无水印模式下直接流复制，音频全程直接流复制。
- **元数据与体积限制**：优先采用 DJI 文件名中的本地拍摄时间，其次读取容器创建时间；尚未完整迁移全部私有元数据或 HDR 辅助轨；`.livp` 采用未压缩 ZIP 流式打包（单文件上限 4 GiB）。
- **第三方应用说明**：手机系统相册长按可播放实况，不代表微信、小红书等全部第三方社交 App 上传时均保持实况状态。

---

## 七、从源码开发与打包（开发者参考）

为什么仓库代码树里不直接提交编译好的 `.exe`？因为运行环境依赖的独立 `ffmpeg.exe` / `ffprobe.exe` 单文件超过 GitHub Git 仓库 100 MB 文件上限，且 Flutter Windows 程序必须携带同级 `.dll` 与 `data/` 目录才能启动，因此完整可执行包统一发布在 **[GitHub Releases](https://github.com/happyfox-dot/Pocket-Motion/releases)**（本地源码目录构建后也可直接双击 `Start-Pocket4P.cmd` 启动 `dist/Pocket4PPort/PocketMotion.exe`）。

环境要求：Flutter（Dart >= 3.13）、Visual Studio 2022 C++ 生成工具、FFmpeg（含 `libx265`）与 `ffprobe`。

```powershell
# 1. 静态分析、单元测试、构建 Release 并将主程序与媒体工具输出到 dist/Pocket4PPort
powershell -File tools/build_windows.ps1

# 2. 打包免安装发布压缩包（含 VC++ 运行库、许可证与 SHA-256 校验清单）到 dist/releases
powershell -File tools/package_windows.ps1

# 3. 合成媒体与四角水印独立解码校验（需 Python 3）
.\.tools\flutter\bin\dart.bat run tools/media_smoke.dart .tools/media-smoke-new
.\.tools\flutter\bin\dart.bat run tools/watermark_smoke.dart .tools/watermark-smoke-new
python tools/verify_watermark.py .tools/watermark-smoke-new
```
