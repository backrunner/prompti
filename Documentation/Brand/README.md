# Prompti 品牌图标

新版以定制的 **P + 对话气泡** 为主标识。圆润的字腹表达交流，向下延伸的气泡尾部让它区别于普通字体 P；保持粗实轮廓和开放内孔，使通知、搜索、主屏幕和商店列表共用同一个符号。旅行主题由产品文案与场景视觉延展。

全部 UI 的实施约束见 [品牌与 UI 开发规范](../../.agents/13-brand-and-ui-guidelines.md)，逐页调整与验证见 [UI 验收记录](UI-Review.md)。App 内通过 `PromptiBrandMark` / `PromptiWordmark` 使用同源的模板 PDF，不显示完整图标边框。

实际 App 的默认字号浅深色画面见 [UI 截图画廊](UI-Review.html) 和 [对照图](UI-Review.png)，与下方的图标概念展示分别保存。

打开 [Preview.html](Preview.html) 或 [预览图](Preview.png) 查看商店排版、六种系统外观、小尺寸和单色品牌组合。商店内容是排版示意，没有添加虚构评分、排名或评价。

## 资源

| 资源 | 用途 |
| --- | --- |
| [AppIcon.icon](../../Prompti/AppIcon.icon) | 工程使用的分层图标；系统提供圆角、光效、透明和着色外观 |
| [AppIcon.appiconset](../../Prompti/Assets.xcassets/AppIcon.appiconset) | 三张 1024 × 1024、sRGB、RGB 无透明通道的平面图稿 |
| [Prompti-Mark.svg](Prompti-Mark.svg) | 深绿色单色主标，透明背景 |
| [Prompti-Mark-Reversed.svg](Prompti-Mark-Reversed.svg) | 深色背景使用的奶白反白标 |
| [Prompti-Mark-Mono.svg](Prompti-Mark-Mono.svg) | `currentColor` 版本，适合内联 SVG |
| [BrandMark.imageset](../../Prompti/Assets.xcassets/BrandMark.imageset) | App 内使用的矢量模板 PDF，与主图标同源 |
| [Previews](Previews) | Icon Composer 导出的系统外观，仅供展示，不是上传用的方形图稿 |

Xcode 优先采用与 `ASSETCATALOG_COMPILER_APPICON_NAME` 同名的 `AppIcon.icon`，并为旧系统自动生成兼容图标。工程保留的 asset catalog 不会覆盖 Composer 生成的旧系统图标；其中 PNG 可独立用于平面物料或不采用 Composer 的构建。

## 品牌使用

- 保持标识形状、比例和方向一致，不添加飞机、航线、边框、文字或额外气泡。
- 主标色：深绿 `#103F38`；反白：奶白 `#F7FFEA`；深色图标前景：薄荷 `#A3F2CE`。原生图标底色为翡翠绿，最终颜色和明暗由系统材质参与渲染。
- 标志周围至少保留标志宽度 10% 的净空；图标主体位于 1024 方形画布中央区域，勿再放大或预裁圆角。
- 独立品牌标志建议至少 16 px 宽。需要表达产品名时将 Prompti 排在标志旁；预览中的系统字体组合仅示意排版，不是独立字体授权交付。
- 主图标不放产品全名或宣传文案；商店标题和副标题承担文字信息。
- 图标的吸引力和商店转化仍需上线后的用户验证；这次验证覆盖可辨识度、外观一致性、资源格式和构建。

## 重新生成

在仓库根目录运行：

```sh
swift Tools/GenerateAppIcon.swift
xcodegen generate
```

生成器是轮廓与配色的唯一源头，同时生成 PNG、SVG、asset catalog 配置和 Composer 文档。修改生成器后同步重新生成文件。

系统外观预览可由 Xcode 自带的 `ictool` 重新导出（将路径替换为本机 Xcode；Xcode 27 支持指定 26 的视觉版本）：

```sh
ICON_TOOL="/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
for appearance in Default Dark TintedLight TintedDark ClearLight ClearDark; do
  "$ICON_TOOL" Prompti/AppIcon.icon --export-image \
    --output-file "Documentation/Brand/Previews/$appearance.png" \
    --platform iOS --rendition "$appearance" --width 512 --height 512 --scale 1 \
    --design-generation 26 --tint-color 0.44 --tint-strength 0.65
done
```

依据：[Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。

## 本轮验证（2026-09-07）

- Xcode 27 / iPhone 17 Pro（iOS 27 模拟器）完整 App 构建成功；`actool` 已将 `AppIcon.icon` 编译为主图标，最低部署版本仍为 iOS 18。
- 使用 Icon Composer 的 iOS 26 渲染检查默认、深色、浅深着色和浅深透明外观，并检查 20、29、40、60、80、120pt 的显示效果。
- 三张平面 PNG 均为 1024 × 1024、RGB 无透明通道，并包含 sRGB 标记；着色图稿是灰度；三个品牌 SVG 与原生图标使用相同路径。
- App 已安装到模拟器，但主屏幕截图自动化停在系统 `testmanagerd` 启动，未完成实际图标所在页面的截图。因此预览页展示的是 Icon Composer 输出与商店排版示意；尚未完成真机及旧系统运行时验收。
