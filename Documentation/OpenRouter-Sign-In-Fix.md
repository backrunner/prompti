# OpenRouter 登录入口修复

日期：2026-09-08。

未登录时，OpenRouter 的 `/auth` 会以 HTTP 307 跳到 `/sign-up`，导致用户在 Prompti 点击连接账号后看到注册页。

原生 `ASWebAuthenticationSession` 和手动复制授权码的浏览器入口现在都先打开 `/sign-in`，通过 `redirect_url` 携带完整的 `/auth` 授权 URL。登录后继续原有授权；`code_challenge`、S256、key label、嵌套 callback/state 均保留，手动流程继续省略 callback_url。URL 使用 URLComponents 编码；verifier 仍只用于后续换码，不进入浏览器 URL。

依据：[OpenRouter PKCE 文档](https://openrouter.ai/docs/guides/overview/auth/oauth)。`/sign-in?redirect_url=…` 同时是 OpenRouter 官方文档导航使用的登录与返回页面方式。

## 验证

- 公开未登录 HTTP 请求复现旧入口的 307 → `/sign-up`；修正后的 `/sign-in` 返回 HTTP 200，标题为 `Sign In | OpenRouter`，完整授权 URL 保留在返回参数中。
- iPhone 17e 模拟器、iOS 27.0、Xcode 27 beta：7 项 OAuth 测试通过。新增参数化用例分别检查原生回调与手动授权码入口，其余用例覆盖 RFC 7636 向量、callback/state、换码和凭据隔离。
- 模拟器测试构建、iPhone Debug 签名构建、codesign 校验、品牌检查、本地化提取检查与 `git diff --check` 通过。
- 新版已覆盖安装到调试 iPhone 17，保留现有 App 数据。

本次没有修改 App 的布局或用户可见文案。公开页面检查和本地测试未输入真实账号，也未执行真实账号确认授权、换取 key 或收费模型调用；这些不记为已完成的端到端验证。
