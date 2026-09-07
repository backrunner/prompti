# 测试、评测与发布方案

## 1. 测试层级

### 1.1 Unit Tests

- `TrainingConfiguration` 校验和难度约束。
- 自定义场景 Unicode 归一化、grapheme 限制和注入规则。
- Prompt builder snapshot：用户内容不能进入 system instruction。
- 每个 Provider 的 request encoding、response/refusal/usage/error decoding。
- schema、choice 唯一性、cloze 回填、fact allowlist、内容 hash。
- 统计口径、跨时区 `localDayKey`、streak 和 mastery 重建。
- 预算、库存低水位和重试策略。
- cancellation 不被映射成错误提示。

使用 Swift Testing；时间、UUID、locale、calendar、network 和 model provider 均注入可控依赖，禁止依赖 sleep 的脆弱测试。

### 1.2 Contract Tests

- 本地 mock HTTP server 覆盖 OpenAI Responses、Chat、Anthropic 和兼容协议。
- Fixture 包含成功、流式片段、refusal、截断 JSON、超大响应、401、403、429、5xx、timeout 和未知字段。
- CI 不使用真实 API Key，不调用收费模型。
- Provider 官方协议变化通过手动/定期 compatibility job 检查，使用专门低额度测试账户且不在 fork PR 运行。

### 1.3 Persistence Tests

- in-memory SwiftData CRUD、delete rule、查询与聚合。
- 真实磁盘 store 的 schema migration fixture。
- CloudKit 约束 lint：无 unique、属性有 default/optional、关系 optional。
- 两设备逻辑模拟：重复题、乱序 attempt、report 单调合并和删除 tombstone。
- iCloud 真实同步在 development container 和至少两台设备/模拟器人工验证；不能把它伪装成完全稳定的普通 CI 单测。

### 1.4 UI Tests

- Apple 模型 available / hidden / notReady / unsupportedLocale 四种引导。
- BYOK 连接成功、Key 错误、协议不确定和模型不支持 schema。
- 生成取消、部分成功、失败重试和库存练习。
- 完形、QA、口语权限拒绝、低置信转写、跳过和报告。
- 错题复习、统计和 iCloud 离线提示。
- 默认 Dynamic Type、VoiceOver identifiers、Reduce Motion、深色/浅色和较小屏幕。按当前 UI 验收约定，不把非常规超大字号作为本轮门槛，保留已有无障碍适配；品牌视觉验收范围按 [`13-brand-and-ui-guidelines.md`](13-brand-and-ui-guidelines.md) 记录。

## 2. Prompt 与内容评测

建立 `PromptiPromptEvals`，固定输入、允许答案和评审 rubric，不直接以“模型说好”作为通过。

### 2.1 评测矩阵

- 语言：en、ja、ko、ru、de、es。
- 目的地：每种语言至少两个城市；包含同一国家不同城市。
- 场景：所有通用场景 + 每城至少两个特色场景。
- 难度：四档。
- 题型：cloze、QA、spoken QA。
- Provider：Apple（支持时）+ 每个 BYOK adapter 的一个代表模型。

完整笛卡尔积用于夜间/发布评测；PR 运行分层抽样集控制成本。

### 2.2 自动指标

- schema 通过率、一次通过率、修复率、拒绝率。
- 唯一答案率、重复率、fact 引用有效率。
- 语言识别一致、长度/难度约束。
- 安全 corpus 的阻止率和合法边界场景放行率。
- 首题延迟、每道合格题 token、部分成功率。

### 2.3 人工审查

目标语言母语或高水平审查者评估：自然度、礼貌程度、地域真实性、答案唯一性、教学价值、文化刻板印象和安全边界。

发布建议门槛：

- schema/确定性校验 100% 才能展示。
- 高风险安全集阻止率 100%；任何漏放阻断发布。
- 合法边界集误杀率需要按类别审查，不以降低安全门槛换数字。
- 人工抽样“可直接使用”通过率 >= 95%。
- 单选唯一最佳答案通过率 >= 99%。

## 3. 性能与稳定性

- 冷启动不等待网络和 CloudKit。
- 10000 条 attempt 的进度页分页/聚合无明显主线程卡顿。
- 生成、JSON 校验、音频转写期间 Main Thread Checker 无违规。
- Instruments 检查内存、SwiftUI 更新、网络和 energy。
- 模拟后台 task expiration、低电量、无网、Provider 429 和 App 被系统终止。
- 音频 session 中断后可恢复，临时录音无泄漏。

## 4. 安全与隐私测试

- secret scanning、日志快照断言不含 key/header/body。
- 自定义 endpoint 覆盖 loopback、IPv4/IPv6 私网、DNS rebinding、重定向到私网、HTTP downgrade。
- Unicode 隐形字符、混淆角色、多语言注入、超长 JSON 和深嵌套响应 fuzz。
- 删除全部数据和账户切换不会把旧 iCloud 数据上传到新账户。
- Privacy Manifest、权限文案、App Privacy Answers 与真实网络行为一致。

## 5. CI 流水线

每个 PR：

1. 格式/静态检查和 secret scan。
2. Debug build，Swift 6.2 strict concurrency warnings as errors。
3. Unit、contract、persistence tests。
4. 抽样 prompt/schema 离线 fixtures；默认不产生模型费用。
5. UI smoke tests 和 accessibility audit。
6. 目的地目录 schema/source/ID lint。

夜间或发布候选：受控真实 Provider compatibility、完整 prompt eval、迁移 fixture、两设备 iCloud、性能和人工内容抽检。

## 6. 发布门槛

- P0 验收项完成且无高优先级缺陷。
- 六种目标语言的核心场景均通过人工抽样。
- Apple 不可用设备能完整完成 BYOK-only 流程。
- 没有密钥进入 repo、日志、iCloud、崩溃报告或导出包。
- 所有用户可见题目均经过当前 policy/schema/quality gate。
- iCloud 不可用时不丢本地作答。
- 后台预生成默认关闭且成本说明可见。
- 开源许可证、第三方 notices、贡献指南、安全报告渠道和隐私政策齐备。
