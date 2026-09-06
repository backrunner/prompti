# 决策、开放问题与交付路线

## 1. 已建议的架构决策

| ID | 决策 | 原因 |
| --- | --- | --- |
| ADR-001 | 最低 iOS 18，iOS 26 条件启用 FoundationModels | 保留更广设备覆盖，同时利用 Apple 设备端模型 |
| ADR-002 | Swift 6.2 严格并发、SwiftUI、SwiftData + CloudKit | 原生能力、可维护性、iCloud 私有数据同步 |
| ADR-003 | 单 App target + feature-first，暂不拆大量 package | MVP 规模下减少构建和依赖复杂度 |
| ADR-004 | Provider-neutral protocol + 独立 REST adapters | BYOK 协议差异被隔离，便于 fixture 测试 |
| ADR-005 | 目的地事实来自版本化目录，LLM 只生成练习 | 降低事实幻觉和时效风险 |
| ADR-006 | 作答事件 append-only，统计派生 | 适应 CloudKit 最终一致和多设备冲突 |
| ADR-007 | Keychain `ThisDeviceOnly`，密钥不进 iCloud | 明确优先保护凭据，换机需重新配置 |
| ADR-008 | 后台预生成默认关闭、有限预算 | BYOK 成本透明且符合 iOS 后台限制 |
| ADR-009 | 口语 MVP 为转写 + 语义反馈，不宣称发音测评 | 避免未经校准的误导性评分 |
| ADR-010 | Apache-2.0 作为建议开源许可证 | 相比 MIT 增加明确专利授权；需项目所有者最终确认 |

## 2. 发布前必须确认

| 问题 | 建议默认 | 影响 |
| --- | --- | --- |
| 最低系统版本 | iOS 18 | 设备覆盖、Speech fallback、测试矩阵 |
| UI 首发语言 | 英文 + 简体中文 | String Catalog、商店素材、人工 QA |
| 首批目的地 | 每种目标语言 2 个代表城市，约 12 个 | 目录编辑和语言审查成本 |
| Provider 范围 | Apple + OpenAI Responses/Chat + Anthropic + compatible | MVP 周期、协议测试量 |
| “政治敏感”边界 | 采用安全文档中的可执行定义 | 合法旅行内容误杀、App 审核和社区治理 |
| iCloud 关闭开关 | MVP 不提供 App 内开关 | 双 store 迁移复杂度 |
| 自定义场景 LLM 审核成本 | 每次保存前一次最小分类请求 | BYOK 成本和失败体验 |
| partial 统计方式 | 单列，不折算正确率 | 统计解释性 |
| 许可证 | Apache-2.0 | 贡献者和依赖兼容 |
| 最低年龄与商店分级 | 4+，但以最终内容政策/商店问卷为准 | 安全策略和隐私文案 |

## 3. MVP 交付阶段

### M0：工程地基

- Xcode 工程、Swift 6.2 strict concurrency、CI、String Catalog、DesignSystem。
- SwiftData V1 schema、CloudKit container、Keychain、目的地目录 schema。
- App shell、四 Tab、依赖装配和 mock services。

完成定义：无真实模型也能用 fixtures 走通导航、保存、同步状态和示例答题。

### M1：AI 配置与生成

- Apple capability gate。
- OpenAI Responses/Chat、Anthropic、compatible adapters。
- Provider probe、Keychain、统一错误。
- prompt/schema、确定性校验、重试和部分成功。

完成定义：每个 adapter 通过 contract fixtures；支持设备与 BYOK-only 设备均能生成合格示例题。

### M2：练习闭环

- 配置、完形、QA、跳过、报告、错题、历史。
- attempt 事件、统计、streak。
- 多目的地/locale 与难度约束。

完成定义：从首次启动到完成一组题、重启后复习，数据完整可解释。

### M3：口语与预生成

- TTS、录音、STT、语义 rubric、undetermined。
- 前台库存维护、BGTask、预算和成本提示。
- 权限、音频中断、后台 expiration。

完成定义：无权限、低置信、被系统挂起均能优雅降级，不误计错题或超预算循环。

### M4：安全、评测与发布

- 输入/输出 policy、adversarial corpus、人工语言审核。
- 两设备 CloudKit、迁移、性能、无障碍、隐私清单。
- 开源许可证、README、CONTRIBUTING、SECURITY、第三方 notices。

完成定义：满足 [`09-testing-and-release.md`](./09-testing-and-release.md) 的发布门槛。

## 4. 主要风险

| 风险 | 概率/影响 | 缓解 |
| --- | --- | --- |
| 多 Provider 结构化输出差异 | 高/高 | 能力协商、独立 adapter、fixture contract、严格本地校验 |
| 目的地内容事实幻觉 | 中/高 | 编辑目录、fact allowlist、禁止实时事实、报告隔离 |
| 安全误杀/漏放 | 中/高 | 明确定义、输入输出双检、多语言 adversarial + 人工复盘 |
| BYOK 成本失控 | 中/高 | 默认关闭预取、预算、低并发、最多两次修复、usage 展示 |
| iCloud 冲突与延迟 | 高/中 | append-only attempt、派生统计、optional 关系、应用层去重 |
| Apple 模型语言/设备限制 | 高/中 | `availability + supportsLocale` 运行时判断、完整 BYOK fallback |
| 口语结果误导 | 中/高 | 低置信 undetermined、不宣称发音分、显示转写、可重试 |
| 开源目录维护成本 | 中/中 | schema、来源、审核日期、社区 PR 模板和责任人 |

## 5. 后续 ADR

实现遇到以下变化时新增独立 ADR，而不是只改代码：

- 更改最低 iOS 或 Swift 版本。
- 引入第三方架构、网络、数据库或语音 SDK。
- 让 API Key 跨设备同步或引入 Prompti 服务端。
- 新增远端目的地目录、用户内容发布或账号系统。
- 改变安全政策、统计口径、原始录音保留或后台默认值。
- 从单 target 拆分 Swift package。

