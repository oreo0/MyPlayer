# MyPlayer v4.0.24 性能修复

基于 v4.0.23；下个版本 v4.0.25。保留 SwiftUI + AppKit、macOS 27 原生视觉、封面取色、原有动画与布局。仅缩小焦点动作和菜单状态的更新范围。

## 定位证据

- 已采样用户正在运行的 `/Applications/MyPlayer.app` v4.0.23 (35)，未修改该应用及数据。5 秒采样中，主线程 2235 个样本持续位于窗口布局链路；2089 个样本进入 NSHostingView.layout，包含 ToolbarBridge 更新和 AttributeGraph 的结构比较。这个采样支持主线程界面布局阻塞，不能单凭它断言 GPU 根因。
- `_printChanges()` 诊断记录在播放状态变化后继续报告 `_collectionActions changed`，连带整个 ContentView 和顶栏更新。高频进度已经由独立 PlaybackClock 承载，因此没有再次改造播放器时钟。
- 修复前后的相同原生 NSWindow/NSHostingView 焦点实验：40 次独立子视图的集合动作变化，v4.0.23 触发 ContentView 重建 40 次，修复后 0 次。该数字是视图重建计数，不是帧率，也不代表所有负载下的总 CPU 降幅。

## 修复

- 将 ContentView 上的 collectionActions FocusedValue 订阅移到两个独立的 CollectionToolbarControls 中。资料库选中、焦点和菜单动作变化不再通过合集操作反复更新整个窗口；按钮行为和布局不变。
- InteractionActivity 保留菜单和编辑输入范围管理，但 ContentView 不再以 ObservedObject 方式监听所有菜单状态。只有播放页控制栏消费去重后的保持显示信号，资料库页面的菜单跟踪不会写回整窗界面状态。
- 未修改受保护的 v4.0.18 全屏顶栏背景实现，未降低光效或动画质量。

## 验证与边界

Tests/run_release24.sh 为新增焦点回归；可通过 MYPLAYER24_BASELINE 指向 v4.0.23 源码并传入 --baseline 进行同条件对照。测试源码只在临时副本中注入计数器，不在发布代码中保留诊断日志或性能开关。

实际交互使用独立应用标识、独立临时数据目录和 300 项合成资料库，媒体为本机生成的静音测试文件；封面只读取副本。正式版应用、资料库、设置、媒体和旧云端备份没有被修改。

## 最终结果

- 用户实际操作反馈：第一轮仅缩小菜单状态更新范围时“有改善，但仍有卡顿”；第二轮同时隔离合集焦点动作后，在 MyPlayer Verification24 中播放、滚动、选歌和打开右键菜单，用户确认“已经顺畅，没有无响应”。
- Release 编译、Release24 与 v4.0.23 基线对照、Release23、Release22、Navigation19、Build44 全部通过。
- Release22 验证保留的视频视图与页面切换、原生标题滚动及外观菜单；Build44 验证 200 次真实表格选择不插入高亮视图、2,000 次跑马灯更新不重启动画。
- 正式交付代码不包含临时数据路径、合成资料库、性能开关、_printChanges 或计数器。安装包使用本机临时签名。
