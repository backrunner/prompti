# Prompti 产品与工程文档

状态：Draft v0.1  
更新日期：2026-07-12

本目录是 Prompti 的产品、设计和工程基线。实现前应先处理
[`10-decisions-and-roadmap.md`](./10-decisions-and-roadmap.md) 中标记为“发布前必须确认”的事项；任何改变用户数据、内容安全或 AI Provider 协议的实现，都应同步更新对应文档。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [`01-product-requirements.md`](./01-product-requirements.md) | 产品目标、范围、功能需求、验收标准 |
| [`02-user-experience.md`](./02-user-experience.md) | 信息架构、核心流程、异常状态、视觉与无障碍 |
| [`03-domain-and-data-model.md`](./03-domain-and-data-model.md) | 领域对象、题型、统计口径、SwiftData/CloudKit 模型 |
| [`04-modules-and-architecture.md`](./04-modules-and-architecture.md) | 模块边界、依赖方向、工程目录和并发模型 |
| [`05-ai-byok-and-generation.md`](./05-ai-byok-and-generation.md) | Apple Foundation Models、BYOK、协议适配和生成管线 |
| [`06-safety-and-quality.md`](./06-safety-and-quality.md) | 输入过滤、内容安全、质量审查、提示词防注入 |
| [`07-persistence-and-icloud.md`](./07-persistence-and-icloud.md) | 本地存储、iCloud 同步、Keychain、冲突与迁移 |
| [`08-technical-implementation.md`](./08-technical-implementation.md) | Swift/iOS 技术选型、接口草案、后台与口语实现 |
| [`09-testing-and-release.md`](./09-testing-and-release.md) | 测试策略、评测集、CI、发布门槛和可观测性 |
| [`10-decisions-and-roadmap.md`](./10-decisions-and-roadmap.md) | 决策记录、开放问题、MVP 分期和风险 |

## 已采用的基线

- 产品名：Prompti；开源、原生 iOS、Swift 编写。
- 推荐工具链：Xcode 26+、Swift 6.2 严格并发检查。
- 建议最低系统：iOS 18；iOS 26+ 且设备、地区、语言均支持时才显示并默认使用 Apple 系统模型。
- UI：SwiftUI；持久化：SwiftData + CloudKit private database；密钥：Keychain，仅本机保存。
- 首期目标语言：英语、日语、韩语、俄语、德语、西班牙语。
- 上述语言并不都属于拉丁文字：首期实际覆盖 Latin、日文、Hangul、Cyrillic 多种书写体系。
- AI 输出不是事实来源。目的地事实由版本化目录提供，模型负责据此生成练习。
- 用户跳过、模型拒答、生成失败、题目被隔离均不计入答错统计。
- 后台预生成默认关闭，必须先展示可能产生额外 token/费用的说明。

## 规范词

- **必须**：MVP 发布门槛。
- **应该**：默认实现；偏离时需要在 PR 中说明。
- **可以**：增强项，不阻塞 MVP。
- **不做**：明确的非目标，避免范围蔓延。

