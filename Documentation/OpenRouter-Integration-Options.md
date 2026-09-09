# OpenRouter 原生连接方式复核

日期：2026-09-09。触发：用户在 iPhone 上确认 build 3 登录后仍进入 OpenRouter 首页，没有看到授权页。

## 当前决定：移除 OAuth

用户在本轮调研后决定使用 API Key 快捷配置。再次检索 FlowDown 当前源码（提交 `a2fd55911720bfa0d11c1d4e354359d4801d9387`）中的 OAuth / `ASWebAuthenticationSession` 及云模型设置，没有发现 OAuth 实现；[云模型凭据编辑器](https://github.com/Lakr233/FlowDown/blob/a2fd55911720bfa0d11c1d4e354359d4801d9387/FlowDown/Interface/SettingController/Model/ModelEditorController/CloudModelEditorController%2BContent.swift#L209) 明确将 token 作为 Bearer 凭据发送。该结论限定于核对的源码版本。

Prompti build 5 移除 OAuth、授权码和 scheme 注册，只需 API Key + 选择或输入模型，详见 [API Key 配置验收](API-Key-Setup.md)。以下保留此前方案研究和 build 4 验证记录。

## 结论与证据边界

此前对 `/sign-in`、Clerk force redirect 参数和回调 query 的修改没有解决用户实测问题。登录前 URL 参数保留、取消测试和构建成功，均不能证明登录后的授权页面已出现。当前没有足够证据将根因认定为 iOS 不支持 scheme，或 OpenRouter 拒绝所有自定义 scheme。

OpenRouter [官方 PKCE 文档](https://openrouter.ai/docs/guides/overview/auth/oauth) 指定从 `/auth` 发起授权，让服务商处理登录；文档明确列出网页 callback、localhost callback 和不传 callback 的授权码流程，没有明确承诺原生自定义 scheme。Prompti 之前自行跳到 `/sign-in` 是额外的登录站点耦合，本轮撤掉该包装。

## 已核对的其他 App 源码

| App | 可核实的接法 | 对 Prompti 的启示 |
| --- | --- | --- |
| Cline / VS Code 桌面版 | [发起授权](https://github.com/cline/cline/blob/2dd8f11ada77947b3a8fb04303ca05b4527f391b/apps/vscode/src/core/controller/account/openrouterAuthClicked.ts) 直接打开 `https://openrouter.ai/auth`；[桌面回调](https://github.com/cline/cline/blob/2dd8f11ada77947b3a8fb04303ca05b4527f391b/apps/vscode/src/extension.ts#L570) 使用 `vscode://<extension-id>/openrouter`，Web 版转换为 HTTPS | 自定义 scheme 是真实项目采用过的方案，但桌面实现不能作为 iOS 已兼容的证明。首先应使用官方 `/auth` 入口。 |
| FlowDown / 原生 iOS | [云模型编辑器](https://github.com/Lakr233/FlowDown/blob/a2fd55911720bfa0d11c1d4e354359d4801d9387/FlowDown/Interface/SettingController/Model/ModelEditorController/CloudModelEditorController%2BContent.swift#L194) 填完整推理端点和 Bearer 凭据 | 可以走 API Key/凭据直连，不必强制账号 OAuth。此处核对的是云模型配置实现，没有将它描述为 OpenRouter 专用 OAuth。 |
| Chatbox | [OpenRouter Provider](https://github.com/Bin-Huang/chatbox/blob/e97c1dbd4ad02d6e017b6ac4176e103f3175cb64/src/shared/providers/definitions/openrouter.ts) 使用 `effectiveApiKey`；[OAuth 映射](https://github.com/Bin-Huang/chatbox/blob/e97c1dbd4ad02d6e017b6ac4176e103f3175cb64/src/shared/oauth/provider-mapping.ts) 不含 OpenRouter | Provider 已支持，不代表该 Provider 有账号 OAuth；API Key 是可单独使用的路径。 |

以上为指定提交的公开源码核对，未登录这些 App 做现场端到端测试。

## 可用形式

1. **官方 `/auth` + 自定义 scheme**：保留现在的自动返回体验和 S256。需要在 iPhone 上验证服务商确实回到 `prompti://…`。本轮修正为直接 `/auth`，不再传 Clerk 登录页返回参数。
2. **官方无回调授权码**：省略 `callback_url`，仍发送 `code_challenge`、S256 和 `key_label`。官方页面显示一次性 code，用户复制到 App，本机使用原 verifier 换 key；code 单次使用、10 分钟有效。它不依赖自定义 scheme、域名或服务端，可直接作为备用方式。
3. **HTTPS 自动回调**：Apple 的 [`ASWebAuthenticationSession.Callback.https(host:path:)`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)) 要求 host 属于与 App 关联的域名。需要控制域名、部署域名关联文件并配置 entitlements。当前项目没有这套关联域名，不能随意填写一个 HTTPS 地址就认为自动返回可用。也可以建设自己的 HTTPS 转发页再回 App，但那是需要单独部署和验证的网页环节。
4. **API Key**：用户从 [OpenRouter keys](https://openrouter.ai/keys) 创建/复制 key，使用已有安全字段和连接探测，不经过网页 OAuth。

## 本轮实现

- 原生和授权码方式都直接打开 `/auth`，移除 `signInURL` 和所有 force redirect 参数。
- 授权码入口移到主连接按钮下方；保留上轮的精简文字及只显示名称的模型菜单。
- 授权码页再次打开浏览器时保留原 verifier 和用户输入，便于登录落到其他页面后重新进入同一次授权。关闭该页后重新进入会创建新事务。
- 延续上一轮的 nonce/PKCE 校验、取消与迟到回调隔离、固定换码端点和 Keychain 语义。

后续真实账号验收必须分别记录：出现授权确认页、得到 code、换码成功、模型验证成功。源代码检查、普通页面可达及模拟器 UI 测试只能覆盖各自范围。

## build 4 验证与安装

- Xcode 27 beta、iPhone 17e 模拟器 / iOS 27.0：19 项相关单元测试通过；中英文模型选择与授权码页面、系统登录取消/重试共 3 项 UI 测试在默认字号浅色/深色各通过一次。
- 实际截图已检查：连接入口、授权码操作与中英文说明完整显示，浅深色均无裁切；截图与覆盖范围见 [模型与本地化验收](Model-and-Localization-Review.md)。授权码界面测试只检查打开页面、初始禁用状态及关闭页面，未输入或兑换真实 code。
- 模拟器与 iPhone Debug 签名构建通过。品牌检查、本地化检查（647 个目录条目、185 个动态标签、316 处编译提取使用）及 diff 检查通过。
- 0.1.0（build 4）已覆盖安装到用户 iPhone 17，设备查询确认版本。保留 App 数据；自动启动因设备锁屏被拒绝，需解锁后打开。签名校验通过，已启用调试 entitlement。
- 结果保存在 `/Volumes/BRData/CodexBuilds/Prompti-OAuth-20260909/light-retry.xcresult` 和 `dark.xcresult`。首轮系统盘空间和模拟器 socket 故障及恢复过程记录在 [OAuth 历史](OpenRouter-Sign-In-Fix.md)。

真实账号登录后的授权页、自动回调、授权码展示、换码和模型额度仍未验证；本轮不宣称首页跳转已端到端修复，也未部署 HTTPS 回调或调用收费模型。
