# 品牌与 UI 开发规范

状态：实施基线 · 2026-09-07

适用：全部 SwiftUI 页面、组件、App Icon、文档和商店物料。

本规范承接 [品牌图标](../Documentation/Brand/README.md)，取代 `02-user-experience.md` 中早期的飞机主视觉、邮戳边框、天空蓝/黄色/珊瑚色装饰方向。交互流程和业务规则仍按各模块规范执行。

## 1. 品牌表达

Prompti 帮助用户练习旅行中常用的对话。视觉气质是清晰、温暖、轻快、可信。中文主句为 **“出发前，练好旅行常用语。”**；英文主句保留 **“Say hello to the world.”**，中英文分别按各自的用语习惯撰写。

- 品牌核心是定制的 **P + 对话气泡**，使用翡翠绿、薄荷绿、奶白与深绿。它同时是 App Icon 的主体和独立 Logo。
- 旅行由城市名称、地标、场景和地图定位符表达；飞机不承担 Logo、欢迎页主视觉或通用练习进度的职责。
- 主视觉使用少量对话元素。正文区域保持安静；不要给每张卡片放 Logo、装饰气泡、彩色渐变、轨迹、邮戳虚线、发光或阴影。
- 文案表达可观察的结果和下一步行动，不把用户“答错”包装成惩罚，不承诺无法验证的掌握程度或精确生成百分比。
- 中文市场与端内文案统一按 [文案规范与市场文案](../Documentation/Brand/Copywriting.md) 执行。说明具体场景、功能和操作，不用旅行隐喻替代功能名称；反馈依据实际作答结果，不把练习完成等同于语言掌握。

## 2. 标识与唯一来源

| 场景 | 必须使用 |
| --- | --- |
| iOS 主图标 | `Prompti/AppIcon.icon`，由系统提供圆角与材质 |
| App 内品牌组合 | `PromptiWordmark`；仅符号用 `PromptiBrandMark` |
| 单色品牌物料 | `Documentation/Brand/Prompti-Mark*.svg` |
| 内置目的地 | `DestinationArtwork`，使用 `Tools/DestinationArtwork` 的地标 / 代表物 SVG，由 `Tools/DrawDestinationArtwork.py` 同步发布 |
| 功能图标 | SF Symbols；通用徽标用 `PromptiSymbolBadge` |

P 对话品牌标识由 `Tools/GenerateAppIcon.swift` 中同一条轮廓生成。App 内使用保留矢量的模板 PDF `BrandMark.imageset`，由前景色着色。不要复写路径、拼接系统气泡与字体 P，也不要在 App 内把完整 App Icon 当作 Logo。

保持方向与长宽比；不挤压、不旋转 Logo，不给它增加飞机或额外气泡。独立 Logo 至少保留自身宽度 10% 的净空，推荐最小可见宽度 16px。欢迎页和设置页可展示完整字标；其他页面以内容为主。

内置目的地不得再复用通用楼房、交通工具等 SF Symbols。每个稳定 ID 对应一幅独立的当地地标或知名代表物 SVG，图稿与资源清单见 [目的地图稿](../Documentation/Brand/DestinationArtwork/Gallery.html)。2026-09-10 起使用经审阅的 `gpt-image-2.5-flare` medium 线稿，清理背景、统一留白后转为真实矢量路径；源 PNG、提示词、生成 ID 和处理脚本按 [目的地图稿说明](../Documentation/Brand/DestinationArtwork/README.md) 保留，不能只替换导出的 SVG，也不能把生成图称为手工原创或实际 App 截图。原生资源保留矢量并按语义色着色；自定义地点使用中性定位符，不虚构当地地标。目的地绘图源与 P 品牌标识源分别维护，不能互相替代。

## 3. 语义配色

唯一运行时定义是 `Prompti/DesignSystem/PromptiTheme.swift`。`AccentColor.colorset` 与 `promptAction` 的浅/深色值同步，用于原生导航和控件。以下数值由自动检查核验，页面不得重复硬编码。

