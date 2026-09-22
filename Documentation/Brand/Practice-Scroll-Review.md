# 练习页固定题目与滚动验收

日期：2026-09-18。

题号与场景固定在顶部，题目区和答案区分开布局。选项、多空完形、口语控件及提交后的反馈在下方独立滚动，底部操作继续使用 safe-area inset 和不透明 `PromptiActionScrim`。切换题目重建滚动区域，回到顶部。

题目优先按完整内容显示；题干特别长或键盘压缩可用高度时，上方题目区可以单独滚动，最多使用剩余阅读高度的一半，为答案保留空间。两处滚动均复用 `PromptiScrollView`，仅在对应方向有溢出内容时显示渐隐，到达边界移除，不拦截触控。

填空题未作答空位改用 `___` 下划线，与原始填空题的标记一致；多空题逐空选择后回填对应答案。

本轮仅调整练习页布局、填空占位与 Debug 验收素材，不改变计分、内容审核、Provider 协议或持久化语义。长选项素材仅在 UI 测试启动参数下使用，不是模型实际生成结果。

## 验证

- 品牌检查通过。
- 本地化检查及编译器提取检查通过，无新增正式界面文案。
- 最终版本模拟器 `build-for-testing` 通过，包含 App 与现有单元 / UI 测试 target；构建日志：`/tmp/prompti-scroll-build-verified.log`。
- 已添加长选项 UI 回归：检查滚动前后题干位置、末项完整露出、底部操作固定、反馈滚动和下一题回到顶部。
- 首次滚动修复验收遇到独立 iPhone 17e / iOS 27.0 模拟器启动服务阻塞：Xcode 采样停在 `SimDevice launchApplicationWithID` / `host_support_mig_launch_app`，主动中止。后续修改填空占位时模拟器恢复，补测结果见下方。
- 口语键盘、退出、完成流程及边缘状态单测的运行时复核仍未完成；不能从以下两项 UI 测试推断其他场景全部通过。

## 验收边界

本轮不覆盖真机、iPad、旧版 iOS、真实录音或人工 VoiceOver。保留既有无障碍适配，不将非常规超大字号作为验收门槛。

## 下划线占位与滚动补测

- 最新 `build-for-testing`、品牌检查、本地化及编译器提取检查、`git diff --check` 通过。构建日志：`/tmp/prompti-cloze-underline-build-final.log`。
- iPhone 17e / iOS 27.0 / 默认字号，英文浅色、简体中文深色的 `testMultipleBlanksRequireEveryAnswer` 与 `testLongAnswersKeepPromptPinnedAndResetForNextQuestion` 均通过，共 4 次。
- 已目视检查浅深色未作答下划线、部分作答回填、全部作答反馈；长选项顶部与底部、反馈滚动、短题重置。题目固定，底部最后选项完整露出，渐隐仅在仍有溢出的边缘出现。
- 截图来自实际 App 的 Demo fixtures；[原始截图及来源清单](PracticeScrollScreenshots/manifest.json)。
