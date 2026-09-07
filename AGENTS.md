# Prompti 开发约定

实现前阅读 [.agents/README.md](.agents/README.md) 中与任务相关的产品、交互和工程基线。

## 品牌与界面

- 所有 UI 工作必须遵循 [.agents/13-brand-and-ui-guidelines.md](.agents/13-brand-and-ui-guidelines.md)。这份规范取代早期的飞机品牌标识、邮戳边框和多彩装饰方向。
- P 对话标识唯一源头是 `Tools/GenerateAppIcon.swift`。App 内使用 `PromptiBrandMark` / `PromptiWordmark`，不能临时使用字体 P、SF Symbols、AppIcon 位图或另一条路径替代。
- 复用 `PromptiTheme.swift` 的语义颜色、间距、字阶与按钮样式；功能页面不能声明 RGB/hex 颜色或复制品牌路径。主操作必须成对使用 `promptAction` / `promptOnAction`。
- 内容卡片使用 `promptiSurface()`，主视觉使用 `promptiHeroSurface()`；系统玻璃仅用于导航与紧凑浮动控件。错误、警告、成功颜色只表达相应状态。
- 品牌更新需要同步生成资源、说明文档和视觉验收记录，不能只修改导出的 PNG/PDF/SVG。
- UI 改动执行 `python3 Tools/CheckBrand.py`、构建和相关现有测试，至少检查一台 iPhone 的默认字号浅/深色。保留现有无障碍适配；按当前用户约定，不把非常规超大字号作为验收门槛。
- 记录实测范围和未完成项；概念图、Icon Composer 输出不能写成实际 App 截图。

## 工作边界

- 保留工作区已有修改，不覆盖与任务无关的用户改动。
- 视觉调整不改变练习统计、安全审核、Provider 协议或持久化语义；确需变动时同步相应领域文档和验证。
- 所有用户可见新文案加入 String Catalog，至少提供英文和简体中文；品牌名与装饰性的多语言问候除外。
