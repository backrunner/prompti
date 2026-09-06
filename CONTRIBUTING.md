# Contributing to Prompti

感谢你改进 Prompti。提交代码前请先阅读 `.agents` 中的产品、安全和架构文档。

## 本地流程

1. 安装 Xcode 26.6+ 和 XcodeGen。
2. 运行 `xcodegen generate`。
3. 运行 PromptiTests。
4. 对 UI 改动至少检查一台 iPhone 模拟器的浅色、深色和最大 Dynamic Type。

## 内容贡献

新增目的地或场景时必须提供：稳定 ID、BCP-47 locale、可核验来源、审核日期和不依赖实时价格/时刻的常青事实。禁止提交政治宣传、露骨色情、极端主义、仇恨或违法指导内容。

## 代码要求

- 保持 Swift 6 strict concurrency 无警告。
- 不让 `ModelContext` 或 SwiftData `@Model` 实例跨 actor。
- API Key、Authorization header、完整 prompt/response 不得进入日志或 fixture。
- Provider 改动需要 request/response/error contract tests。
- 安全策略、统计口径或 iCloud schema 变化需要同步更新 `.agents` 文档。

## Pull Request

PR 描述应包括行为变化、验证命令、UI 截图（如适用）、数据迁移影响、模型成本影响和安全影响。

