# Prompti

**出发前，练好旅行常用语。**

Prompti 是一款开源的 iOS 旅行语言练习 App。选好目的地，从点餐、问路、酒店入住等场景开始，通过填空、选择和口语练习，熟悉旅行中常用的说法。每组练几道，也可以随机练一题；练过的题目随时可以复习。

App 使用原生 SwiftUI 开发，由 Apple 设备端 Foundation Models 或用户连接的模型服务生成题目，支持按语言、场景、难度和题量调整练习。

## MVP 功能

- 覆盖常用城市目录，并允许添加任意城市和国家；中国自定义目的地默认中文，其他自定义目的地默认英文。
- 中文、英语、日语、韩语、俄语、德语和西班牙语训练。
- 通用场景、城市特色场景和经过 LLM 审核的自定义场景。
- 入门沟通、基本交流、自然交流和流畅表达四档难度；每组 3–20 题，也可以随机练一题。
- Apple Foundation Models、OpenAI Responses、OpenAI Chat / Compatible、Anthropic Messages。
- 结构化生成、逐题安全与质量审核、确定性校验、来源快照和有界失败恢复。
- 填空题（1–3 个空）、选择题和口语练习；支持编辑语音识别结果、查看口语反馈、调整朗读速度、跳过题目和反馈题目问题。
- SwiftData 本地题库、错题复习、统计、账户独立存储与 CloudKit private database 同步。
- 可先练已通过审核的题目，其余题目在练习时继续生成；显示实际请求和 token 用量，可清空待练题目。
- API Key 仅保存于本机 Keychain，不进入 iCloud 或日志。
- 提前准备题目默认关闭；开启后，App 会在前台进入首页时按需补充待练题目，可能产生额外模型费用。

产品和工程设计文档见 [.agents/README.md](.agents/README.md)。

品牌 Logo、iOS 图标外观与商店展示示意见 [品牌预览](Documentation/Brand/Preview.html)；矢量资源和生成方式见 [品牌说明](Documentation/Brand/README.md)。

中文 slogan、商店介绍和端内用词见 [文案规范与市场文案](Documentation/Brand/Copywriting.md)。

全 App 的品牌实施与实际模拟器截图见 [UI 验收记录](Documentation/Brand/UI-Review.md)；开发约束见 [品牌与 UI 规范](.agents/13-brand-and-ui-guidelines.md)。

引导与设置内置当前快速模型，并提供 OpenAI、Gemini、DeepSeek、Anthropic 和 OpenRouter 连接预设。OpenRouter 候选按有来源的近 7 天请求次数快照排序，显示数据日期；未知调用量单独列出，已有模型与手填 ID 保留。维护时运行 `python3 Tools/UpdateModelRecommendations.py`，发布前复核型号与数据日期。详细口径见 [模型规范](.agents/05-ai-byok-and-generation.md)。

界面支持英文和简体中文，包含目的地 / 地标 / 场景、动态提示和系统权限文案；支持用中文或英文搜索内置目的地。运行 `python3 Tools/CheckLocalization.py` 检查翻译和占位符，实际界面与验证范围见 [模型与本地化验收](Documentation/Model-and-Localization-Review.md)。

## 环境

- Xcode 26.6 或更高版本
- Swift 6，Complete Strict Concurrency
- iOS 18+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Apple Foundation Models 只在 iOS 26+、支持 Apple Intelligence、模型已就绪且支持目标 locale 时出现。其他情况必须配置 BYOK。

## 构建

```bash
xcodegen generate
xcodebuild -project Prompti.xcodeproj \
  -scheme Prompti \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```

在 Xcode 中打开 `Prompti.xcodeproj` 也可以直接运行。

App 标识为 `com.alkinum.prompti`，CloudKit 容器为 `iCloud.com.alkinum.prompti`。真机开发需要在 Xcode 登录开发者账号；`project.yml` 保存签名团队和自动签名配置，自动签名会准备对应的开发描述文件。Fork 需改为自己的团队和 `PRODUCT_BUNDLE_IDENTIFIER`，关联自己的 CloudKit 容器，并同步调整 entitlement 与运行时的 `PROMPTI_CLOUD_CONTAINER_IDENTIFIER` 设置。

