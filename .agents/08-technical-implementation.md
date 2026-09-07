# 技术实现方案

品牌与 UI 的现行实现约束见 [`13-brand-and-ui-guidelines.md`](13-brand-and-ui-guidelines.md)。DesignSystem 统一提供语义颜色、文本角色、按钮/内容面/答案状态与 P 品牌组件；`Tools/GenerateAppIcon.swift` 同时生成原生图标和 App 内的矢量模板 PDF。`python3 Tools/CheckBrand.py` 是 UI 贡献的静态检查入口。

## 1. 平台基线

- Swift 6.2+，Complete Strict Concurrency。
- Xcode 26+。
- 建议 deployment target iOS 18，使用 `#available(iOS 26, *)` 隔离 FoundationModels 和 Liquid Glass API。
- SwiftUI + Observation；SwiftData + CloudKit；URLSession + Codable。
- Apple 框架：FoundationModels、Speech、AVFoundation、BackgroundTasks、Security、OSLog、CryptoKit。

iOS 18 最低版本和 iOS 26 Apple 模型能力并不冲突：旧系统保留 BYOK 路径，新系统在运行时开放设备端能力。

## 2. 依赖装配

```swift
@MainActor
@Observable
final class AppDependencies {
    let catalog: DestinationCatalog
    let providerRegistry: ProviderRegistry
    let generation: GenerationCoordinator
    let questions: QuestionRepository
    let attempts: AttemptRepository
    let speech: SpeechService
    let secureStore: SecureStore
}
```

这是示意而非要求所有服务都可观察。纯服务保持不可观察，通过 typed environment 注入；feature-local 依赖优先 initializer injection。

## 3. 生成状态机

```swift
enum GenerationState: Equatable, Sendable {
    case idle
    case preparing
    case connecting
    case generating(completed: Int, requested: Int)
    case reviewing(accepted: Int, candidateCount: Int)
    case saving(accepted: Int)
    case partial(ready: Int, requested: Int)
    case ready(count: Int)
    case failed(GenerationFailure)
    case cancelled
}
```

数字只表示已确认的题目数量，不伪装为时间百分比。状态变更通过 `AsyncStream` 或 AsyncSequence 暴露；消费者退出时取消父任务。

## 4. Provider HTTP 实现

- 每个 Adapter 自己定义 Request/Response Codable DTO，不复用一个包含大量 optional 的万能 DTO。
- `URLSessionConfiguration.ephemeral` 用于 BYOK 请求；禁用不必要 cache/cookie。
- 默认超时：连接 15 秒、请求 60 秒；大批次拆小，不单纯提高超时。
- 响应设置合理字节上限和 JSON 嵌套限制；拒绝非预期 MIME 时仍保留安全错误摘要。
- 认证通过 `URLRequest` 最后一步注入；日志层之前对 headers/body 脱敏。
- 429 读取 `Retry-After`，只对幂等生成请求在预算内退避；401/403 不自动重试。
- OpenAI Responses 设置 `store: false`，读取 typed output/refusal/usage，而不是假设首段一定是文本。
- Chat、Anthropic 和兼容端点分别解析 finish reason、refusal 和 usage。

## 5. Foundation Models 实现

```swift
@available(iOS 26.0, *)
func appleModelStatus(for locale: Locale) -> AppleModelStatus {
    let model = SystemLanguageModel.default
    guard model.supportsLocale(locale) else { return .unsupportedLocale }
    switch model.availability {
    case .available: return .available
    case .unavailable(.deviceNotEligible): return .hidden
    case .unavailable(.modelNotReady): return .notReady
    case .unavailable: return .unavailable
    }
}
```

具体 case 名称以实现时 Xcode 26 SDK 为准并由编译器验证。题目 DTO 使用 guided generation；每个 session 控制上下文大小，批次间不保留不必要 transcript。系统更新后通过 prompt eval 回归，不依赖固定输出措辞。

## 6. 口语实现

### 6.1 播放

- MVP 使用 `AVSpeechSynthesizer` 读取题干和参考答案。
- 根据 BCP-47 locale 选择系统 voice；voice 不存在时明确显示不可播放。
- 用户可调较慢/正常语速，不把速度绑定难度为不可更改值。

