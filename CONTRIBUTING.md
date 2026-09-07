# Contributing to Prompti

感谢你改进 Prompti。提交代码前请先阅读 `.agents` 中的产品、安全和架构文档。

## 本地流程

1. 安装 Xcode 26.6+ 和 XcodeGen。
2. 运行 `xcodegen generate`。
3. 运行 `python3 Tools/CheckBrand.py` 和 PromptiTests。
4. 对 UI 改动至少检查一台 iPhone 模拟器在系统默认字号下的浅色、深色布局。超大字号等非常规显示设置不纳入当前验收范围。

## 内容贡献

新增目的地或场景时必须提供：稳定 ID、BCP-47 locale、可核验来源、审核日期和不依赖实时价格/时刻的常青事实。禁止提交政治宣传、露骨色情、极端主义、仇恨或违法指导内容。

## 代码要求

- 保持 Swift 6 strict concurrency 无警告。
- 不让 `ModelContext` 或 SwiftData `@Model` 实例跨 actor。
- API Key、Authorization header、完整 prompt/response 不得进入日志或 fixture。
- Provider 改动需要 request/response/error contract tests。
- 安全策略、统计口径或 iCloud schema 变化需要同步更新 `.agents` 文档。

## 品牌与 UI 贡献

先阅读 [品牌与 UI 开发规范](.agents/13-brand-and-ui-guidelines.md)。页面复用语义色、按钮、卡片、答案状态和输入组件，不单独定义配色或复制 Logo。标识修改从 `Tools/GenerateAppIcon.swift` 重新生成，并同步品牌文档。

提交时说明覆盖的页面和状态，并提供实际 App 的浅深色截图。品牌静态检查不能替代视觉检查；记录未完成的设备或运行时验证。默认字号为当前验收基线，已有无障碍适配应保留。

相关 PR 会触发 `Brand contract` 工作流，在 CI 中执行相同的品牌检查。

## Pull Request

PR 描述应包括行为变化、验证命令、UI 截图（如适用）、数据迁移影响、模型成本影响和安全影响。
