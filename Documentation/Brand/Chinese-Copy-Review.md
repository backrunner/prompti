# 中文文案验收

日期：2026-09-08。文案基线见 [文案规范与市场文案](Copywriting.md)。本轮围绕中文表达修订，品牌标识、颜色、计分、安全策略、Provider 协议和持久化语义保持原有实现。

后续完成页已精简文案并加入全对礼花，最新画面见 [完成页与庆祝动效验收](Result-Celebration-Review.md)。本页保留文案修订时的截图。

## 修订范围

- 全量审读普通 UI 与系统权限两个 String Catalog，重写 206 条现有中文界面文案，另补齐功能说明、题目审核阶段及钥匙串错误的双语键，修订两条中文权限说明。
- 中文主句统一为“出发前，练好旅行常用语。”，欢迎页在逗号后换行；副文案说明点餐、问路、入住等具体用途。品牌预览、商店副标题、README 和品牌规范同步更新。
- 引导、首页、练习设置、生成状态、作答反馈、完成页、复习、进度、模型连接、费用说明、同步和错误恢复改用自然的中文。统一“参考答案”“待练题目”“全部记录”“已反馈”“未计分”等用词。
- “入门沟通”仅替换难度的中文显示名称；原有难度 ID、CEFR 对应和出题约束不变。完成页描述实际作答结果，不再宣称完成练习就已掌握表达。
- 生成阶段的“审核”与学习记录的“复习”使用不同翻译键；自定义场景按钮改为“添加”。钥匙串错误通过 String Catalog 显示可理解的中英文提示。
- 增加商店介绍与截图标题文案，均为仓库内物料，未发布到 App Store。

## 实际 App 检查

环境：Xcode 27.0 beta（27A5228h），iPhone 17e 模拟器，iOS 27.0，竖屏，系统默认字号 `large`。中文流程使用 `zh-Hans` / `CN`；英文欢迎页显式使用 `en_US`。全部图片来自实际 App 的 XCTest 附件，未经重绘；练习内容为 Demo fixtures。

46 张截图、测试方法和采集时间见 [原图清单](ChineseCopyScreenshots/manifest.json)。下表链接为每次检查时的可见区域，不表示已经截图整张滚动页面。检查确认中文标题、主要操作、提示与反馈正常换行；中英文欢迎页的功能说明完整可读。

| 页面 / 状态 | 浅色 | 深色 |
| --- | --- | --- |
| 中文欢迎页 | [原图](ChineseCopyScreenshots/light/onboarding-welcome.png) | [原图](ChineseCopyScreenshots/dark/onboarding-welcome.png) |
| 目的地引导 | [原图](ChineseCopyScreenshots/light/onboarding-destination.png) | [原图](ChineseCopyScreenshots/dark/onboarding-destination.png) |
| 学习语言 | [原图](ChineseCopyScreenshots/light/onboarding-language.png) | [原图](ChineseCopyScreenshots/dark/onboarding-language.png) |
| 模型连接 | [原图](ChineseCopyScreenshots/light/onboarding-model.png) | [原图](ChineseCopyScreenshots/dark/onboarding-model.png) |
| 练习偏好 | [原图](ChineseCopyScreenshots/light/onboarding-preferences.png) | [原图](ChineseCopyScreenshots/dark/onboarding-preferences.png) |
| 今日 | [原图](ChineseCopyScreenshots/light/home.png) | [原图](ChineseCopyScreenshots/dark/home.png) |
| 目的地列表 | [原图](ChineseCopyScreenshots/light/destination-picker.png) | [原图](ChineseCopyScreenshots/dark/destination-picker.png) |
| 练习设置 | [原图](ChineseCopyScreenshots/light/practice-setup.png) | [原图](ChineseCopyScreenshots/dark/practice-setup.png) |
| 生成中 | [原图](ChineseCopyScreenshots/light/generation-working.png) | [原图](ChineseCopyScreenshots/dark/generation-working.png) |
| 部分题目可用 | [原图](ChineseCopyScreenshots/light/generation-partial.png) | [原图](ChineseCopyScreenshots/dark/generation-partial.png) |
| 生成失败 | [原图](ChineseCopyScreenshots/light/generation-failure.png) | [原图](ChineseCopyScreenshots/dark/generation-failure.png) |
| 选择题反馈 | [原图](ChineseCopyScreenshots/light/practice-feedback.png) | [原图](ChineseCopyScreenshots/dark/practice-feedback.png) |
| 口语编辑与键盘 | [原图](ChineseCopyScreenshots/light/speech-edited.png) | [原图](ChineseCopyScreenshots/dark/speech-edited.png) |
| 口语未计分反馈 | [原图](ChineseCopyScreenshots/light/speech-feedback.png) | [原图](ChineseCopyScreenshots/dark/speech-feedback.png) |
| 完成页（全部跳过） | [原图](ChineseCopyScreenshots/light/practice-summary.png) | [原图](ChineseCopyScreenshots/dark/practice-summary.png) |
| 复习空状态 | [原图](ChineseCopyScreenshots/light/review-empty.png) | [原图](ChineseCopyScreenshots/dark/review-empty.png) |
| 进度空状态 | [原图](ChineseCopyScreenshots/light/progress-empty.png) | [原图](ChineseCopyScreenshots/dark/progress-empty.png) |
| 复习有数据 | 本轮未采集 | [原图](ChineseCopyScreenshots/dark/review-with-data.png) |
| 进度有数据 | 本轮未采集 | [原图](ChineseCopyScreenshots/dark/progress-with-data.png) |
| 设置 | [原图](ChineseCopyScreenshots/light/settings.png) | [原图](ChineseCopyScreenshots/dark/settings.png) |
| 英文欢迎页 | [原图](ChineseCopyScreenshots/light/welcome-default.png) | [原图](ChineseCopyScreenshots/dark/welcome-default.png) |

