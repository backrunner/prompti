# 生成等待与连接设置 · 2026-09-18

## 问题与修正

用户反馈 OpenRouter DeepSeek V4.1 在 0 道题处等待几十秒后超时。复核发现：

- 生成页只有静态阶段图标；计数只统计完成生成、校验、去重、审核并落库的题目，所以请求期间一直显示 0。
- 单次生成和审核各有 60 秒截止，整组为 180 秒。OpenRouter 当前对 `deepseek/deepseek-v4.1-flash` 默认开启高强度思考，旧请求未覆盖该默认值。公开元数据明确允许关闭思考；这会增加等待时间，是本轮发现的延迟风险，但没有用户该次调用的服务端日志，无法证明它是唯一原因。
- “更多连接方式”以说明文字为主，对 OpenRouter 没有额外配置控件。

初步修正为：工作期间显示系统加载指示；降低动态效果时使用静态沙漏。首批到达前显示中英文等待文案，有过审题才显示真实题数，完成/失败状态恢复静态图标。第一版只针对 OpenRouter DeepSeek V4.1 发送 `reasoning: { enabled: false }`；随后用户明确强制思考模型仍需保留，当前最终参数策略见文末“强制思考模型与低强度”。单次/整体截止、安全质量标准、审核步骤、统计与保存规则保持原行为。

设置和引导共用的“更多连接方式”折叠区与重复长说明已删除。保留直接可用的自定义兼容地址、API Key、模型选择/手填、连接测试和费用提示；OpenRouter 获取 Key 与 CC BY 4.0 来源链接直接显示。既有自定义配置仍显示地址。

## 协议依据

- [OpenRouter 模型元数据](https://openrouter.ai/api/v1/models)：[本次模型字段快照](GenerationReview/Loading/model-capabilities.json) 记录 `mandatory: false`、`default_enabled: true`、`default_effort: high`。
- [OpenRouter reasoning 参数](https://github.com/OpenRouterTeam/docs/blob/main/guides/best-practices/reasoning-tokens.mdx)：使用统一 `reasoning.enabled` 控制开关；`exclude` 只隐藏返回内容，不能消除思考耗时。
- [DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode)：官方文档说明默认开启思考，支持关闭。实际 OpenRouter 请求使用网关统一参数，不向其透传 DeepSeek 专用字段。

## 验证

- Xcode 27.0，iPhone 17 模拟器（Prompti-Generation-Review），iOS 27.0 / 24A5390f，默认字号 large。
- 构建及 97 项单元/协议/持久化测试通过；含参数化执行 144 次，0 失败/跳过。新增用例覆盖 DeepSeek 生成、审核、探测及格式回退的思考参数，其他模型/端点隔离，响应头前和响应体中途停滞的真实 URLSession 取消行为。停滞测试使用本地 URLProtocol fixture，150ms 截止在 1 秒内返回。
- `CheckBrand.py`、`CheckLocalization.py --stringsdata`（640 个键、185 个动态标签、299 处编译提取使用）与 `git diff --check` 通过。编译仅有现有 AppIntents 元数据提取提示。
- UI 自动化的中文连接流程通过，包含移除折叠入口、模型选择/手填、自定义地址与未验证门槛。英文用例输入 `my-custom-model` 时系统自动输入实际得到 `my-custo-model`，断言失败。随后生成页用例停在 App 启动/自动化会话阶段，尚未点击生成；进程采样显示主线程等待 RunLoop，并非正在执行模型请求。中断、重启专用模拟器后缩减为生成页/设置页重跑，仍停在测试进程启动阶段，已终止。日志摘录：[首次运行](GenerationReview/Loading/light-interrupted.log)、[重启后](GenerationReview/Loading/retry-startup-interrupted.log)。
- 首次尝试的浅/深色加载页与设置页视觉验收 **未完成**（后续成功补验见文末）；没有将旧截图、概念图或启动画面当作本轮验收。中文流程的测试日志不替代实际加载图标的视觉检查。原始构建/测试日志及通过的单元结果在 `/tmp/prompti-generation-*`，未完成的 UI result bundle 不计为通过。

## 验证边界

未使用真实 API Key 发起付费模型请求，未在真实设备端 Apple 模型上测试。因此没有实测 DeepSeek 修正前后首题延迟，也不能承诺所有服务商负载下均不超时。模型质量仍由现有校验/审核把关；关闭额外思考后的真实多语言输出质量需要后续抽样。UI 截图使用实际 App 的 DEBUG demo 数据，不代表真实模型生成效果。本次工作保留工作区并行的答题页滚动布局改动，该改动另行验收。


## 强制思考模型与低强度

用户随后明确：强制思考的模型继续保留，但思考强度统一设置为最低的 `low`。因此当前请求策略按能力分两类：允许关闭的模型使用显式关闭参数；强制思考的模型继续请求，并使用最低强度，不返回“需要思考”的前置错误。

- OpenRouter：普通模型发送 `reasoning: { enabled: false }`，强制模型发送 `reasoning: { effort: "low" }`。
- OpenAI Responses：普通模型发送 `reasoning.effort=none`，GPT-5/mini/nano 等强制模型发送 `low`。
- OpenAI Chat、Gemini OpenAI 兼容和通用 Chat：普通模型发送 `reasoning_effort=none`，强制模型发送 `low`。
- DeepSeek 官方 Chat：普通模型发送 `thinking.type=disabled`，DeepSeek R1 等强制模型发送 `thinking.type=enabled` 和 `reasoning_effort=low`。
- Anthropic Messages：当前推荐模型使用 `thinking.type=disabled`，不发送 OpenAI 的 `reasoning_effort` 字段。
- OpenAI GPT-4/GPT-3.5 等旧模型不支持 reasoning，继续省略不兼容字段。

推荐列表恢复并保留原有强制思考候选，Gemini 官方预设也继续使用 Gemini 3 系列。推荐刷新工具不再因 `reasoning.mandatory` 报错；模型目录的能力信息只用于选择关闭或低强度参数。所有生成、审核、场景审核、口语评估、连接探测和结构化格式回退共用这套策略。

验证覆盖全部内置 OpenRouter 推荐、官方协议、Gemini/DeepSeek 端点、强制模型低强度参数、可关闭模型显式关闭、旧模型字段兼容性，以及参数被拒后的 JSON mode 回退。仍未使用真实 API Key 发起付费请求，因此没有把离线参数检查当作真实服务延迟或模型质量证明。
