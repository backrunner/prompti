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
  -> provider generation          # 每次 1 题，远端最多 3 条链并发；Apple 串行
  -> transport/schema decode
  -> deterministic validation
  -> safety classification
  -> language/answer/destination/tourist-role quality checks   # 每题独立审核
  -> deduplication                # 跨并发批次按 contentSignature 去重
  -> approved 事件逐题下发 → 即时落库
  -> ready inventory
```

每题是一条独立的 generate → review 链；生成和审核顺序执行，其他题互不阻塞。第一道过审题保存后即可开练，其余继续补足。审核打回、本地结构不合格、重复、拒答、截断或可恢复模型错误在原任务内重新生成该题，每个候选位置最多 2 次重试（共 3 次尝试）。外显进度保持最远阶段；达到题量后取消剩余工作。单次生成/审核各 120s，整组按题数设置 180–600s 硬截止；任一上限先到就停止，保留已保存题目。

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

- 每道候选初次失败后只重生成该题，最多再尝试 2 次；合格题不重新生成。
- 每次尝试包含一次单题生成与必要的一次单题审核；结构不合格和重复候选不进入付费审核。
- 原任务自动重试覆盖审核打回、格式/截断、拒答、超时和 Provider 暂时不可用；认证、权限、余额、限流、配置、网络不可达和取消不会自动追加调用。总时长、输出 token 和每日预算均有上限。
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
- 引导和设置共用 API Key 配置：选择服务商，填入 API Key，从只显示名称的菜单选择模型，或选择“输入模型 ID”。常用服务商预填地址；自定义兼容接口保留地址和模型 ID 输入。2026-09-18 移除仅以说明为主的“更多连接方式”折叠区；OpenRouter keys 页面及推荐数据来源链接直接显示，保留一句数据处理/费用提示。
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

- 引导和设置共用 `ModelConnectionView` / `ModelRecommendations`。默认推荐快速、低成本的文本模型：OpenAI GPT-5.6 Luna、Gemini 3.8 Flash / 3.5 Flash-Lite、DeepSeek V4.1 Flash、Claude Haiku 4.5；OpenRouter 另含 GLM、Qwen 等快速模型。未将旗舰、图像、音频、医学或金融专用模型作为默认练习模型。
- `ProviderPreset` 是连接快捷方式，继续使用既有 Responses / Chat / Messages 协议与凭据隔离。Gemini 使用官方 OpenAI 兼容的完整 `v1beta/openai/chat/completions` 端点；完整端点不再追加 `/v1`。不引入新的持久化 Provider 类型。
- `OpenRouterRecommendations.json` 是带日期、来源和许可的近 7 天请求次数快照。只在已核实的快速模型候选中按 `weeklyRequests` 降序排列，未知调用量排在末尾；并不宣称是所有模型的全量请求排行榜。OpenRouter 网站可见榜单主要按 token 排名，不能直接把其名次当成调用次数排名。按 2026-09-09 的界面约定，下拉只显示模型名，不展示调用次数或按用量分组；排序与快照元数据保留。
- 连接区域默认保留服务商、模型、连接按钮和一句数据处理/费用提示。移除营销标语和排名说明。2026-09-18 起不再显示“更多连接方式”；OpenRouter API Key 与 CC BY 4.0 来源链接直接显示。连接状态与错误仍就地显示。
- `Tools/UpdateModelRecommendations.py` 从 `/api/v1/models` 核对模型 ID、文本输出与 canonical slug，并读取公开排名页 `rankings/models/view=week` 数据中的 `count`。页面内嵌数据不是稳定 API，格式变化、缺少请求数或全部匹配失败时停止且保留原快照；绝不以 token 数代替请求数。App 运行时只读取内置资源，不抓网页，不在 landing 请求用户凭据或产生模型调用。
- 每次发布前刷新快照，复核候选型号。新增版本不能仅凭名称自动收入；核对官方型号、用途、结构化输出后维护名单。已存模型、手填 ID 和连接验证保持原行为，选择不同模型后必须重新验证。
- 数据来源：Source: OpenRouter (openrouter.ai/rankings), as of 2026-09-06. Licensed under CC BY 4.0. 当前快照读取的是公开流量，缺少请求数不代表零调用。
- 官方型号与接口依据：[OpenAI 模型目录](https://developers.openai.com/api/docs/models)、[GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)、[Gemini 模型](https://ai.google.dev/gemini-api/docs/models)、[Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)、[Claude 模型](https://platform.claude.com/docs/en/models/overview)、[DeepSeek 模型](https://api-docs.deepseek.com/quick_start/pricing)、[OpenRouter 数据口径](https://openrouter.ai/docs/cookbook/administration/data-api)。账号权限、额度及模型服务质量仍需真实账号验证；本轮不进行收费推理调用。

## 2026-09-16：并发批次与边生成边练习

- `QuestionGenerationService.generate` 使用有界 task group：远端 3 题/批、最多 3 批并行，Apple 2 题/批、串行。每批依次生成、本地校验、共享候选去重、逐题审核，再增量下发通过题。不同批次轮换选中场景和沟通目标；所有模式使用相同质量/安全标准。截止 180s，单次生成/审核各 60s；Provider 错误后不再追加批次，但保留其他进行中批次的通过题。凑齐后停止调度并取消剩余工作，返回和事件数量均不超过目标。
- `PracticeSessionState` 持有唯一有界的补全任务：`.approved` 事件到达即落库并追加到 `records`；`furthestStage` 记录管线最远阶段，内部重生成不回退外显进度。`PracticeFlow` 在生成与练习路由间共享同一 session，`GenerationView` 在已有 min(3, count) 题过审时自动进入练习页。
- 题目语义改为对话式：选择题 prompt 是当地人对学习者说的一句话，选项是可说的应答（唯一最佳），`translation` 改作讲解语言的上下文说明（谁在说话、在哪里、学习者要做什么），不得复述题干；cloze 是带 1–3 个空位的自然对话/话语，挖空关键用词或固定搭配；spoken prompt 为讲解语言的指令句。本地校验新增 translation≠prompt、选择题选项/答案≠prompt；审核 prompt 同步要求拒绝元题（"which sentence…"）与近义干扰项。
- UI：生成页为"场景信息→生成→审核"三段进度条（行程图底色 + 已过审题数），练习页题干卡片直接显示对错徽标与卡片色调，选项/解析保留在下方；练习偏好页拆成难度、题型、题数+讲解语言三张卡片，讲解语言不再孤立悬浮。
- 验证：`CheckBrand.py`、`CheckLocalization.py` 通过；PromptiTests 79 项通过（含并发峰值、增量事件、跨批去重、session 增量落库/短文案、取消）；UI 测试覆盖自动进入、后台补足、等待/重试与部分完成。未做真实 Provider 付费调用验证。

## 2026-09-17：多样性、预算与复核

- `GenerationMode` 为本机持久化偏好，练习页和设置页可切换。默认节省 Token：按目标题量调度；宽松模式的首轮候选上限为 `count + min(10, max(2, ceil(count/2)))`，例如 5 题最多先请求 8 个候选。两者都至多追加一次小批补题；总候选数和批次数同时受限。Apple 串行达到目标即停止，不为了用完预算继续生成。
- 自动预生成 `allowsRegeneration: false`，无论偏好模式都严格遵守已预留题数，不额外补量、不超每日预算。用户手动开始的练习不受自动预生成每日限额约束。
- 每个生成任务共享 `CandidateFilter`：历史题、当前批内及并发批次的相同/格式变体题在审核前剔除。落库时再查重，防止并发保存或同步晚到的重复；详情见领域文档。
- 审核只发送上下文、必要题目字段与审核标准，不再嵌入整份生成指令，不发送选项 UUID/生成元数据。安全、语言、场景、自然度、唯一答案、难度六项检查保留，并要求同批近义重复保留最好的一道。
- 部分失败后自动进入练习/前后台切换不启动第二个收费任务；显式“重试”才重新生成。落库错误取消剩余任务并显示实际错误，不再伪装为审核短缺。
- 选中场景作为宽泛类别；目的地常青事实提供地域启发，AI 在原有生成请求内自主扩展具体店铺类型、物品与交流情境，不增加规划请求或输出规划文本。并发批次轮换沟通目标与探索角度；已有题目提示和共享去重继续生效。事实示例不是话题白名单，审核允许分类内合理的虚构交流，但不允许捏造真实地点或时效事实。
- 所有目的地使用同一文化扩展规则，要求当地生活、文化、情境礼仪与说话习惯对交流本身有意义，例如先问候再请求、确认轮候、征求许可、澄清当地用词或礼貌拒绝。每道短题按场景和难度选取合适维度，不硬塞全部文化要素，不转成礼仪常识题。生成与审核读取同一份、按地点与学习语言裁剪的背景。
- 事实与目录版本 `2026-09.3`，提示版本 `5`；Provider 响应 schema、Keychain、计分规则与数据库 schema 不变。实测范围见 `Documentation/Generation-Review-2026-09-17.md`。


## 2026-09-18：DeepSeek 等待与连接设置

- 最初为 OpenRouter DeepSeek V4.1 Flash 关闭默认高强度思考；随后按用户要求统一为全部请求禁用额外 reasoning，最终规则见下节。
- 保留单次 60 秒、整组 180 秒截止和小批并行，安全/质量判定与逐题审核仍执行。未用真实 API Key 验证首题耗时，不能把默认参数问题当作用户这次超时的唯一已证实原因。
- 生成页等待时展示系统加载指示，降低动态效果时显示静态沙漏；首批到达前显示等待文案，已有过审题才显示真实计数。生成完成或失败不显示加载动画。
- 设置/引导移除“更多连接方式”及重复长说明，保留自定义地址、API Key/模型输入、验证操作、费用提示和 OpenRouter 必要链接。
- 证据、回归及视觉验收见 [生成等待修复记录](../Documentation/Generation-Loading-2026-09-18.md)。


## 2026-09-19：强制思考模型保留，统一低强度

模型请求按服务商协议应用统一策略：可关闭思考的模型显式关闭；服务商标记为强制思考的模型继续出现在推荐列表和用户已保存配置中，并把思考强度设为最低的 `low`，不在请求前拦截。

| 协议/端点 | 可关闭思考的模型 | 强制思考的模型 |
| --- | --- | --- |
| OpenRouter | `reasoning: { enabled: false }` | `reasoning: { effort: "low" }` |
| OpenAI Responses / Responses 兼容 | `reasoning: { effort: "none" }` | `reasoning: { effort: "low" }` |
| OpenAI Chat / Gemini / 通用 Chat 兼容 | `reasoning_effort: "none"` | `reasoning_effort: "low"` |
| DeepSeek 官方 Chat | `thinking: { type: "disabled" }` | `thinking: { type: "enabled" }` 与 `reasoning_effort: "low"` |
| Anthropic Messages | `thinking: { type: "disabled" }` | 当前推荐列表没有强制思考型号 |
| Apple Foundation Models | 保留现有 guided generation | 由系统模型控制 |

已知强制思考型号包括 Gemini 3 系列、Gemini 2.5 Pro、GLM 5.3 Flash、DeepSeek R1 和 GPT-5/mini/nano 系列；模型能力规则集中在 `ModelReasoningPolicy`。旧版 GPT-4/GPT-3.5 等不支持 reasoning 的模型不附加无效字段。JSON mode 回退沿用同一策略，不通过重试删除参数来改变思考模式。

推荐刷新工具保留强制思考候选；刷新只校验文本能力和请求数，不因 `reasoning.mandatory` 删除或拒绝候选。完整协议依据和回归证据见 [生成等待修复记录](../Documentation/Generation-Loading-2026-09-18.md#强制思考模型与低强度)。

## 2026-09-20：游客视角、逐题入库与自动补题（取代上述旧批次策略）

- 生成系统规则、选择题/完形/口语说明及语义审核统一固定游客身份。当地人或服务人员可向游客说话，但学习者必须是顾客、住客、乘客或访客。角色反转使 `scene=false`；示例明确区分游客点茶和服务员为客人上茶。移除“变换说话角色/方向”的歧义。新题 promptVersion=6，原题与作答历史不改写。
- 所有 Provider 都按单题生成和审核；远端最多 3 条链并发，Apple 串行。过审立即发事件并保存，不等另外两题；第一题就可以自动开练。生成页和练习页继续共用一个有界任务。
- 每个候选位置至多初次 + 2 次重试，不共享整组的一次补题机会。节省模式最多 `3 * count` 个生成尝试；宽松模式候选位置上限保持 `count + min(10, max(2, ceil(count/2)))`，各位置同样最多 3 次。足量即停止，不为了用完预算继续调用；因并发最多存在 2 个额外进行中候选。
- 首页预生成同样逐题保存。初始请求按已预留题数执行，每个重试或宽松候选必须先额外预留 1 个每日准备额度；额度不足不请求。取消/失败不会清除已过审保存的题目。原 `allowsRegeneration=false` 调用仍严格遵守已预留候选数。
- 生成/审核统一 120s 单次上限，URLRequest 与 URLSession resource 上限同步；原 60s 硬截止不能因收到空行 keep-alive 自动变为无限等待。任务时限为 `min(600, max(180, count * 30))` 秒（按本次缺题数），取消仍立即传播。每次生成输出上限从 12000 降为 4000 token，审核/探测等上限 2000。
- DeepSeek 直连关闭思考仅发送 `thinking: {type: disabled}`，不再发送 Chat 接口不支持的 `reasoning_effort: none`；强制思考模型仍保留并使用 low。OpenRouter 延续 `reasoning.enabled=false` / 必须思考时 low，并设置 `provider.require_parameters=true`、`provider.sort=latency`，要求路由支持所发参数并优先低延迟端点。参数支持不足导致的 OpenRouter 404 可降级为 JSON mode；模型不存在的 404 不降级。
- 实测范围、公开文档与真实 Provider 边界见 [2026-09-20 生成修复记录](../Documentation/Generation-Review-2026-09-20.md)。本地合约测试不能证明真实模型角色遵循率或用户实际线路延迟。

## 2026-09-22：请求效率与可观察的补题

- 每个单题候选位置明确分配一种选中题型，按选择题、完形、口语轮换；prompt 只携带该类型的生成说明，schema 只允许该类型，非适用的 cloze / rubric / sampleAnswer 为 null。游客角色、目的地、难度、去重和安全规则保留；promptVersion 为 7。模型返回非请求类型仍在付费审核前拒绝。
- 结构化模式只在协议的 schema 字段发送结构定义，不再同时将整份 schema 附在 user prompt；JSON mode 和 Anthropic 文本模式仍携带完整 schema。固定规则置于变化的 JSON 场景 / 历史 / 题目数据之前，JSON key 排序稳定。前缀复用是否命中缓存由服务商决定。
- 同一 `RemoteAIClient` / 生成任务按 schema 记忆成功的 JSON 降级，后续同 schema 请求直接使用 JSON mode，避免每题重复一次已知失败的 schema 请求。不同 schema、不同 client/新任务独立；失败的 fallback 不写入记忆。无额外持久化，不改变模型、端点或 reasoning 策略。
- `.activity(attemptID, stage?)` 跟踪正在生成与审核的请求，完成、取消、失败清除。显示已用时与真实请求数，不估计剩余秒数。
- 仍为远端最多 3 条链、Apple 串行，逐题独立审核及保存；每位置至多两次重试、预算与截止保持原上限。取消后自动进入 / 前台恢复不启动新任务；用户显式继续或重试仍只请求缺题。

验证证据与真实服务商边界见 [2026-09-22 生成体验记录](../Documentation/Generation-Experience-2026-09-22.md)。

## 2026-09-22：可选 TypeSafe Jev 题目审核

- 设置新增“题目审核”，默认仍由生成模型审核。用户选择 TypeSafe Jev，输入独立 API Key 并主动完成连接测试后才能保存启用。设置取消不写入新 Key、不删除旧 Key；审核 Key 复用现有 Keychain 管理与独立协议/端点 scope，不作为生成 Provider。
- 适配固定官方 `POST https://api.typesafe.ai/v1/systemone`、锁定 `jev-1.13.0`，发送 `{model,state,questions}`；一次请求包含 14 个独立 Noul 缺陷判断，避免生成长审核文本。请求只含必要练习、场景、语言、难度、事实及最近 30 条题干，不含凭据、选项 UUID、用户标识或完整历史。
- 每个任务开始时固定审核模式；初次生成、练习中补题及自动库存准备共用此配置。先本地校验/去重，再 Jev；明确通过跳过生成模型审核，明确拒绝沿用每题最多三次候选的预算；有效但不确定的判断交给生成模型完整审核。具体阈值与未校准边界见安全文档。
- Jev 的认证、权限/额度、限流、连接、超时、协议错误立即终止本轮任务并取消其他进行中链；不静默换审核服务、不自动追加请求。已收到 approved 事件的题目保留，用户可修改配置或显式重试。每次 Jev 请求限时 30 秒，仍受整个任务截止约束；凭据请求拒绝重定向，响应上限 2 MB。
- 审核与连接测试都进入既有本机用量账本，保留真实 usage 与失败/取消状态；缺失 usage 仍为未知。TypeSafe 可能收费，连接测试只在用户点击后发出。场景过滤和口语评分继续走既有流程。
- 协议、验证记录及官方来源见 [TypeSafe 审核接入](../Documentation/TypeSafe-Review-2026-09-22.md)。离线测试不证明真实账号、延迟、安全召回或语言质量。
