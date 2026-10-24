# MyPlayer

一个纯净的本地 macOS 音频和视频播放器，使用 AI 协助制作。
A pure, local music and video player for macOS, made with Love ❤️ and ChatGPT.

**当前预发布版本：MyPlayer 4.0 (17) · MyPlayer Beta**
**系统要求：macOS 27 或更新版本；Apple Silicon（arm64）。不支持 Intel Mac。**

[下载安装包](https://github.com/oreo0/MyPlayer/releases/tag/v4.0.0-beta.17) · [更新记录](CHANGELOG.md) · [用户数据](USER-DATA.md) · [参与贡献](CONTRIBUTING.md)

## 下载与安装

1. 在 [Releases](https://github.com/oreo0/MyPlayer/releases) 下载 `MyPlayer.dmg`，打开后将 `MyPlayer.app` 拖到 Applications。也可下载 ZIP 解压安装。
2. 替换旧测试版前，请先完全退出应用。应用包名称保持 `MyPlayer.app`，应用身份为 `MyPlayer Beta`；版本号在“关于 MyPlayer”中显示为“版本4.0 (17)”。
3. 本次发布使用临时签名，**未经过 Developer ID 签名和 Apple 公证**；下载后 macOS 可能提示无法验证开发者。不要将此发布包视为 App Store 或已公证版本。
4. 可使用发布附件 `SHA256SUMS.txt` 校验下载文件。

## 功能

- 本地音频、视频播放；资料库列表及按专辑、艺人、文件夹浏览的封面视图。
- 我的合集、喜欢、播放队列、文件夹扫描与自定义快捷键。
- LRC 歌词及 SRT/VTT 视频字幕、播放进度和会话恢复。
- SwiftUI 与 AppKit 原生组件、Apple 平台媒体框架、封面取色及极光光效。
- 毛玻璃、深层磨砂、纯色背景及明暗外观；保留主题强调色。
- 测试版首次迁入正式版资料库和设置，随后使用独立目录保存。

## 测试版数据与 iCloud

测试版 Bundle ID：`com.myplayer.native.beta`。本地数据位于 `~/Library/Application Support/MyPlayer Beta/`，与正式版的 `MyPlayer/` 目录分开。首次启动会复制可用的正式版数据，之后修改测试版不回写正式版。

提供 iCloud Drive 文件备份与重装恢复逻辑，覆盖资料库记录、设置、封面、歌词/字幕副本、合集、队列与播放状态；**音乐和视频原文件不上传，仍保留原位置**。

**已知限制：**本地备份/恢复流程已用合成数据验证；当前开发环境的 iCloud 服务返回账户访问错误，尚未证实服务器上传和跨设备恢复成功。请勿将这一功能作为唯一备份。详情见 [USER-DATA.md](USER-DATA.md)。

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

构建输出位于仓库上一级的 `work/ReleaseDerivedData/`；ZIP 位于上一级 `outputs/`。`BuildNumber.txt` 保留当前构建号 17，**每次 Xcode 构建自动加一**，从这份源码下一次构建的编号为 18。GitHub 的版本标签用于标识本次发布快照，不会固定后续构建号。

## 验证

```sh
bash Tests/run_build39.sh  # 真实音视频的播放、暂停及恢复
bash Tests/run_build44.sh  # 选择、原生滚动文字、封面完整性及界面布局
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
