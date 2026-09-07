# 领域模型与数据设计

## 1. 核心概念

### 1.1 DestinationCatalogEntry

版本化、只读的目的地目录项，随 App bundle 发布，后续可由签名目录更新。

- `id`: 稳定 slug/UUID，不以显示名称作为主键。
- `kind`: country / region / city。
- `localizedNames`: 本地化显示名。
- `countryCode`, `administrativeArea`, `city`。
- `timeZoneIdentifier`。
- `supportedLocales`: 可训练 BCP-47 locale 列表。
- `defaultLocale`。
- `commonSceneIDs`, `localSceneIDs`。
- `facts`: 经编辑审核的常青事实、地域表达、饮食与景点背景。
- `catalogVersion`, `contentVersion`。

目录只提供生成依据，不保存实时价格、营业时间、签证政策或安全警报。生成提示明确禁止模型补齐这些时效事实。

### 1.2 SceneDefinition

- `id`, `scope`（global / destination / user）。
- `localizedTitle`, `shortIntent`。
- `destinationIDs`, `supportedLocales`。
- `factReferences`。
- `safetyCategory`, `reviewVersion`。
- 用户场景附加 `normalizedInput`, `moderationDecision`, `createdAt`。

用户场景建议限制为 40 个 Unicode grapheme clusters，硬上限 80；单行、无 URL、无代码块、无控制字符。

### 1.3 TrainingConfiguration

一次生成请求的不可变配置快照：

- `destinationID`, `targetLocale`, `explanationLocale`。
- `sceneIDs`。
- `difficulty`。
- `questionTypes`。
- `requestedCount`。
- `romanizationPreference`, `speechPreference`。
- `providerProfileID`, `providerProtocol`, `modelID`。
- `promptVersion`, `schemaVersion`, `policyVersion`, `catalogVersion`。

## 2. 题目模型

### 2.1 Question

- `id`: UUID，由客户端生成；CloudKit 不使用 uniqueness constraint。
- `contentHash`: 归一化题干、答案、locale、场景生成的哈希，用于应用层去重。
- `type`: cloze / multipleChoiceQA / spokenQA。
- `destinationID`, `targetLocale`, `sceneID`, `difficulty`。
- `promptText`, `translation`, `explanation`。
- `choices`: 可选子对象关系。
- `correctChoiceIDs` 或 `acceptedAnswerRubric`。
- `clozeSegments`: 文本段与空位的结构化表示，不在 UI 层解析下划线。
- `pronunciationHints`, `romanization`。
- `sourceFacts`: 使用的目录事实 ID，便于追溯。
- `qualityScore`, `reviewState`。
- `generationMetadata`。
- `createdAt`, `lastReviewedAt`, `quarantinedAt`。

### 2.2 Choice

- `id`, `text`, `isCorrect`。
- `feedback`: 选择该项时的短解释。
- 选项顺序属于会话快照，不能使用数组 index 作为 SwiftUI identity。

### 2.3 GenerationMetadata

- Provider 协议、模型 ID、模型可见版本（若 Provider 提供）。
- prompt/schema/policy/catalog 版本。
- 请求时间、完成时间、重试次数。
- 输入/输出 token；未知则为空。
- 质量检查代码、安全检查结果代码。
- 不保存 API Key、完整认证头、原始系统 prompt 或 Provider 的隐藏推理。

## 3. 作答与复习

### 3.1 PracticeSession

- `id`, `configurationSnapshot`。
- `questionIDs`，以及会话内固定顺序。
- `startedAt`, `endedAt`, `status`。
- `requestedCount`, `preparedCount`。

### 3.2 QuestionAttempt

采用 append-only 事件，便于 CloudKit 合并。

- `id`, `questionID`, `sessionID`。
- `startedAt`, `answeredAt`。
- `result`: correct / incorrect / partial / skipped / undetermined / reported。
- `selectedChoiceIDs`, `submittedText`, `transcript`（均可选）。
- `speechRecognitionConfidence`, `evaluationSummary`。
- `skipReason`, `reportReason`。
- `destinationID`, `targetLocale`, `sceneID`, `difficulty` 的冗余快照，保证统计不依赖已删除关系。
- `localDayKey`, `timeZoneIdentifier`。

