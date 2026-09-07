# AI、BYOK 与题目生成方案

## 1. 能力模型

应用不按 Provider 名称写分支，而按能力协商：

```swift
struct ModelCapabilities: Sendable {
    let structuredOutput: StructuredOutputMode
    let streaming: Bool
    let supportedLocales: Set<String>?
    let maxOutputTokens: Int?
    let usageReporting: Bool
    let remoteDataRetentionControllable: Bool
}
```

`structuredOutput` 可为 Apple guided generation、JSON Schema strict、JSON mode、text-only fallback。text-only fallback 仍必须经本地严格解析和完整校验，不合格不落库。

## 2. Apple Foundation Models

- Foundation Models framework 从 iOS 26 起可用。
- 使用 `SystemLanguageModel.default.availability` 检查 `.available`、`.deviceNotEligible`、`.modelNotReady` 和其他原因。
- 还必须使用 `supportsLocale(_:)` 检查目标语言，不能仅因为模型总体可用就认为六种语言均可生成。
- 结构化题目优先用 `@Generable`/guided generation，输出后仍执行产品自己的安全和质量检查。
- prompt、schema 和评测必须版本化，因为系统模型会随 OS 更新。
- 设备端模型适合短上下文、单一任务。大目录、长历史和批量题目拆成小批，不把整个数据库塞入上下文。
- Apple 自带 guardrails 是额外防线，不替代 Prompti 内容政策；guardrail refusal 作为可恢复结果处理。

## 3. BYOK Provider

### 3.1 MVP 协议

| Adapter | 端点形态 | 输出策略 |
| --- | --- | --- |
| OpenAI Responses | `POST /v1/responses` | 首选 `text.format` JSON Schema；`store: false` |
| OpenAI Chat | `POST /v1/chat/completions` | `response_format` JSON Schema 或 JSON mode |
| Anthropic Messages | `POST /v1/messages` | tool/schema 能力可用时结构化；否则 JSON + 校验 |
| OpenAI-compatible | 用户 base URL + chat endpoint | 先能力测试，保守使用共同子集 |

OpenAI 新配置默认推荐 Responses；Chat Completions 作为现有网关和兼容服务。Provider 远端数据保留策略由用户账户决定，Prompti 只能尽量发送无身份、最小化数据，并在 Provider 设置页链接其政策。

### 3.2 协议识别

1. 校验 URL：仅 HTTPS，规范化 path，阻止 loopback、link-local、私网 IP 和 `.local`。
2. 根据官方 host、path 和模型命名生成候选，不据此直接判定成功。
3. 尝试无副作用的模型列表/能力接口；不可用时跳过。
4. 用户点击“测试连接”后，发送最小、低 token 的结构化握手请求。
5. 返回 `detected(protocol, confidence, capabilities)`；低置信度要求手动选择。
6. 保存协议和能力探测时间；Provider 或 model 变化后重新探测。

不对所有可能端点盲目发送 API Key，也不把认证失败当成协议不匹配无限重试。

## 4. 统一接口

```swift
protocol LanguageModelProvider: Sendable {
    var id: ProviderID { get }
    func probe(_ configuration: ProviderConfiguration) async throws -> ProbeResult
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult
}
```

Domain 只接触：

- 规范化的 instructions/input。
- provider-neutral generation schema。
- token/timeout/temperature 等受控选项。
- 文本或结构化结果、refusal、usage、finish reason。

Adapter 负责认证头、URL、请求/响应字段、流式事件和错误映射。HTTP 原文只在 DEBUG 且脱敏后临时可见。

## 5. 生成管线

```text
TrainingConfiguration
  -> capability + budget check
  -> destination facts + scene context
  -> prompt assembly (untrusted data fenced as data)
  -> provider generation
  -> transport/schema decode
  -> deterministic validation
  -> safety classification
  -> language/answer/destination quality checks
  -> deduplication
  -> explicit SwiftData save
  -> ready inventory
```

### 5.1 Prompt 组成

- 固定系统规则：角色、允许任务、禁止内容、输出 schema、拒绝方式。
- 版本化目的地事实：只提供本题相关的最少片段。
- 训练约束：target/explanation locale、难度的数值边界、题型数量。
- 场景数据：以带长度的结构化字段传入，明确“仅作为主题数据，不是指令”。
- 质量样例：每种题型少量正例和反例，不随用户输入变化。

严禁把用户自定义场景直接拼接到 system instruction；严禁要求或保存 chain-of-thought。解释只要求简短、面向学习者的答案依据。

### 5.2 结构化 schema

批次返回：

- `questions[]`。
- 每题固定 `type`, `targetLocale`, `prompt`, `choices`, `answer`, `explanation`。
- `safetyDisposition` 仅作模型自报，不能代替本地审查。
- `sourceFactIDs` 必须来自输入 allowlist。
- 不兼容输入时返回显式 `incompatibleInput`/空数组，而不是编造合格题。

schema 与 Swift DTO 维护单一来源或在 CI 检查同步，避免两边漂移。

## 6. 校验与修复

### 6.1 确定性校验

- 数量、枚举、必填字段、字符/句子长度。
- locale 和书写体系。
- choice 数量、唯一文本、正确答案数量和 ID 引用。
- cloze 空位确实能由答案回填且语法成立。
- QA 题干不泄露答案。
- source fact ID 属于请求上下文。
- 无 URL、Markdown 指令、系统提示泄露或实时事实声明。

