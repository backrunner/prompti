# 城市线框图标

日期：2026-09-10。

65 个内置城市使用更精细的地标 / 代表物线稿，保留圆润轮廓、单色表达和开放留白。App 继续通过 `DestinationArtwork` 使用可着色矢量模板，浅色为翡翠绿、深色为薄荷绿；没有白色底图、额外装饰背景或新增界面文案。

- [交互对照画廊](Gallery.html)：全部 65 个城市，旧版 / 新版、浅色 / 深色和 40px / 64px 预览，可搜索。
- [图稿 1](Review/sheet-1.png)、[图稿 2](Review/sheet-2.png)、[图稿 3](Review/sheet-3.png)、[图稿 4](Review/sheet-4.png)：全部矢量图的静态审阅页。它们是资源预览，不是实际 App 截图。
- [资源与来源清单](manifest.json)：稳定 ID、地标名称、模型、质量、prediction ID、原始 PNG、输入和 SVG 的路径及 SHA-256。

## 生成与源文件

使用本机 `replicate` CLI 0.1.1，模型为 `openai/gpt-image-2.5-flare`。先生成东京塔的 low / medium 两张对照，再以 medium 生成 65 个独立城市图；共 67 张输出，没有使用 high 档。

统一输入为 `aspect_ratio=1:1`、`background=opaque`、`output_format=png`、`number_of_images=1`。提示词要求单个可识别地标、黑色圆头线条、白底、选取关键结构细节，避免密集排线、文字标签、阴影和渐变。每城完整提示词保存在清单链接的 `input.json` 中。

- [生成脚本](../../../Tools/GenerateDestinationArtwork.py)：默认只准备输入，只有 `--generate` 才创建收费预测；可恢复已提交任务，已完成的输出不会重复生成。
- [原始图片与记录](../../../output/imagegen/destinations/)：`pilot` 保存两档对照，`sources` 保存全部城市的原始输出、输入、prediction 和下载清单，`before` 保存此次修改前的 SVG 供对照。
- [转换脚本](../../../Tools/PrepareDestinationArtwork.py)：Pillow 灰度阈值清理背景，归一到 1024px 画布及 896px 主体范围，轻度中值滤波；potrace 1.16 追踪轮廓并去除孤立噪点，最终映射到 64 × 64。轮廓之间的留白和背景都透明，SVG 不嵌入 PNG 或字体。
- [可编辑矢量源](../../../Tools/DestinationArtwork/)：65 份真实路径及来源清单。
- [发布脚本](../../../Tools/DrawDestinationArtwork.py)：离线同步矢量源、asset catalog 和画廊；文件内保留最初的几何稿作为历史基线。

Replicate API 的模型信息未公开可固定的版本 schema；输入字段从模型公开 API 页面核对，正式请求前执行 CLI dry run。服务返回的版本为 `hidden`，已如实记录。保存 PNG 与散列用于确定性重建；再次调用模型不保证相同图像。

离线重建：

```sh
# 首次需在工具环境安装 Pillow，以及本机 potrace 1.16。
python3 Tools/PrepareDestinationArtwork.py
python3 Tools/DrawDestinationArtwork.py
python3 Tools/CheckBrand.py
```

这批图是 AI 生成后经清理和矢量化的线稿，不称为手工原创。P 对话品牌标识仍以 `Tools/GenerateAppIcon.swift` 为唯一来源。目录 ID、目的地事实、练习统计、安全审核、Provider 协议和持久化语义均未因本次资源更新而改变。

## 实测记录

环境：Xcode 27.0 beta（27A5228h）、iPhone 17e 模拟器（Prompti Brand Final）、iOS 27.0，系统默认字号 `large`。本轮检查仅针对图标资源，不扩大到工作区已有的模型接入修改。

- 65 幅矢量图已按四张审阅页逐张检查，额外查看了首批九城的旧版 / 新版和 40px 缩略图；地标轮廓、留白和主要结构可辨。
- 浏览器中确认画廊包含全部 65 个城市，搜索、新旧切换和浅深色切换正常；实际计算色值分别为 `#08765D` / `#A3F2CE`，图形不额外描边。画廊是资源预览，不等于 App 实测。
- `python3 Tools/CheckBrand.py` 通过；65 个源 PNG 的 SHA-256、矢量源和发布资源逐项一致，SVG 仅包含路径、分组和标题，没有嵌入位图或字体。
- 模拟器 `xcodebuild build-for-testing` 成功；构建结果位于 `/tmp/prompti-city-artwork-build`。
- `python3 Tools/CheckLocalization.py --stringsdata /tmp/prompti-city-artwork-build` 通过：629 个目录条目、185 个动态标签、297 处编译器提取结果。
- `git diff --check` 通过。

**未完成：现有测试执行与实际 App 的浅深色截图。** 已选择 `DestinationPresentationTests` 的资源覆盖 / 滚动边界两项测试，以及首页、目的地列表和筛选三项现有 UI 测试。中文浅色首次运行停在测试服务启动；重启该模拟器后重跑仍未开始用例，均主动中断，不能记为通过。随后直接 `simctl launch` 也在 50 秒后超时。本机采样显示 CPU 无空闲、15GB 内存已用、系统平均负载约 280；本轮没有获得新版实际 App 截图，英文深色运行也未完成。

测试服务恢复后，应补跑上述测试并检查默认字号的中文 / 英文、浅色 / 深色界面，再补入实际截图。既有无障碍实现保持不变；本轮也未进行真机、iPad、旧系统或人工 VoiceOver 验收，不把非常规超大字号列为门槛。机器可读记录见 [validation.json](validation.json)。
