# 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [LICENSE](LICENSE)、[NOTICE](NOTICE) 和 [商业授权规则](COMMERCIAL-LICENSE.md)。非商业修改和分发需保留作者署名；商业使用需另行书面授权。

- 提交问题时说明应用版本、macOS 版本、Apple Silicon 型号、背景/明暗模式、重现步骤及预期行为。
- 截图或日志中请移除个人路径、媒体内容、访问书签和其他私人数据。
- 修改保持聚焦；性能修复不要顺带改动强调色、圆角、材质或其他交互。
- 保留 `MyPlayer.app` 包名、Beta Bundle ID 和既有用户记录；测试仅使用合成数据与临时目录。
- 选择相关修改不得在每次选中时插入/删除行子视图或强制整表重绘，也不得持续 KVO 回写行高。
- 播放恢复相关修改运行 `bash Tests/run_build39.sh`；选择、封面或滚动文字相关修改运行 `bash Tests/run_build44.sh`。
- PR 描述需交代问题、最终行为、验证方法及已知限制。提交前运行 `git diff --check`。

贡献默认按仓库现有许可提交；提交贡献不代表授予任何人通用商业使用权限。
