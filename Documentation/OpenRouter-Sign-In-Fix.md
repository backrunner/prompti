# OpenRouter 登录入口修复

当前状态：用户决定停止使用 OAuth，build 5 已移除浏览器登录、授权码流程和回调注册，改为 API Key 快捷配置，见 [当前实现与验收](API-Key-Setup.md)。下文保留各轮 OAuth 尝试及失败记录，不代表当前产品入口。

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

## 2026-09-09：回调兼容与会话取消

收到 OAuth 仍走不通的反馈后，公开 HTTP 请求和独立浏览器均确认当前 `/sign-in?redirect_url=…` 可显示登录表单，登录页中的注册链接也保留完整授权 URL。此阶段尚未取得具体卡点，下面两处改动没有证明真实账号授权已经正常。后续用户补充“登录后进入首页、未看到授权页”，针对登录返回地址的处理见下一节。

- 旧回调为 `prompti://oauth/openrouter?state=<nonce>`，解析器要求 query 中同时存在 state 和 code。OpenRouter 官方协议只约定返回 code，没有承诺 echo OAuth state 或如何合并 callback 中已有的 query。将 nonce 移到路径：`prompti://oauth/openrouter/<nonce>`；服务商追加 `?code=…` 即可解析。保留每次独立 nonce、S256、精确回调校验；缺少/错误 nonce、重复或空 code、error、fragment、用户信息和端口均拒绝。没有降级为接受缺少 nonce 的旧回调。
- 旧 `cancel()` 仅关闭系统浏览器，没有恢复 `withCheckedThrowingContinuation`，父任务取消也未桥接到浏览器取消。现在主动结束等待并关闭对应浏览器，按会话 ID 忽略旧回调，启动失败和重复 completion 都只恢复一次。新的登录尝试会先取消旧的等待。
- 使用 iOS 17.4+ 的 `.customScheme("prompti")` 回调 API，仍满足 iOS 18 最低版本。换码请求、Provider 协议、Keychain 和模型探测语义保持既有行为。

本轮验证（Xcode 27 beta，iPhone 17e 模拟器，iOS 27.0）：

- 12 项 OAuth 单元测试通过，包含 3 组双参数用例；覆盖 RFC 7636、原生/手动授权 URL、只追加 code 的回调、无效回调、换码请求、凭据隔离及浏览器生命周期。
- 新增原生 UI 测试在默认字号浅色、深色各通过一次：从引导进入 OpenRouter，连续两次在系统确认框取消，确认 App 显示取消提示、按钮恢复且可再次登录。在系统确认框拒绝后不会加载授权网页，不依赖账号或网络。实际 App 截图附在各自的 xcresult 中；App 为英文、系统确认框为简体中文。首轮 UI 测试因系统中文按钮不匹配英文选择器失败，适配后浅深色均通过。
- 模拟器测试构建、通用 iPhone Debug 构建（关闭签名）、品牌检查、本地化静态检查及 `git diff --check` 通过。现有 AppIntents 元数据与 iPad orientation 构建警告未在本轮处理。未进行真机签名安装。
- 本地结果：`/tmp/prompti-oauth-fix-tests.xcresult`、`/tmp/prompti-oauth-ui-light-retry.xcresult`、`/tmp/prompti-oauth-ui-dark.xcresult`；截图导出在 `/tmp/prompti-oauth-review/`。本轮没有修改 App 布局或用户可见文案。

没有输入真实账号、确认账号授权或执行收费调用；真实 OpenRouter 对自定义 scheme 的接受、登录后的跳转、换码和模型额度仍待设备端验证。以上测试不能代替真实账号的端到端验收。

## 2026-09-09：登录后返回授权页与连接区域精简

用户确认此前登录成功后进入 OpenRouter 首页，没有看到 OAuth 授权页。这个现象发生在回调 App 和换码之前，上一节的回调/取消测试不能验证它。

`signInURL` 现在把 `redirect_url`、`sign_in_force_redirect_url`、`sign_up_force_redirect_url` 都设置为同一条完整 `/auth` 请求。OpenRouter 使用的 Clerk 登录组件允许强制返回配置覆盖普通 `redirect_url`；显式设置登录和注册的返回目标，确保切换账号入口时仍以本次授权页为目标。原生与手动授权码流程共用此构造，verifier 不进入 URL。