## 自动验证

- `python3 Tools/CheckBrand.py` 通过，最低文本对比 4.64:1。
- `python3 Tools/CheckLocalization.py --stringsdata /tmp/prompti-chinese-copy-build` 通过：642 个目录条目、185 个动态目录名称、323 处编译器提取用法；中文覆盖及参数类型、数量完整。
- 最终 `build-for-testing` 成功，启用 `SWIFT_EMIT_LOC_STRINGS=YES`。
- 现有 `ModelAndLocalizationTests` 的 7 项测试通过，其中接口预设测试包含 4 组参数；覆盖目录翻译仅作用于显示、自定义内容不误翻译、讲解语言默认值及英文单复数。
- 浅色共 12 个不同 UI 测试方法最终通过。首次部分生成用例因固定期待英文 `3 of 5` 而失败，中文实际为 `3 / 5`；修正现有双语数量断言后通过。最后的欢迎页换行与生成阶段用词变更重新构建后，重跑 4 个相关 UI 方法及上述 7 项单测，全部通过。
- 最终深色批次 13 个 UI 测试方法全部通过，包含上述 12 项及有数据的复习 / 进度流程。浅色和深色原图分别为 22、24 张。
- `git diff --check` 通过。最终批次的机器可读摘要见 [验证结果](ChineseCopyValidation.json)。

## 品牌物料

[Preview.html](Preview.html) 与重新导出的 [Preview.png](Preview.png) 已同步新主句和商店副标题。在 Chromium 中检查 1560px 与 390px 宽度，修正移动端标题断行和“获取”按钮换行，页面无横向溢出。PNG 从 1560 × 1080 的浏览器视口导出。

预览里的图标来自既有 Icon Composer 资源，商店区是排版示意，不是实际 App 截图。本轮没有改动品牌轮廓，不需要重新生成图标。

## 验收边界

- 逐条审读范围包括全部静态中文文案；未逐一触发所有网络、账号、钥匙串、权限与 iCloud 异常。自定义城市、场景表单和数据恢复页面仅完成文案与代码审查，未单独采集截图。
- 设置截图只覆盖当前可见区域，费用、同步与数据导入的全部表单项不能计作逐项视觉实测。
- 沿用 Demo 题目与所选讲解语言，题目内容中的英文不表示 UI 本地化失败。没有修改模型提示词或模型生成的练习内容。
- 本轮未进行真机、iPad、iOS 18 / 26、真实账号授权、收费模型请求、真实录音及双设备 iCloud 验收。保留已有无障碍适配，未将非常规超大字号作为验收门槛。
- 旧品牌及本地化截图保留为历史记录，最新中文文案以本页与新截图清单为准。