| 角色 | 浅色 | 深色 | 使用位置 |
| --- | --- | --- | --- |
| `promptCanvas` | `#F5F6F0` | `#101C18` | 全页面与底部操作遮罩 |
| `promptSurface` | `#FFFFFF` | `#1A2A24` | 卡片、表单行、内容面 |
| `promptSurfaceRaised` | `#EAF0E6` | `#263B32` | 输入区、图标徽标、次级分组 |
| `promptHero` | `#E3EDDE` | `#203B2E` | 欢迎、目的地、练习完成主视觉 |
| `promptText` | `#173D33` | `#EDF4EB` | 品牌正文与标题 |
| `promptMuted` | `#52675B` | `#B2C5B7` | 自定义界面的次要文案 |
| `promptAction` | `#08765D` | `#A3F2CE` | 主按钮、实底选择项 |
| `promptOnAction` | `#F7FFEA` | `#103F38` | 主操作表面的文字与图标 |
| `promptSelection` | `#DFEEE3` | `#264538` | 轻量选中背景 |
| `promptSuccess` / Surface | `#176C47` / `#E5F1E6` | `#A3F2CE` / `#213C2C` | 明确成功、正确 |
| `promptWarning` / Surface | `#815710` / `#F8EFD8` | `#E9C67D` / `#3C3221` | 重试建议、费用提示、隔离状态 |
| `promptError` / Surface | `#AE392F` / `#FAE9E4` | `#FFAEA0` / `#442B27` | 错误答案、失败、正在录音的停止操作 |

**必须成对使用前景和背景。** 深色主按钮是薄荷底配深绿文字，不能继续配白字。浅色次要文字不能用低对比的薄荷绿或天空蓝。

成功、错误、警告都必须同时提供图标或文字。答题选项用 `PromptiAnswerStyle`，其选中、正确、错误状态保持布局稳定，并响应 Differentiate Without Color；搭配 `PromptiAnswerButtonStyle`，提交后禁用改答但不降低答案的阅读对比。提示条用 `InlineNotice(tone:)`，不传装饰色。未评分和跳过是中性状态。

## 4. 页面与组件

- 大面积背景使用 `PromptiBackground`，不把图标的饱和背景铺满整个阅读界面。
- 内容面使用 `promptiSurface()`，采用不透明颜色和细边线，不使用玻璃、模糊和投影。品牌主视觉使用 `promptiHeroSurface()`。
- 主操作使用 `PrimaryActionButtonStyle`：至少 52pt 高，稳定实底、明确对比；一屏同一决策层级只突出一个主操作。
- 次操作使用 `SecondaryActionButtonStyle`；导航、辅助音频操作和紧凑浮动按钮使用 `CompactGlassButtonStyle` / `GlassIconButtonStyle`。只有这些位置在系统支持且未降低透明度时使用原生玻璃；降级表面必须不透明。
- 录音按钮使用 `RecordingActionButtonStyle`，等待、录音与停止文字不能只靠颜色区分。
- 统一输入区使用 `PromptiCredentialFieldModifier`；安全字段继续用 `SecureField`。口语转写使用 `TextEditor`，允许拒绝麦克风权限时手动编辑，并保留焦点与提交能力。原生 `Form`、`Picker`、`Menu`、确认对话框保留系统行为。
- 空状态使用 `PromptiEmptyState`，可恢复故障使用 `PromptiRecoveryView`。不要用新的插画或品牌符号替代状态本身的含义。
- 主流程底部操作继续通过 safe-area inset 固定，并用 `PromptiActionScrim` 阻止正文穿透；不要让操作覆盖最后一项内容。
- 全部自有纵向滚动内容使用 `PromptiScrollView`；原生 `Form` 使用 `promptiScrollEdges()`。上方还有内容时才显示顶部渐隐，下方还能继续滚动时才显示底部渐隐；到达边界、内容不满一屏或筛选缩短列表时及时移除对应遮罩。遮罩不截获手势，保留导航、底部安全区和键盘适配。
- 目的地语言筛选与支持语言使用当前界面语言名称；支持语言以可换行的小标签展示。筛选项未选中时不保留勾选占位，选中后自然变宽，使用一次 0.26 秒平滑过渡；降低动态效果时直接切换。
- 场景选项按名称所需宽度排列，空间不足时整项移到下一行；每项的名称保持单行，图标、文字和勾选垂直居中。内置场景完整显示，不预留第二行高度；超过整屏可用宽度的自定义场景保留字号并可横向查看全文。

## 5. 字阶、间距和动效

- Hero、内容标题、分区标题分别使用 `PromptiTypography.hero / title / section`；正文使用系统 `.body` / `.subheadline`，说明使用 `.footnote` / `.caption`。圆润标题与 Logo 呼应，不使用装饰字体。自定义文字使用 `promptMuted` 作为次级前景，避免继承的品牌前景被 `.secondary` 再次降低透明度。
- 屏幕主体水平留白使用 `PromptiSpacing.page`（20pt）；欢迎、引导与独立表单可使用 24pt。8/12pt 用于关联元素，24pt 用于分区。避免用大量独立常数制造新层级。
- 圆角保持 `PromptiRadius` 的 14 / 20 / 24 / 32pt，分别用于紧凑、操作、内容和主视觉；系统胶囊、分段控件保持原生。
- 图标通常为 semibold，功能按钮触控区至少 44pt。统计数字使用等宽数字，不把正文缩小来塞满控件。
- 仅在状态转换时使用短促淡入/位移；Logo 保持静止。不得增加无限旋转、呼吸光效或与实际进度无关的伪百分比。Reduce Motion 使用静态或淡入形式。
- 一组题全部答对时，完成页允许播放一次 1.8 秒的品牌色礼花；不循环、不拦截操作，离开页面或进入后台立即停止。降低动态效果时只展示静态结果和全对徽标。跳过、未计分、已反馈题目或未补齐题量的 100% 正确率不触发全对庆祝。
- 默认字号与常规布局是当前验收范围；已有无障碍、VoiceOver、降低透明度和颜色区分实现必须保留。

