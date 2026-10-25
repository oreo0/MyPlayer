# MyPlayer

一个纯净的本地 macOS 音视频播放器，ChatGPT 协助制作。
A pure, local audio and video player for macOS, made with Passion and ChatGPT.

**当前版本：MyPlayer v4.0.20**
**系统要求：macOS 27 或更新版本；Apple Silicon（arm64）。不支持 Intel Mac。**

[下载安装包](https://github.com/oreo0/MyPlayer/releases/tag/v4.0.20) · [更新记录](CHANGELOG.md) · [用户数据](USER-DATA.md) · [参与贡献](CONTRIBUTING.md)

## 下载与安装

1. 在 [Releases](https://github.com/oreo0/MyPlayer/releases) 下载 `MyPlayer-v4.0.20-arm64.dmg`，打开后将 `MyPlayer.app` 拖到 Applications。也可下载 ZIP 解压安装。
2. 替换旧版前，请先完全退出应用。应用包名称保持 `MyPlayer.app`，版本号仅在“关于 MyPlayer”中显示为 `v4.0.20`。此开发线已并入正式版本命名。
3. 本次发布使用临时签名，**未经过 Developer ID 签名和 Apple 公证**；下载后 macOS 可能提示无法验证开发者。不要将此发布包视为 App Store 或已公证版本。
4. 可使用发布附件 `SHA256SUMS.txt` 校验下载文件。

## 功能

- **随封面变化的音乐氛围**：封面取色搭配极光光效，让每张专辑都有自己的视觉表达。
- **可定制的质感界面**：毛玻璃、深层磨砂与纯色背景，搭配明暗外观和主题强调色。
- **音乐与视频一站播放**：本地音视频统一管理，同时支持同步歌词与视频字幕。
- **自由组织个人收藏**：按专辑、艺人、文件夹浏览，也能创建专属合集，整理喜欢的内容。
- **接续上次的播放**：记住播放进度与会话状态，再次打开即可继续。
- **为 Mac 打造的原生体验**：融合 macOS 原生界面与自定义快捷键，让浏览和播放更顺手。

## 用户数据与 iCloud

为兼容已有资料库，继续使用 Bundle ID `com.myplayer.native.beta` 和本地目录 `~/Library/Application Support/MyPlayer Beta/`；这些内部兼容名称不会将应用显示为 Beta。缺少该目录时沿用旧版首次迁移逻辑；日常升级保留已有数据，不重复导入或清空。

提供 iCloud Drive 文件备份与重装恢复逻辑，覆盖资料库记录、设置、封面、歌词/字幕副本、合集、队列与播放状态；**音乐和视频原文件不上传，仍保留原位置**。

**已知限制：**本地备份/恢复流程已用合成数据验证，未重新验证服务器上传和跨设备恢复。请勿将这一功能作为唯一备份。详情见 [USER-DATA.md](USER-DATA.md)。

## 从源码构建

需要 Apple Silicon Mac、macOS 27+，以及包含 macOS 27 SDK 的 Xcode 和命令行工具；不依赖第三方 Swift 包。

```sh
git clone https://github.com/oreo0/MyPlayer.git
cd MyPlayer
open MyPlayer.xcodeproj
```

选择 `MyPlayer` scheme 后在 Xcode 中构建，或运行：

```sh
bash build_app.sh
bash package_app.sh
```

构建输出位于仓库上一级的 `work/ReleaseDerivedData/`；ZIP 位于上一级 `outputs/`。`Version.txt` 定义公开版本 `4.0.20`；后续发布依次使用 `v4.0.21` 等标签。`BuildNumber.txt` 当前为内部构建 29，每次 Xcode 构建自动加一，下一次为 30；内部构建号与公开版本分别管理。

## 本版性能修复

移除应用入口未使用的云状态订阅，避免云状态更新触发无关窗口视图更新。同期 35 秒静置对照中，主线程采样由 180 ms 降至 15 ms；此数据不是功耗或缩放帧率改善比例。**真实前台普通缩放与全屏的帧率/GPU配对尚未完成，不能宣称全部缩放卡顿已解决。**详见 [性能记录](docs/PERFORMANCE-v4.0.20.md)。

## 验证

```sh
bash Tests/run_build39.sh  # 真实音视频的播放、暂停及恢复
bash Tests/run_build44.sh  # 选择、原生滚动文字、封面完整性及界面布局
bash Tests/run_navigation19.sh  # 层级/滚动位置、重复点击 tab 与顶栏保护
```

测试使用合成/临时数据。开发或验证时不要以真实正式版资料库作为测试目录，不要提交用户媒体、偏好、访问书签或 iCloud 快照。

## 目录

- `Sources/`：应用源码
- `Resources/`、`Icons/`：应用图标与资源
- `MyPlayer.xcodeproj/`：Xcode 工程与共享 scheme
- `Scripts/`：构建号脚本
- `Tests/`：原生回归测试及合成测试夹具
- `docs/`：开发历史记录

## 许可与署名

本项目为**源码公开、非商业许可**项目，采用 [PolyForm Noncommercial 1.0.0](LICENSE)。非商业使用、修改和分发须遵循许可，并保留 [NOTICE](NOTICE) 中的作者声明：

> MyPlayer by oreo0 — https://github.com/oreo0/MyPlayer

**商业使用必须事先获得作者单独书面授权，获授权后仍须保留署名和项目链接。**详见 [商业授权规则](COMMERCIAL-LICENSE.md)。本项目未使用 MIT/GPL 授予通用商业使用权限。

反馈欢迎通过 [GitHub Issues](https://github.com/oreo0/MyPlayer/issues) 或 fight1212@outlook.com 提交。