依据：[Clerk 自定义返回地址与 force redirect 的优先级](https://clerk.com/docs/guides/custom-redirects)。本地独立浏览器加载真实 OpenRouter 登录页后，确认注册链接保留两个 force 参数；点击 Google 登录并在发出请求前拦截，确认 `action_complete_redirect_url` 为完整 `/auth`，SSO callback 也携带两个 force 参数。没有提交登录请求或输入账号。对照检查中，旧 URL 在初始 Google 登录请求里也保留了 `/auth`，因此不能将本轮检查写成已复现真实登录后的首页跳转；它验证的是新增返回参数确实被当前登录组件采用。

连接 UI 删除模型名称后的调用次数、按用量分组、营销标语和排名说明。默认只保留必要控件与一句数据处理/费用提示，完整隐私说明和数据来源收进“更多连接选项”。推荐排序、模型 ID、凭据存储和连接验证语义保持既有行为；新短文案加入英文/简体中文 String Catalog。

本轮 19 项相关单元测试通过；iPhone 17e / iOS 27.0 默认字号，中英文模型选择、连接未验证状态及原生登录取消/重试的 3 项 UI 测试在浅色/深色分别通过。模拟器构建、通用 iPhone Debug 构建（不签名）、品牌检查、本地化编译提取检查和 diff 检查通过。结果为 `/tmp/prompti-oauth-redirect-light.xcresult` / `/tmp/prompti-oauth-redirect-dark.xcresult`；UI 截图及覆盖范围见 [最新连接区域验收](Model-and-Localization-Review.md)。没有真机安装、真实账号授权、换码或付费模型调用；首页跳转的端到端修复仍待真实账号验证。

## 2026-09-09：安装调试 build 3

按用户要求，将包含上述 UI 精简及 OAuth 修改的 0.1.0（build 3）Debug 版本覆盖安装到已连接的 iPhone 17（iOS 27.0）。`project.yml` 与 Xcode 工程构建号同步从 2 升为 3；真机签名构建及 codesign 校验通过，确认 `get-task-allow` 已启用。

设备安装后查询确认版本为 build 3，随后成功启动 `com.alkinum.prompti`。使用相同 bundle ID 覆盖更新，没有卸载或清除 App 数据，也没有传入 Demo/清理测试参数。真实账号 OAuth 授权仍由后续设备实测确认，不把安装成功记作授权流程已通过。

## 2026-09-09：官方入口、无回调授权码与 build 4

用户实测 build 3 登录后仍进入首页。撤掉 `/sign-in` 和 Clerk force redirect 包装，原生和授权码流程均直接进入官方 `/auth`。授权码入口移到主连接按钮下方，省略 `callback_url`，同一页面重新打开浏览器保留 verifier 与输入。行业源码、HTTPS 关联域名要求与未证实的 scheme 兼容性见 [接法复核](OpenRouter-Integration-Options.md)。

已完成 iPhone Debug 签名构建、严格 codesign 校验，确认版本为 0.1.0（build 4）及 `get-task-allow = true`。覆盖安装到同一台 iPhone 17 后，设备查询确认 `bundleVersion = 4`；没有卸载、清空数据或传测试启动参数。自动启动被设备锁屏拒绝（`FBSOpenApplicationErrorDomain / Locked`），本轮不记为已启动或真机授权通过。

构建和测试产物位于 `/Volumes/BRData/CodexBuilds/Prompti-OAuth-20260909/`；此前由本任务生成的三个 DerivedData 目录移到该目录的 `previous/`，保留旧产物。首次测试遇到系统盘空间不足，迁移后编译通过，但模拟器遗留的 testmanagerd socket 路径不存在；重启该模拟器并复用构建产物后恢复运行，没有清除模拟器数据。

最终 19 项相关单元测试通过，3 项中英文连接/授权码和系统取消/重试 UI 测试在默认字号浅深色各通过一次（`light-retry.xcresult` / `dark.xcresult`）。品牌、本地化编译提取和 diff 检查通过。实际截图见 [build 4 视觉验收](Model-and-Localization-Review.md)。这些结果不包含真实账号授权、code 兑换或模型调用，不能据此认定首页跳转已修复。