### 6.2 录音和转写

- `AVAudioSession` 配置录音/播放切换，处理耳机、电话中断和路由变化。
- iOS 26 优先现代 Speech API（实现时核对 locale 支持）；iOS 18 fallback 到可用的 Speech recognition API。
- 权限：麦克风与语音识别分别处理；拒绝后仍可做文本题。
- 音频写临时目录，完成/取消/失败后删除。

### 6.3 评分

1. 转写置信度过低 -> undetermined。
2. 规范化标点、大小写和允许的书写变体。
3. 确定性检查关键意图/slot。
4. 对开放答案调用受限的语义 rubric 评估，输出固定分类和一句改进建议。
5. 不输出 87/100 一类未经校准的“发音分”。

## 7. 后台与预生成

- App 活跃时维护库存最可靠：进入首页、完成一题或网络恢复时检查低水位。
- `BGAppRefreshTask` 用于轻量检查，`BGProcessingTask` 仅作为机会性补充；必须设置 expiration handler 取消生成。
- 默认关闭。启用后配置：库存目标、每日题数/token 上限、仅 Wi-Fi、低数据模式、低电量/低电源模式暂停。
- 任务开始前重新检查 Provider key、目的地配置、预算和库存；完成每题后立即保存，允许部分结果。
- iOS 终止任务时不把它标为失败；job 保持可恢复/过期状态，下次前台继续。

## 8. 日志和可观测性

- 使用 `Logger` 分类：app、generation、provider、safety、persistence、speech、background。
- 使用 signpost 测量首题时间、生成、审查和保存阶段。
- 日志仅写 request ID、provider kind、model 的非敏感别名、状态码、错误枚举、token 数和耗时。
- 禁止记录 Authorization、API Key、完整 request/response、用户录音、未通过审核的场景和题目原文。
- 用户主动导出诊断时生成一次性脱敏包，并在 UI 中列出包含内容。

## 9. 目的地目录

- bundle 中按 schema 验证的 JSON；构建时校验 ID 引用、locale、重复、事实时效性标记。
- 地方事实须有来源 URL、审核日期和编辑备注，但来源元数据不必全部进入模型上下文。
- 后续远端更新必须签名验证、原子替换和保留上一个可用版本。
- 社区贡献通过 PR、schema lint、事实来源与人工语言审查进入，不允许 App 内直接发布未审用户内容。

## 10. 安全配置

- ATS 默认严格；自定义 endpoint 仅 HTTPS，不提供“允许任意 HTTP”开关。
- URL 解析后检查最终解析地址和重定向目标，阻止 SSRF 到本机/局域网。
- Keychain 使用按 Provider profile 分离的 secret ID；删除 profile 同步删除 secret。
- Privacy Manifest 声明使用的 required-reason API；Info.plist 提供麦克风、语音识别、iCloud 用途说明。
- CI secret scanning；示例配置使用明显无效 key。


## 2026-09-06：前台库存和音频修正

- 库存默认关闭；仅在 App active、Today 可见时启动，每次最多申请 3 题。目标库存默认 3、可设 3–20；每日预生成上限默认 12、可设 3–50；默认仅 Wi-Fi，低数据模式、低电量和低电源模式下不启动新请求。
- 预生成预算以 UTC 日键持久化，在发出请求前预扣申请题量；失败/取消不返还，避免反复进入页面或重启突破上限。用户手动开始练习不受此预生成上限限制。
- 停止录音先释放麦克风，再等待最终转写；最多等待 3 秒，未完成时不评分。离开题目、退出会话、应用变为非活跃、音频中断或耳机断开时清理音频资源；旧回调不能覆盖新一题。
- BGTask、token usage 仪表和清空库存操作尚未实现，不将以上前台维护描述为系统后台调度。

## 2026-09-07：能力补齐

已加入账户独立文件、同文件 CloudKit 回退恢复、旧库显式幂等导入、同步事件状态及真实 V1 磁盘迁移测试。真实 CloudKit mirroring 账户切换生命周期仍须双设备验收。 最新实现范围、测试结果和真实环境边界见 [能力补齐记录](12-capabilities-2026-09-07.md)。