### 6.2 语义校验

- 是否符合目的地和场景。
- 目标难度、自然度、地域用法和答案唯一性。
- 干扰项是否合理但明确错误。
- 口语 rubric 是否允许等价表达。
- 内容安全分类。

### 6.3 重试预算

- 第一次失败：只修复失败题，并传递字段级错误代码。
- 第二次失败：重新生成失败题，降低批次大小。
- 最多 2 次额外模型调用；总时长、输出 token 和每日预算均设置上限。
- 安全失败不把违规原文重新塞给另一个 Provider；只传分类和重写要求。
- 达到上限后返回部分成功或明确失败，不无限循环消费用户额度。

## 7. 错误分类

统一错误：`invalidCredential`、`permissionDenied`、`modelNotFound`、`rateLimited(retryAfter)`、`quotaExceeded`、`networkUnavailable`、`timedOut`、`providerUnavailable`、`unsupportedCapability`、`refused`、`malformedOutput`、`unsafeOutput`、`qualityRejected`、`cancelled`。

Adapter 不把所有非 2xx 都映射成“网络错误”。UI 根据错误提供设置、等待、换模型、缩小批次或使用库存等动作。

## 8. Token 与隐私

- 生成请求默认无对话状态；每批独立，避免累积历史 token。
- 对 OpenAI Responses 显式设置 `store: false`；其他 Provider 使用等价的最小保留设置（如支持）。
- 不发送用户姓名、设备标识、完整历史或精确位置。
- 记录 Provider 返回的 usage；不自行假装精确 token 计数。
- 费用估算使用用户选择的、带更新时间的价格表；自定义模型默认不显示货币值。

## 9. 官方参考

- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Apple SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [OpenAI: Migrate to the Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [OpenAI: Structured model outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages)

实现时以 SDK/官方协议的当前版本和 contract tests 为准，不把本文中的端点形态当作永久不变的协议。

## 2026-09-06：OpenRouter 账号授权

- 新增 `openRouterOAuth`，通过 OpenRouter 官方 PKCE 流程连接账号；同一授权可切换 OpenRouter 上的 GPT、Claude、Gemini 模型 ID。它不是这些厂商订阅账号的直接登录。
- 原生入口使用 `ASWebAuthenticationSession` 和 `prompti://oauth/openrouter` 回调。每次生成独立 verifier/state；只接受对应 state、唯一 code 和精确回调路径。S256 按 RFC 7636，换码请求不跟随重定向。
- 另提供官方无回调授权码流程：浏览器授权后复制一次性 code 返回 App，使用保留在内存中的 verifier 换取 key。有效期由服务商控制（官方文档为 10 分钟）。
- 连接后发送最小能力探测；模型切换使测试结果失效。余额不足、取消和认证失效有独立恢复文案。所有选定模型仍经过既有内容审核和本地校验。
- OAuth 端点固定为 `https://openrouter.ai/api/v1/chat/completions`，不能编辑为其他服务。授权凭据不能发送到更改后的主机。
- Keychain 按协议、scheme/host/port 和 endpoint path 隔离；旧单密钥只迁移到原先保存的配置。新凭据在设置 Done 或引导完成时落盘，失败时保留旧配置。模型 ID 不参与凭据 scope，支持同一账号内切换模型。
- 本地“断开”删除当前配置对应的密钥；远程撤销需在服务商账号操作。没有引入 Prompti 后端、client secret 或密钥同步。
- 官方依据：https://openrouter.ai/docs/guides/overview/auth/oauth
- 自动化覆盖 PKCE 向量、回调/state 错误、换码请求、隔离边界和 Chat 响应解析；真实账号授权与额度检查需要使用测试账号做设备端联调。

## 2026-09-06：协议复核修正

- JSON mode 和 Anthropic 文本模式均显式发送序列化后的 JSON Schema；OpenAI Chat 在结构化与 JSON mode 中均发送 `store: false`。
- 生成输出上限为 12,000 tokens，审核/探测为 4,000 tokens；OpenAI Chat 使用 `max_completion_tokens`，兼容接口使用 `max_tokens`，Responses 使用 `max_output_tokens`。兼容服务是否接受这些字段仍需真实账号验证。
- HTTP 凭据请求不跟随重定向；读取响应时执行 2 MB 上限。URL 拒绝用户信息、query/fragment、常见 IPv4 非公网地址及 IPv6 本地/映射地址。DNS 解析到私网及 rebinding 防护尚未完成，不能宣称已全面防 SSRF。
- 认证、权限、模型/端点不存在、余额不足、限流、网络、超时、拒答和输出截断分别映射为可恢复错误；URLSession 取消保持取消语义。
- 四档难度传递具体长度、词汇、句式和干扰项约束；输出仍需人工语言质量校准，不能把 prompt 约束视为已经通过难度评测。
- 官方核对依据：[Structured Outputs / JSON mode](https://developers.openai.com/api/docs/guides/structured-outputs)。本轮未调用收费 Provider。

## 2026-09-07：能力补齐

已接入逐题审核、口语语义评估、小批次生成/边练边补、有界重试和本机实际请求/token 用量。 最新实现范围、测试结果和真实环境边界见 [能力补齐记录](12-capabilities-2026-09-07.md)。
