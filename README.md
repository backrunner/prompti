# Prompti

Prompti 是一款开源、原生 SwiftUI 旅游语言学习应用。用户选择城市、语言、场景、难度和题量后，Prompti 使用 Apple 设备端 Foundation Models 或用户自己的模型 API Key 生成完形填空、QA 选择题和口语练习。

## MVP 功能

- 覆盖常用城市目录，并允许添加任意城市和国家；中国自定义目的地默认中文，其他自定义目的地默认英文。
- 中文、英语、日语、韩语、俄语、德语和西班牙语训练。
- 通用场景、城市特色场景和经过 LLM 审核的自定义场景。
- 生存、基本、自然和流畅四档难度；3-20 题或随机一题。
- Apple Foundation Models、OpenAI Responses、OpenAI Chat / Compatible、Anthropic Messages。
- 结构化生成、输入过滤、输出二次审查、题目确定性校验和失败恢复。
- 完形填空、QA、录音转写、系统语音播放、跳过和题目报告。
- SwiftData 本地题库、错题复习、统计和 CloudKit private database 同步。
- API Key 仅保存于本机 Keychain，不进入 iCloud 或日志。
- 用户明确启用后，在 App 前台进入首页时补足少量题目库存。

产品和工程设计文档见 [.agents/README.md](.agents/README.md)。

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

CloudKit 同步需要在开发者账号中注册 `iCloud.com.prompti.app`，或将 bundle/container identifier 改为自己的标识。CloudKit 配置不可用时，应用会退化到本地 SwiftData store。

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
- Provider 请求只包含目的地、语言、所选场景和生成约束，不包含设备标识或完整历史。
- 原始录音不持久化；Speech framework 仅在一次口语练习期间处理音频。

请自行确认所选 Provider 的数据保留、价格、地区和模型政策。

## 当前 MVP 边界

- 口语题提供录音、转写和参考答案；低置信语音不计分，也不宣称提供专业发音评分。
- “提前准备”只在 App 活跃且首页出现时执行，不承诺 iOS 系统后台调度。
- 预设目的地目录是随 App 发布的静态、常青内容；自定义目的地仅生成通用旅游场景，不提供实时票价、营业时间、签证、法律或安全信息。
- 当前 UI 文案以英语为主，训练内容支持七种目标语言。
- 本环境没有使用真实用户 API Key 调用收费 Provider；远程协议实现基于官方协议并覆盖响应 fixture contract tests，但发布前仍需进行受控的真实账户兼容测试。

## 贡献与安全

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要把密钥或未脱敏的模型响应放入公开 issue。

## License

Apache License 2.0，见 [LICENSE](LICENSE)。

### Model sign-in and interface refresh

OpenRouter sign-in now supports PKCE authorization and multiple model choices through one account. A code-based sign-in fallback is available under **More connection options**. OpenAI Responses, compatible Chat APIs, Anthropic API keys and eligible Apple on-device models remain available. Provider usage can require account credits; a provider subscription is not automatically an API credit balance.

Credentials are isolated by provider endpoint in the device Keychain. New connections are verified before saving. Disconnecting removes the local credential; revoke remote access from the provider account.

The welcome route animation, content surfaces and floating actions now share a quieter Liquid Glass treatment, with Reduce Motion/Reduce Transparency fallbacks. Today starts a default practice set directly; advanced preferences stay in the Practice tab. See `.agents/02-user-experience.md` and `.agents/05-ai-byok-and-generation.md` for the current interaction and authorization contracts.
