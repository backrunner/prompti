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

## 2026-09-09：API Key 快捷配置（取代账号 OAuth）

- 按用户决定移除全部 OpenRouter OAuth / PKCE、授权码页面、浏览器登录和 App scheme 回调注册。FlowDown 当前公开源码的云模型使用端点 + Bearer 凭据，没有发现 OAuth 实现；证据及旧尝试历史见 [连接方式复核](../Documentation/OpenRouter-Integration-Options.md)。
- 引导和设置共用 API Key 配置：选择服务商，填入 API Key，从只显示名称的菜单选择模型，或选择“输入模型 ID”。常用服务商预填地址；自定义兼容接口保留地址和模型 ID 输入。展开选项保留详细说明，OpenRouter 另提供 keys 页面及推荐数据来源链接。
- OpenRouter 运行时类型更名为 `openRouter`，仅保留 `openRouterOAuth` 作为历史持久化 raw value，保证已保存配置、使用记录及 Keychain scope 不变。这不是仍启用 OAuth；项目不再包含浏览器会话或换码端点。
- OpenRouter 固定使用 `https://openrouter.ai/api/v1/chat/completions` 与用户 API Key 的 Bearer header；固定预设不能修改为其他主机。其他服务商继续使用现有 Responses / Chat / Messages 协议。
- API Key、端点或模型改变会使连接验证失效。填好后测试连接，完成最小能力探测再保存；缺少 key 或模型时不能测试，未经验证不能完成引导。认证失败提示更新 API Key，余额不足和模型不可用沿用既有恢复行为。
- Keychain 继续按协议、scheme/host/port 和 endpoint path 隔离，模型 ID 不参与 scope；密钥仅保存在本机。输入 key 去除首尾空白后探测，在设置 Done 或引导完成时才落盘，失败保留旧配置。原来已连接的 OpenRouter key 仍可使用，无需重新授权或强制清除。
- 本地“断开”删除当前配置密钥；远程撤销在服务商账号进行。没有引入服务端、client secret、密钥同步或学习数据迁移；内容审核、练习统计不变。
- 回归覆盖历史配置解码和 scope、预设地址、用户输入 key/model 的实际请求构造及认证错误，以及中英文选模/手填/空字段限制。完整验证记录见 [API Key 配置验收](../Documentation/API-Key-Setup.md)。真实服务商账号、额度和付费模型调用不由离线测试证明。

## 2026-09-06：协议复核修正

- JSON mode 和 Anthropic 文本模式均显式发送序列化后的 JSON Schema；OpenAI Chat 在结构化与 JSON mode 中均发送 `store: false`。
- 生成输出上限为 12,000 tokens，审核/探测为 4,000 tokens；OpenAI Chat 使用 `max_completion_tokens`，兼容接口使用 `max_tokens`，Responses 使用 `max_output_tokens`。兼容服务是否接受这些字段仍需真实账号验证。
- HTTP 凭据请求不跟随重定向；读取响应时执行 2 MB 上限。URL 拒绝用户信息、query/fragment、常见 IPv4 非公网地址及 IPv6 本地/映射地址。DNS 解析到私网及 rebinding 防护尚未完成，不能宣称已全面防 SSRF。
- 认证、权限、模型/端点不存在、余额不足、限流、网络、超时、拒答和输出截断分别映射为可恢复错误；URLSession 取消保持取消语义。
- 四档难度传递具体长度、词汇、句式和干扰项约束；输出仍需人工语言质量校准，不能把 prompt 约束视为已经通过难度评测。
- 官方核对依据：[Structured Outputs / JSON mode](https://developers.openai.com/api/docs/guides/structured-outputs)。本轮未调用收费 Provider。

## 2026-09-07：能力补齐

已接入逐题审核、口语语义评估、小批次生成/边练边补、有界重试和本机实际请求/token 用量。 最新实现范围、测试结果和真实环境边界见 [能力补齐记录](12-capabilities-2026-09-07.md)。

## 2026-09-08：快速模型与连接预设

- 引导和设置共用 `ModelConnectionView` / `ModelRecommendations`。默认推荐快速、低成本的文本模型：OpenAI GPT-5.6 Luna、Gemini 3.8 Flash / 3.5 Flash-Lite、DeepSeek V4 Flash、Claude Haiku 4.5；OpenRouter 另含 GLM、Qwen 等快速模型。未将旗舰、图像、音频、医学或金融专用模型作为默认练习模型。
- `ProviderPreset` 是连接快捷方式，继续使用既有 Responses / Chat / Messages 协议与凭据隔离。Gemini 使用官方 OpenAI 兼容的完整 `v1beta/openai/chat/completions` 端点；完整端点不再追加 `/v1`。不引入新的持久化 Provider 类型。
- `OpenRouterRecommendations.json` 是带日期、来源和许可的近 7 天请求次数快照。只在已核实的快速模型候选中按 `weeklyRequests` 降序排列，未知调用量排在末尾；并不宣称是所有模型的全量请求排行榜。OpenRouter 网站可见榜单主要按 token 排名，不能直接把其名次当成调用次数排名。按 2026-09-09 的界面约定，下拉只显示模型名，不展示调用次数或按用量分组；排序与快照元数据保留。
- 连接区域默认保留服务商、模型、连接按钮和一句数据处理/费用提示。移除营销标语和排名说明，将完整凭据/隐私说明及 OpenRouter CC BY 4.0 来源链接收进“更多连接选项”。连接状态与错误仍就地显示。
- `Tools/UpdateModelRecommendations.py` 从 `/api/v1/models` 核对模型 ID、文本输出与 canonical slug，并读取公开排名页 `rankings/models/view=week` 数据中的 `count`。页面内嵌数据不是稳定 API，格式变化、缺少请求数或全部匹配失败时停止且保留原快照；绝不以 token 数代替请求数。App 运行时只读取内置资源，不抓网页，不在 landing 请求用户凭据或产生模型调用。
- 每次发布前刷新快照，复核候选型号。新增版本不能仅凭名称自动收入；核对官方型号、用途、结构化输出后维护名单。已存模型、手填 ID 和连接验证保持原行为，选择不同模型后必须重新验证。
- 数据来源：Source: OpenRouter (openrouter.ai/rankings), as of 2026-09-06. Licensed under CC BY 4.0. 当前快照读取的是公开流量，缺少请求数不代表零调用。
- 官方型号与接口依据：[OpenAI 模型目录](https://developers.openai.com/api/docs/models)、[GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)、[Gemini 模型](https://ai.google.dev/gemini-api/docs/models)、[Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)、[Claude 模型](https://platform.claude.com/docs/en/models/overview)、[DeepSeek 模型](https://api-docs.deepseek.com/quick_start/pricing)、[OpenRouter 数据口径](https://openrouter.ai/docs/cookbook/administration/data-api)。账号权限、额度及模型服务质量仍需真实账号验证；本轮不进行收费推理调用。
