# 模块设计与项目架构

## 1. 架构目标

- SwiftUI 视图只负责状态呈现和用户意图，不直接组装 prompt、调用网络或写复杂查询。
- 业务规则位于可测试的 Domain/Service 层。
- Provider、持久化和语音能力通过窄协议替换。
- 使用 feature-first 目录，但 MVP 保持单 App target，避免过早拆成大量 Swift Package。
- 不强制套用 MVVM/TCA 名称；复杂页面可以有 `@MainActor @Observable` feature model，简单页面使用本地值状态。

## 2. 逻辑分层

```text
SwiftUI Features
    -> Application Use Cases
        -> Domain Models / Policies
            -> Provider Protocols
                -> Apple Models / HTTP AI / SwiftData / Speech / CloudKit
```

依赖只向内。Domain 不 import SwiftUI、SwiftData、CloudKit、FoundationModels 或具体 Provider SDK。

## 3. 模块边界

| 模块 | 职责 | 不负责 |
| --- | --- | --- |
| AppShell | Tab、NavigationStack、依赖装配、全局路由 | 业务判断、网络 |
| Onboarding | 目的地/语言/Provider 首次配置 | API 协议实现 |
| PracticeSetup | 训练配置、场景审核入口 | 生成与保存细节 |
| Practice | 会话、作答、跳过、报告、反馈 | 统计聚合 |
| Review | 错题、历史、隔离题目 | 修改历史快照 |
| Progress | 统计查询和图表 | 维护竞争式计数器 |
| Settings | Provider、iCloud、预生成、语音偏好 | 保存明文密钥 |
| DestinationCatalog | 版本化目的地/场景/事实读取 | 实时旅行事实 |
| AIProvider | 统一生成协议与能力描述 | 决定产品安全政策 |
| Generation | prompt、批次、修复、去重、状态机 | 直接渲染 UI |
| Safety | 输入/输出策略、分类、决策记录 | 自动放宽政策 |
| Quality | schema、语言、答案、目的地相关性校验 | 内容政策裁决 |
| Speech | TTS、录音、STT、语义评估输入 | 声称专业发音测评 |
| Persistence | SwiftData repository、迁移、聚合 | Keychain 密钥 |
| SecureStore | Keychain secret 生命周期 | iCloud 同步 |
| Background | 库存策略、BGTask 调度、预算 | 承诺准时执行 |

## 4. 建议工程结构

```text
Prompti/
  App/
    PromptiApp.swift
    AppShellView.swift
    AppDependencies.swift
    AppRoute.swift
  Features/
    Onboarding/
    Home/
    PracticeSetup/
    Practice/
    Review/
    Progress/
    Settings/
  Domain/
    Destinations/
    Training/
    Questions/
    Attempts/
    Statistics/
    Safety/
  Services/
    AI/
      Core/
      AppleFoundationModels/
      OpenAIResponses/
      OpenAIChat/
      AnthropicMessages/
      OpenAICompatible/
    Generation/
    Safety/
    Quality/
    Speech/
    Persistence/
    SecureStore/
    Background/
  DesignSystem/
    Colors/
    Components/
    Motion/
  Resources/
    Localizable.xcstrings
    DestinationCatalog/
    PromptTemplates/
  SupportingFiles/
PromptiTests/
PromptiUITests/
PromptiPromptEvals/
```

## 5. 状态所有权

- App 根部创建长生命周期服务，通过 typed `@Environment` 注入。
- 单个 View 的选择、展开和焦点用 `private @State`。
- 子 View 只有需要修改父值时才用 `@Binding`。
- 跨多个 UI 状态的流程使用 `@MainActor @Observable` feature model，并由根 View 以 `@State` 持有。
- 注入的 observable 需要 binding 时使用 `@Bindable`。
- 路由使用 enum + `NavigationStack` path；sheet 使用 item 驱动，不堆叠多个 boolean。
- `body` 中不执行业务逻辑；异步加载放 `.task(id:)`，离开页面自动取消。

## 6. 并发设计

### 6.1 隔离边界

- UI/feature model：`@MainActor`。
- `GenerationCoordinator`：actor，拥有 in-flight job 和去重表。
- `ProviderClient`：Sendable value/client 或 actor；URLSession async API。
- `QuestionStore`：`@ModelActor` 或等价 repository，独占 `ModelContext`。
- 音频会话控制：actor 或明确的单 executor，回调桥接后返回 Sendable DTO。

### 6.2 规则

- 固定数量的独立检查用 `async let`；动态批次用 task group，并限制并发。
- 生成问题默认串行或低并发，避免突然放大 BYOK 成本和限流。
- 每次 `await` 后重新验证 actor 内状态，不能假设 job 仍为原状态。
- 长循环和修复重试调用 `Task.checkCancellation()`。
- `CancellationError` 是正常生命周期事件，不弹失败警报、不自动重试。
- 禁止用 `Task.detached` 绕过 isolation；禁止用 `@unchecked Sendable` 消除编译器错误。

## 7. 关键用例

### GeneratePracticeSet

输入 `TrainingConfiguration`，协调目录读取、场景审查、Provider 能力、生成、安全/质量验证、去重和持久化，输出 `AsyncStream<GenerationEvent>` 或等价状态序列。

### SubmitAnswer

以 question DTO 和答案创建不可变 `QuestionAttempt`，返回反馈；之后异步更新可重建 mastery cache。写入 attempt 成功是 UI 显示“已记录”的前提。

### ReviewWrongAnswers

查询最近一次可判定结果为错误/部分正确的题目，排除 quarantined/reported；在 repository 内完成筛选和分页。

### MaintainQuestionInventory

根据目的地、语言、场景和难度维度计算可用库存，尊重每日预算、网络、电量、温度、低数据模式和用户开关，创建有限 generation jobs。

## 8. 依赖策略

MVP 优先 Apple 原生框架：SwiftUI、Observation、SwiftData、CloudKit、FoundationModels、Speech、AVFoundation、BackgroundTasks、OSLog、CryptoKit、Security。

- Provider REST 直接用 URLSession + Codable，避免为少量端点引入大型 SDK。
- 引入第三方依赖需要记录：必要性、许可证、二进制体积、隐私清单、维护状态和替换方案。
- 所有 Provider contract 由本地 fixture 测试，不能依赖第三方 SDK 的未封装类型穿透到 Domain。

