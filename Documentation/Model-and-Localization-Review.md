# 模型选择与本地化验收

本页记录模型预设与本地化覆盖的实现。后续中文文案修订及最新界面截图见 [中文文案验收](Brand/Chinese-Copy-Review.md)。

## 当前版本：build 5 API Key 快捷配置

已按用户决定移除 OAuth 和授权码入口，预设服务商只需 API Key 与模型；模型支持菜单选择或手动输入。当前实现、实际截图和验证范围见 [API Key 配置验收](API-Key-Setup.md)。以下 build 4 及更早截图保留为历史，不代表最新产品入口。

## 2026-09-09：build 4 授权码入口

“使用授权码连接”直接显示在 OpenRouter 主按钮下方。模型下拉继续只显示名称，详细连接说明保留在展开项。授权码页直接打开官方 `/auth`，再次打开浏览器保留当前事务；新增重新打开按钮的英文/简体中文翻译。

Xcode 27 beta，iPhone 17e 模拟器，iOS 27.0，默认字号。19 项相关单元测试通过；中英文模型选择、授权码页初始状态及关闭、原生授权取消/重试的 3 项 UI 测试在浅深色各通过一次。实际检查两种语言、两种外观的连接页及授权码页，入口、字段、操作和说明完整可见，无裁切。品牌检查、本地化检查（647 个条目、316 处编译提取使用）、模拟器与 iPhone Debug 签名构建通过。

以下均为 build 4 实际 App 的 XCTest 附件；保留上一轮截图作为历史。元数据：[浅色](ModelConnectionScreenshots/Build4/Light/manifest.json) / [深色](ModelConnectionScreenshots/Build4/Dark/manifest.json)。

| 实际页面 | 浅色 | 深色 |
| --- | --- | --- |
| 中文连接 | [查看](ModelConnectionScreenshots/Build4/Light/model-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-zh-Hans.png) |
| 中文授权码 | [查看](ModelConnectionScreenshots/Build4/Light/model-code-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-code-zh-Hans.png) |
| 中文模型菜单 | [查看](ModelConnectionScreenshots/Build4/Light/model-options-zh-Hans.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-options-zh-Hans.png) |
| 英文连接 | [查看](ModelConnectionScreenshots/Build4/Light/model-en.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-en.png) |
| 英文授权码 | [查看](ModelConnectionScreenshots/Build4/Light/model-code-en.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-code-en.png) |
| 英文模型菜单 | [查看](ModelConnectionScreenshots/Build4/Light/model-options-en.png) | [查看](ModelConnectionScreenshots/Build4/Dark/model-options-en.png) |

授权页本身、登录后返回、真实 code 换取及模型验证不在这些 UI 测试的通过范围；未执行真实账号授权、收费调用或非常规超大字号验收。build 4 已覆盖安装到用户 iPhone 17，设备锁屏阻止自动启动；详见 [接法复核与验证边界](OpenRouter-Integration-Options.md)。

## 2026-09-09：连接区域精简

模型下拉现在只显示名称，删除调用次数和按用量分组的标题。连接区域移除宣传标语、排名解释和日期段落，保留服务商/模型选择、连接按钮、更多连接选项及一句数据处理/费用提示；完整说明和来源链接位于展开内容。推荐排序与连接验证语义不变。

Xcode 27 beta、iOS 27.0、iPhone 17e 模拟器，默认字号。中英文连接页面、纯名称菜单、选择模型后保持未验证状态，以及取消登录再重试，在浅色/深色各 3 项 UI 测试通过；19 项相关单元测试通过。模拟器与通用 iPhone Debug 构建、品牌检查、本地化检查（646 个目录条目、315 处编译器提取使用）通过。

以下为本轮实际 App 截图，均来自 XCTest 附件，未使用真实账号或付费模型。元数据见 [浅色清单](ModelConnectionScreenshots/Light/manifest.json) / [深色清单](ModelConnectionScreenshots/Dark/manifest.json)。OpenRouter 登录返回地址的修改与尚未完成的真实账号验收见 [OAuth 记录](OpenRouter-Sign-In-Fix.md)。

| 实际页面 | 浅色 | 深色 |
| --- | --- | --- |
| 中文连接 | [查看](ModelConnectionScreenshots/Light/model-zh-Hans.png) | [查看](ModelConnectionScreenshots/Dark/model-zh-Hans.png) |
| 中文模型菜单 | [查看](ModelConnectionScreenshots/Light/model-options-zh-Hans.png) | [查看](ModelConnectionScreenshots/Dark/model-options-zh-Hans.png) |
| 英文连接 | [查看](ModelConnectionScreenshots/Light/model-en.png) | [查看](ModelConnectionScreenshots/Dark/model-en.png) |
| 英文模型菜单 | [查看](ModelConnectionScreenshots/Light/model-options-en.png) | [查看](ModelConnectionScreenshots/Dark/model-options-en.png) |

## 2026-09-08：此前验收

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