## 6. 页面覆盖清单

| 页面或状态 | 本轮统一规则 |
| --- | --- |
| 欢迎 / 引导 | P 字标、问候主视觉、绿色语言选中态、一致按钮和卡片 |
| 今日 | 品牌抬头、暖绿目的地卡、统一地标徽标和统计块 |
| 目的地列表 / 筛选 / 自定义 | 地标表达内容，去邮戳虚线和黄色徽标，统一选择与输入区 |
| 练习配置 / 自定义场景 | 共用选择状态、主操作、字段与错误提示 |
| 生成 / 部分成功 / 失败 | 对话阶段图形、真实阶段文案、恢复操作与语义错误色 |
| 完形 / 选择 / 口语 | 共用答案外观，正文对比、录音与播放按钮一致 |
| 答题反馈 / 完成 | 正确、建议、未评分含义独立；圆形结果、短标题、非零统计；全对时一次礼花，保存提示紧邻完成按钮 |
| 复习 / 筛选 / 隔离 | 不透明卡片、中性空状态、警告语义与明确操作 |
| 进度 / 有数据与空数据 | 单一绿色数据系列，中性说明、统一统计块 |
| 设置 / Provider / 授权码 | 品牌身份、原生表单、统一输入与按钮；保持账户授权流程 |
| 学习数据故障 / 会话不存在 | 共用恢复组件及明确下一步 |

此表描述实现要求；实测结果和截图另见 [UI 验收记录](../Documentation/Brand/UI-Review.md)。

## 7. 开发流程和门槛

1. 修改共享 token/组件，再修改需要变化的页面，不复制样式。
2. 标识变化运行 `swift Tools/GenerateAppIcon.swift`；新增源文件运行 `xcodegen generate`。
3. 运行 `python3 Tools/CheckBrand.py`。检查覆盖旧配色与品牌飞机残留、页面内硬编码颜色、Logo 资源来源、主色配对和文本对比；通过不等于视觉验收完成。仓库的 `Brand contract` GitHub Actions 工作流在相关 PR 中执行同一检查。
4. 构建并运行相关已有测试。修改选择/反馈组件时覆盖完形、选择、口语、提交后状态、取消与完成；不得改变计分和持久化语义。
5. 在一台 iPhone 模拟器中检查默认字号的浅深色主流程，检查中文与英文文案。截图必须来自实际 App，并记录系统版本、模式和覆盖边界。
6. PR 说明品牌规范的变更及验证结果；有意偏离规范时写明原因和影响，不把常规实现选择变成额外审批流程。

## 8. 本地化实现约定

- 界面语言与学习 / 讲解语言独立。当前 UI 覆盖英文、简体中文；新用户的讲解语言根据系统首选语言选择中文或英文，已保存的选择不变。
- 静态文案和带变量的整句使用可提取的 `Text("…")`、`String(localized: "…")`；不要先把变量插入普通 `String`，再转为 `LocalizedStringKey`。封装控件接收的动态标题需要显式本地化，并在 String Catalog 中维护对应键。
- 城市、国家、地标、内置场景与历史题目的显示使用 `CatalogLocalization`。按稳定 ID 识别内置内容；自定义城市和用户场景作为原文显示。不能把翻译写入持久化字段、改变筛选 ID 或模型生成上下文。
- `Localizable.xcstrings` 维护普通 UI；`InfoPlist.xcstrings` 维护麦克风、语音识别等系统权限文案。动态目录键标为 manual；品牌名、模型 ID 和纯数字模板可标记不翻译。
- 数量整句配置英文 one / other 与中文翻译。格式参数必须保留类型与数量；中文需要调整顺序时使用位置参数。
- 执行 `python3 Tools/CheckLocalization.py`；以 `SWIFT_EMIT_LOC_STRINGS=YES` 构建后，再带 `--stringsdata <DerivedData>` 检查编译器提取的文案。它覆盖目录、插值和翻译完整性，不能替代中文 / 英文默认字号的实际浅深色检查。
