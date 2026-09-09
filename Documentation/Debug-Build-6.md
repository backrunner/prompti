# Debug 6 打包与视觉复核

日期：2026-09-10。版本 **0.1.0（build 6）**，应用代码提交为 [`7cc5394`](https://github.com/backrunner/prompti/commit/7cc5394c71c29523d6232c4f4e59f6a6b13c7f27)。API Key 接入调整 `ac6039c` 与城市图标 `7cc5394` 均已推送到 `origin/main`；本记录与截图是后续文档提交，没有改变已打包的应用代码。

## 安装包

本机产物目录：`/Volumes/BRData/CodexBuilds/Prompti-Debug-6-20260910/`。

- `Prompti-0.1.0-debug.6.ipa`：6,640,295 字节，Apple Development 签名，`get-task-allow=true`，bundle ID 为 `com.alkinum.prompti`。已核对用户 iPhone 在描述文件设备列表中。
- SHA-256：`e121af70ecc7b5863ae135e62b91bcb9626194b11a025c1fe8fa160a7e7473b8`。
- `package.json` 保存版本、源码提交、签名与散列；`device-build.log`、`install.json` 和 `installed-app.json` 保存构建与安装证据。签名校验和 IPA ZIP 完整性检查均通过。
- 已覆盖安装到用户 iPhone 17，设备查询确认 **0.1.0 / build 6**。未卸载、清空数据或向真机传入测试参数。自动启动因设备锁屏被系统拒绝，解锁后可以手动打开；这不是一次真机视觉验收。

## 验证

- iPhone Debug 签名构建与模拟器 `build-for-testing` 成功。保留既有 AppIntents 元数据与 iPad 全方向警告。
- 74 个 Swift Testing 单元测试、11 个 suite 全部通过。参数化展开后为 107 次单元测试执行；另有中文浅色和英文深色各 5 次 UI 测试全部通过。
- 两轮 UI 覆盖首页、目的地列表 / 筛选 / 滚动 / 搜索、练习配置 / 生成 / 答案反馈，以及 API Key 预设 / 手填模型。截图中的内容和统计来自现有离线 Demo fixtures，没有使用真实 API Key 调用付费服务。
- 品牌检查、本地化编译提取检查和 `git diff --check` 通过；[远端 Brand contract](https://github.com/backrunner/prompti/actions/runs/34376840728) 通过。
- 目视检查实际 App 的默认字号中文浅色和英文深色：城市地标清晰、模板着色正确，列表及卡片没有裁切或错位，主按钮与文本对比正常；无需修改应用代码。

[打开实际截图与完整覆盖边界](Brand/DestinationArtwork/README.md#实测记录)。保存了 38 张原始 XCTest 截图和来源清单，预览画廊与实际 App 截图分别标注。未覆盖真机视觉、iPad、旧系统、人工 VoiceOver 或真实 Provider 账户联调。

测试原始结果保存在产物目录的 `light.xcresult` / `dark.xcresult`，摘要为 `light-summary.json` / `dark-summary.json`。源码工作区未包含二进制安装包。
