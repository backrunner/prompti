# 持久化、iCloud 与密钥管理

## 1. 数据分区

| 数据 | 存储 | 同步 |
| --- | --- | --- |
| 题目、choice、会话、作答、错题状态 | SwiftData CloudKit store | iCloud private database |
| 用户自定义场景与审核结果 | SwiftData CloudKit store | iCloud private database |
| 统计事件和可重建聚合 | SwiftData CloudKit store | iCloud private database |
| 目的地目录 | App bundle + 签名更新缓存 | 不作为用户数据同步 |
| API Key、敏感 headers | Keychain | 不同步，建议 `ThisDeviceOnly` |
| Provider 类型、模型和非敏感偏好 | UserDefaults/本地配置 | 默认不跨设备；可后续同步非敏感部分 |
| 原始录音 | 临时文件 | 不同步，评估后删除 |
| 诊断日志 | Unified Logging，脱敏 | 不由 App 主动同步 |

Keychain 选择 `ThisDeviceOnly` 意味着换机后必须重新输入 API Key；这是安全取舍，必须在设置页说明。

## 2. CloudKit 行为

- 使用用户 private database，App 不拥有或读取其他用户的数据。
- iCloud 默认启用；用户未登录、关闭 iCloud Drive、配额不足或网络异常时退化为本地 store。
- 启动不等待同步完成；展示本地内容，并在后台收敛。
- UI 提供“已同步 / 等待同步 / iCloud 不可用”的状态，不承诺精确上传进度。
- MVP 不提供 App 内“关闭同步”开关。真正的双 store 切换涉及迁移、重复和删除语义；若必须提供，作为独立 P1 项实现。

## 3. 冲突策略

CloudKit 是最终一致，不假设另一设备的数据已经出现。

- `QuestionAttempt`、session 和 generation event 采用 append-only UUID，天然合并。
- 统计从 attempt 派生，避免 last-write-wins 丢增量。
- 用户设置按字段保存 `updatedAt`；冲突使用最新时间并保留可解释默认值。
- 题目用 `contentHash` 应用层去重；不得依赖 CloudKit 不支持的 SwiftData unique constraint。
- quarantine/report 是单调状态：任意设备报告后都保持隔离，除非用户显式恢复。
- 删除使用 tombstone/删除事件传播；同步窗口内 UI 能容忍引用暂时为空。

## 4. Repository 设计

- SwiftUI View 可以用简单 `@Query` 展示；复杂筛选、分页、聚合在 repository。
- repository 使用 `@ModelActor` 独占 `ModelContext`。
- actor 外只返回 Sendable DTO、UUID、计数和分页 token，不返回 `@Model` 实例。
- 正确性关键操作后显式 `save()`；失败时 UI 不显示已保存。
- 批量导入目录或题库分批保存并检查取消，避免长期占用内存。

## 5. Schema 与迁移

从第一个可发布版本建立：

- `PromptiSchemaV1: VersionedSchema`。
- `PromptiMigrationPlan`。
- 字段新增优先 optional/default，关系变化明确 delete rule。
- 发布前用旧版本真实 store fixture 测试升级，不只测试空库。
- prompt/schema/policy/catalog 版本是业务版本，不等同于 SwiftData schema 版本。

## 6. iCloud 异常

| 情况 | 行为 |
| --- | --- |
| 未登录 iCloud | 本地可用；设置页提示登录后同步 |
| 配额不足 | 本地继续；明确提示无法上传，不丢本地数据 |
| 冲突/部分关系缺失 | 展示可用快照；后台重算聚合和去重 |
| 账户切换 | 暂停写入、重新建立 store；不得把前账户数据上传到新账户 |
| CloudKit schema 错误 | 发布阻断；生产环境不能依赖运行时自动建 schema |
| 用户删除 iCloud 数据 | 本地观察删除并收敛，不从缓存“复活” |

## 7. 数据生命周期与导出

- 设置提供删除历史题目、删除录音临时文件、删除全部学习数据、删除 Provider 密钥。
- 导出建议为 JSON，包含 schema 版本、题目快照和 attempt；默认不含 Provider 配置和内部 prompt。
- 删除全部数据需要二次确认，CloudKit 删除可能延迟；UI 展示进行中状态。
- 崩溃报告、诊断导出和 issue 模板必须自动移除 Key、Authorization header、用户自定义 endpoint query 和用户场景原文。