原始录音默认不持久化、不上传 iCloud；评估完成后删除临时文件。若未来允许保存，必须单独征得同意并评估存储成本。

### 3.3 MasteryState

这是可重建的缓存，不是事实来源：

- `questionID`, `lastResult`, `lastAttemptAt`。
- `correctStreak`, `nextReviewAt`, `status`。

发生冲突或迁移时，可由 `QuestionAttempt` 重建。

## 4. 统计口径

- **已作答题数**：correct + incorrect + partial；不含 skipped、undetermined、reported。
- **正确率**：correct / (correct + incorrect + partial)。partial 可按产品决策计 0.5，但 UI 必须说明；MVP 建议不折算，只单列。
- **错题集**：最近一次可判定结果为 incorrect/partial，且题目未被报告或删除。
- **每日打卡**：某个 `localDayKey` 至少有一条可判定作答事件。
- **连续打卡**：按作答时记录的当地日键计算，跨时区旅行不回写历史日期。
- **生成数量**不是学习数量，不进入打卡。

统计页面即时从事件或可重建聚合缓存获取，不能同步“总正确数 += 1”一类竞争写入。

## 5. SwiftData + CloudKit 映射规则

CloudKit store 中建议包含：`QuestionRecord`、`ChoiceRecord`、`PracticeSessionRecord`、`AttemptRecord`、`UserSceneRecord`、`GenerationJobRecord`、`MasteryRecord`。

必须遵守：

- 所有属性有默认值或为 optional。
- 所有 relationship 为 optional，并显式声明 inverse 和 delete rule。
- 不使用 `@Attribute(.unique)` 或 `#Unique`；依靠稳定 UUID 和应用层去重。
- 首次保存后才依赖 persistent identifier。
- 关键写入显式 `modelContext.save()`。
- `@Query` 只用于 SwiftUI View；Repository 使用 `FetchDescriptor`。
- `ModelContext` 和 `@Model` 实例不跨 actor；跨边界传 UUID、persistent ID 或 Sendable DTO，并在目标上下文重新 fetch。
- 从 v1 起定义 `VersionedSchema` 和 `SchemaMigrationPlan`。
- iOS 18+ 可对 `createdAt`、`questionID`、`destinationID`、`localDayKey` 等高频查询字段建索引；写多读少字段不滥用索引。

## 6. 去重与删除

- 同一 `contentHash + targetLocale + destinationID` 在本地合并；CloudKit 同步后再次执行去重整理。
- 删除目的地配置不删除历史题目或 attempt，只移除用户偏好。
- 删除题目时关联 choice 使用 cascade；attempt 保留快照字段，question 关系可 nullify。
- 报告问题优先隔离而非立即物理删除，以保持历史统计可解释。
- 用户请求“删除全部学习数据”时清除 CloudKit 数据、SwiftData 本地 store、缓存和临时音频；Keychain 独立确认是否一并清除。


## 2026-09-06：代码复核修正

- 错题队列按最近一次可判定结果构建；答对后离开队列，原错误事件继续保留在 History。进入复习时固定题目快照，查询更新不会改变进行中的会话。
- 报告事件使该题的作答退出准确率和打卡统计，但不删除事件；同一次会话提交后不再允许追加 skip。
- 新 attempt 用作答时的当地 Gregorian 日期写入 `localDayKey`；首页、每日完成和 streak 读取日键，不按旅行后的当前时区重新解释旧时间戳。旧版本错误写入的 UTC 日键缺乏原时区，无法可靠回填，保留原值。
- 生成 schema 返回所用的 `sceneID`，必须属于请求的场景集合，保存时据此归属场景；不再按题目位置轮流分配标签。现有数据库字段不变，无 schema 迁移。
- 生成批次内去重已实现；跨批次/同步去重、完整生成元数据及其他待办见 `11-code-review-2026-09-06.md`。

## 2026-09-07：能力补齐

已冻结 V1 并加入 V2 轻量迁移；结构化完形、口语 rubric、生成来源快照、讲解语言、session/答题快照及去重已实现。 最新实现范围、测试结果和真实环境边界见 [能力补齐记录](12-capabilities-2026-09-07.md)。
