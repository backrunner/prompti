# 模型选择与本地化验收

本页记录模型预设与本地化覆盖的实现。后续中文文案修订及最新界面截图见 [中文文案验收](Brand/Chinese-Copy-Review.md)。

日期：2026-09-08。iPhone 17e 模拟器，iOS 27.0，默认字号，浅色 / 深色。全部截图来自实际 App 的 XCTest 附件，练习数据为 Demo fixtures。原图、测试方法和时间见 [截图清单](ModelLocalizationScreenshots/manifest.json)。

## 模型选择

引导与设置共享快速模型目录。OpenAI 推荐 GPT-5.6 Luna，Gemini 推荐 3.8 Flash / 3.5 Flash-Lite，DeepSeek 推荐 V4 Flash，Anthropic 推荐 Haiku 4.5。Gemini 与 DeepSeek 可直接填写各自的 API key，继续使用既有 Chat 适配器。自定义模型和已保存配置不因推荐变化而被替换。

OpenRouter 列出 8 个已核实的快速模型。公开周请求次数可匹配的 4 个候选按调用量排序；其余 4 个在“暂无调用量数据”分组中列出。快照截至 **2026-09-06**，不是实时排名或所有模型的全量请求榜单。

| 已核实候选 | 近 7 天请求次数 |
| --- | ---: |
| DeepSeek V4 Flash 0731 | 494,967,610 |
| GPT-5.6 Luna | 418,787,054 |
| GLM 5.3 Flash | 368,973,973 |
| Gemini 3.7 Flash | 65,441,986 |

Source: OpenRouter (https://openrouter.ai/rankings), as of 2026-09-06. Licensed under CC BY 4.0. 数字来自公开页面周数据的 `count`，按 canonical slug 关联当前模型 ID；没有将 token 排名用作请求次数排名。更新工具、来源与协议边界见 [模型规范](../.agents/05-ai-byok-and-generation.md)。

| 实际页面 | 浅色 | 深色 |
| --- | --- | --- |
| 中文模型连接 | [查看](ModelLocalizationScreenshots/Light/model-zh-Hans.png) | [查看](ModelLocalizationScreenshots/Dark/model-zh-Hans.png) |
| 英文模型连接 | [查看](ModelLocalizationScreenshots/Light/model-en.png) | [查看](ModelLocalizationScreenshots/Dark/model-en.png) |
| 中文模型菜单 | [查看](ModelLocalizationScreenshots/Light/model-options-zh-Hans.png) | [查看](ModelLocalizationScreenshots/Dark/model-options-zh-Hans.png) |
| 英文模型菜单 | [查看](ModelLocalizationScreenshots/Light/model-options-en.png) | [查看](ModelLocalizationScreenshots/Dark/model-options-en.png) |
| Gemini 中文连接 | [查看](ModelLocalizationScreenshots/Light/gemini-zh-Hans.png) | [查看](ModelLocalizationScreenshots/Dark/gemini-zh-Hans.png) |
| Gemini 英文连接 | [查看](ModelLocalizationScreenshots/Light/gemini-en.png) | [查看](ModelLocalizationScreenshots/Dark/gemini-en.png) |

## 本地化覆盖

- 目录的城市、国家、地标、语言和内置场景统一按显示语言翻译；首页、引导、练习、生成、复习和进度使用相同规则。中文和原始英文名称都可搜索。保存的 ID、统计、生成上下文和用户自定义原文保持原值。
- 补齐错误恢复、举报理由、麦克风 / 语音识别权限文案、动态错误、字段占位符及英文单复数。界面语言与学习语言分开；新用户默认讲解语言跟随首选中文 / 英文，已有设置保留。
- 动态目录键保留为手工维护项，避免代码提取器误标过期。新增本地化检查纳入 CI，验证中文完整性与格式参数，并支持检查 Swift 编译器提取出的字符串。

实际浅色流程：[首页](ModelLocalizationScreenshots/Light/home-zh-Hans.png)、[中文搜索北京](ModelLocalizationScreenshots/Light/destination-search-zh-Hans.png)、[生成](ModelLocalizationScreenshots/Light/generation-zh-Hans.png)、[练习配置](ModelLocalizationScreenshots/Light/practice-setup.png)、[作答反馈](ModelLocalizationScreenshots/Light/practice-feedback.png)、[复习](ModelLocalizationScreenshots/Light/review-with-data.png)、[进度](ModelLocalizationScreenshots/Light/progress-with-data.png)、[设置](ModelLocalizationScreenshots/Light/settings.png)。

## 验证结果与边界

- Debug 构建成功。73 个 Swift Testing 测试通过；最终使用原生 String Catalog 复数格式后，模型与本地化的 7 项再次通过，包含 4 个服务端点、调用量排序、自定义模型保留、目录与用户原文分离、默认讲解语言和英文单复数。
- 最终浅色 6 项 UI 测试、深色 3 项 UI 测试通过：中英文模型菜单、选定 Gemini、直接连接的正确模型 ID、未验证时阻止继续，以及中文搜索 / 生成、设置、练习选择 / 反馈、复习 / 进度。两种外观下模型名称、数量说明与底部操作可读可用。
- `CheckLocalization.py` 通过：640 个目录条目（含不翻译的品牌 / 数字模板），185 个动态目录标签，322 处编译器提取使用；`CheckBrand.py` 与 `git diff --check` 通过。
- 未调用真实收费模型，没有将账号权限、真实生成质量或延迟写成已验证。系统权限翻译已编译，未逐一触发原生权限弹窗。未增加其他完整 UI 语言，也未执行全面 VoiceOver 或非常规超大字号验收。
- 旧历史缺少可识别场景 ID 时保留原文，避免误翻译用户场景。模型请求数快照需要发布前刷新，公开页面数据结构改变时更新工具会停止并保留旧资源。
