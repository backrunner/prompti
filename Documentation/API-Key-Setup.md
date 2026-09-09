# API Key 快捷配置

日期：2026-09-09，0.1.0 build 5。用户确认停止修复 OpenRouter OAuth，改为只填写 API Key、选择或输入模型。

## 接法与界面

FlowDown 当前公开源码（提交 `a2fd55911720bfa0d11c1d4e354359d4801d9387`）未发现 OAuth 或 `ASWebAuthenticationSession` 实现；[云模型设置](https://github.com/Lakr233/FlowDown/blob/a2fd55911720bfa0d11c1d4e354359d4801d9387/FlowDown/Interface/SettingController/Model/ModelEditorController/CloudModelEditorController%2BContent.swift#L209) 使用推理端点和 Bearer token。此结论只针对核对的源码版本；前序其他 App 调研及 OAuth 尝试见 [历史方案记录](OpenRouter-Integration-Options.md)。

- 引导和设置共用同一配置区域。选择 OpenRouter、OpenAI、Gemini、DeepSeek 或 Anthropic 时预填服务地址，默认显示 API Key、模型和测试连接。
- 模型菜单只显示名称，可选“输入模型 ID”切换到手动输入。已保存的自定义模型直接显示输入框，不被推荐值覆盖。API Key 和模型未填完整时不能测试；测试通过前不能完成引导。
- 新建自定义兼容接口的地址与模型 ID 留空，等待用户填写；已有自定义配置保留。预设的更多选项保留必要的地址编辑、凭据说明，以及 OpenRouter keys 页和数据来源链接。主页面删除账号登录说明、OAuth、授权码入口与额外宣传文字。
- 主操作使用语义配色和既有按钮样式，API Key 使用安全输入框；继续保留 Apple 设备端模型。

## 协议与已有数据

OpenRouter 直接向固定 Chat Completions 端点发送用户的 Bearer API Key。删除 `OpenRouterOAuth.swift`、`OpenRouterCodeConnectionView.swift`、相关 URL 注册、授权文案及失效的 OAuth 测试；没有 browser session、PKCE 事务或换码请求。

运行时代码使用 `ProviderKind.openRouter`，保留历史 raw value `openRouterOAuth`，维持旧配置解码、Keychain scope 和使用记录的身份。旧模型、验证状态及可用 key 不被清空，也不需要将密钥复制到新 scope。输入 key 去除首尾空白后测试；新凭据仍只在设置 Done / 引导完成时落盘。

API Key、模型或端点改变后需要重新验证。既有 Responses / Chat / Messages 适配、固定主机保护、审核、费用记录和学习数据逻辑保持原行为。测试中的 key 均为本地 fixture，不发送到真实服务商。

## 验证与真机安装

- Xcode 27 beta，iPhone 17e 模拟器 / iOS 27.0，默认字号。42 项相关单元测试通过，覆盖旧 OpenRouter 配置及 scope、所有云服务预设端点、手填 key/model 的请求、401 错误、现有远端协议和领域回归。
- 中英文模型选择/手填、切换服务商后的未保存凭据清空、空 Key/模型禁止测试、未验证禁止继续，共 3 项 UI 测试在浅色/深色各通过一次。实际检查两种语言、两种外观的默认连接页和手填页，内容及主操作完整可见，没有裁切；浅色菜单和自定义兼容接口也已检查。
- `CheckBrand.py`、`CheckLocalization.py --stringsdata`（629 个目录条目、185 个动态标签、297 处编译提取使用）及 `git diff --check` 通过。模拟器构建及 iPhone Debug 签名构建成功；保留现有 AppIntents 元数据、iPad 方向警告，未在本轮处理。
- 已校验签名、版本 0.1.0（build 5）、调试 entitlement 和已移除的 scheme 注册。覆盖安装到用户 iPhone 17，设备查询确认 build 5，并成功启动 `com.alkinum.prompti`。没有卸载、清空 App 数据或使用测试启动参数。
- 测试与安装日志位于 `/Volumes/BRData/CodexBuilds/Prompti-APIKey-20260909/`。最终结果为 `light-final.xcresult` / `dark.xcresult`。初次测试编译发现错误断言要求 Equatable，改为匹配具体错误；随后 UI 回归发现新建兼容接口仍带 OpenAI 默认模型，修正为空白配置后全部通过，失败结果保留在原目录。

本轮没有使用真实 API Key 发起收费模型调用。UI 测试只验证输入及验证门槛，请求成功/401 由注入的离线响应验证，不代表真实账号权限、余额或指定模型质量已经通过。未执行全面 VoiceOver 或非常规超大字号验收。

## 实际 App 截图

截图来自 build 5 的 XCTest 附件；[浅色清单](ModelConnectionScreenshots/Build5/Light/manifest.json) / [深色清单](ModelConnectionScreenshots/Build5/Dark/manifest.json) 保留设备、测试方法和时间。手填页的安全输入框在系统截图中隐藏内容，所用 key 仅为 fixture。

| 页面 | 浅色 | 深色 |
| --- | --- | --- |
| 中文默认配置 | [查看](ModelConnectionScreenshots/Build5/Light/model-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-zh-Hans.png) |
| 英文默认配置 | [查看](ModelConnectionScreenshots/Build5/Light/model-en.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-en.png) |
| 中文模型菜单 | [查看](ModelConnectionScreenshots/Build5/Light/model-options-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-options-zh-Hans.png) |
| 英文模型菜单 | [查看](ModelConnectionScreenshots/Build5/Light/model-options-en.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-options-en.png) |
| 中文手填模型 | [查看](ModelConnectionScreenshots/Build5/Light/model-custom-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-custom-zh-Hans.png) |
| 英文手填模型 | [查看](ModelConnectionScreenshots/Build5/Light/model-custom-en.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-custom-en.png) |
| 中文兼容接口 | [查看](ModelConnectionScreenshots/Build5/Light/model-compatible-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-compatible-zh-Hans.png) |
| 英文兼容接口 | [查看](ModelConnectionScreenshots/Build5/Light/model-compatible-en.png) | [查看](ModelConnectionScreenshots/Build5/Dark/model-compatible-en.png) |