同一账户的 CloudKit 配置与本地回退使用相同的 SwiftData 文件；验证账户后启用同步。旧版本与未登录的数据可在设置中明确确认后导入，不会自动归入当前 iCloud 账户。

## 测试

```bash
xcodebuild test -project Prompti.xcodeproj \
  -scheme Prompti \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Debug 构建可添加 `-prompti-demo` 启动参数绕过真实模型并使用安全的示例题；同时添加 `-prompti-practice` 可直接打开练习配置页。这两个参数不会进入 Release 行为。

## BYOK 与隐私

- OpenAI 官方配置默认使用 Responses API，并设置 `store: false`。
- Chat Completions 官方配置同样设置 `store: false`。
- 自定义 endpoint 只允许 HTTPS，并拒绝常见的回环和私网地址。
- 生成请求包含目的地、语言、场景、生成约束与最多 30 条已有题干以避免重复；不发送设备标识或答题历史。
- 口语语义评估仅发送当前题干、参考答案/rubric、转写文字和语言设置。生成来源和答题快照随学习数据保存；请求用量仅在本机保存。
- 原始录音不持久化；Speech framework 仅在一次口语练习期间处理音频。

请自行确认所选 Provider 的数据保留、价格、地区和模型政策。

## 当前 MVP 边界

本轮实现、验证与剩余发布检查见 [2026-09-07 能力补齐](.agents/12-capabilities-2026-09-07.md)；原始差距清单保留在 [代码复核](.agents/11-code-review-2026-09-06.md)。

- 口语题提供录音、转写和参考答案；低置信语音不计分，也不宣称提供专业发音评分。
- “提前准备”只在 App 活跃且首页出现时执行，不承诺 iOS 系统后台调度。
- “提前准备”默认仅 Wi-Fi、每日最多申请 12 题（设置可调整）；失败/取消仍占用该预算，低电量或低电源模式下不启动新请求。
- 口语通过所选模型按意图和必要细节评估同义表达；低置信、模糊或评估服务不可用时不计分。模型语义质量仍需七语言内容验收。
- 已实现同账户回退恢复、账户分库、显式导入和 CloudKit 同步事件状态；真实账户切换、系统 mirroring 生命周期和双设备收敛仍需真机验收。
- 预设目的地目录是随 App 发布的静态、常青内容；自定义目的地仅生成通用旅游场景，不提供实时票价、营业时间、签证、法律或安全信息。
- 新增主要流程提供中英文文案，训练内容支持七种目标语言；本轮按系统默认字号和常规布局验收。
- 本环境没有使用真实用户 API Key 调用收费 Provider；远程协议实现基于官方协议并覆盖响应 fixture contract tests，但发布前仍需进行受控的真实账户兼容测试。

## 贡献与安全

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要把密钥或未脱敏的模型响应放入公开 issue。

## License

Apache License 2.0，见 [LICENSE](LICENSE)。

### Model sign-in and interface refresh

OpenRouter sign-in now supports PKCE authorization and multiple model choices through one account. A code-based sign-in fallback is available under **More connection options**. OpenAI Responses, compatible Chat APIs, Anthropic API keys and eligible Apple on-device models remain available. Provider usage can require account credits; a provider subscription is not automatically an API credit balance.

Credentials are isolated by provider endpoint in the device Keychain. New connections are verified before saving. Disconnecting removes the local credential; revoke remote access from the provider account.

The interface now uses the same P conversation mark as the app icon, emerald actions and warm neutral reading surfaces. Welcome, generation and completion visuals share the conversation theme. Native Liquid Glass stays in navigation and compact floating controls, with opaque fallbacks. Today starts a default practice set directly; advanced preferences stay in the Practice tab. See [.agents/13-brand-and-ui-guidelines.md](.agents/13-brand-and-ui-guidelines.md) for the brand contract and [.agents/05-ai-byok-and-generation.md](.agents/05-ai-byok-and-generation.md) for authorization behavior.
