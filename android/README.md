# THKMDView · Android

Android 原生 Markdown 库，包名 `com.thk.mdview`，最低 API 21。

业务安装、公开 API、主题、点击事件、图片缓存和生命周期以 [主 README](../README.md) 为准。本页只维护 Android 构建与开发说明。

## 工程

- [thkmdview](thkmdview/)：发布为 AAR 的库，包含 Mermaid / MathJax assets。
- [sample](sample/)：示例应用，不随库发布。
- [库构建配置](thkmdview/build.gradle.kts)：插件、依赖和 Maven 发布配置。
- [共享用例](../ios/Fixtures/data/)：双端使用同一份 P0～P3 数据。
- [模拟回复](../examples/sse/replies.json)：双端 SSE Chat 的 30 组回复。

使用 JDK 17 和仓库 Gradle Wrapper。当前 AGP 8.5.2、Kotlin 1.9.24、compileSdk 34。首次构建需要下载依赖。

## 构建与测试

以下命令从仓库根目录开始：

```sh
cd android
./gradlew :thkmdview:assembleRelease
./gradlew :thkmdview:testDebugUnitTest
./gradlew :sample:assembleDebug
```

AAR 位于 `thkmdview/build/outputs/aar/`；示例 APK 位于 `sample/build/outputs/apk/debug/`。运行示例可用 Android Studio 打开本目录，选择 sample 和设备。

单元测试使用 Robolectric，无需启动模拟器；覆盖解析、分片、复用、主题、图片、表格、公式请求及 SSE 状态等。真实 WebView 绘制、滚动性能和视觉效果仍需要设备验收。测试目录见 [src/test](thkmdview/src/test/)。

## 示例入口

`MainActivity` 提供四个入口：

| 页面 | 职责 |
| --- | --- |
| ShowCaseActivity | P0～P3 用例、全文/播放/暂停/单步、验收要求 |
| SSEChatActivity | 30 组本地模拟回复、等待/输出/失败/重试 |
| WeeklyListActivity | 50 篇周刊列表与 Markdown 详情 |
| ThemeSettingsActivity | 默认/鲜明预设、颜色与字号编辑、本地保存 |

SSE Chat 不是在线 AI 服务；输入 1～30 选题，10/20/30 演示失败与重试，输入 `/停止` 中止。主题持久化和消息模型属于示例业务，不属于库。

## 集成注意

- THKMDView 是 LinearLayout，不是 TextView；使用 wrap_content 高度，字体/颜色通过主题设置。
- 所有视图操作在主线程；流式传入新增文本，而不是重复累计全文。
- reset 清理渲染任务，不替业务取消网络请求；复用前重新绑定业务状态与回调。
- 链接回调返回 true 表示业务处理，但 false 不会自动打开浏览器。
- 图片完成后可能改变高度；生产环境建议注入共享的业务图片加载器。
- 宿主负责 INTERNET 权限、HTTPS 策略、URL 校验与账号缓存隔离。
- 独立复制 AAR 不会自动安装传递依赖，优先使用模块或带 POM 的 Maven 包。

完整示例与双端差异见 [业务指南](../README.md#业务接入检查清单)。

## 发布

推送 `x.y.z` tag（无 `v` 前缀）后自动测试并发布到公开的 `maven-repo` 分支，坐标为 `com.thk.mdview:thkmdview:<tag>`。tag 必须与 Android 和 iOS 版本配置一致；普通分支推送不发布。手动构建填写已有 `release_tag`，可补发历史版本。已发布版本目录不可覆盖，后续版本保留历史产物及完整 Maven 元数据。

依赖地址为 `https://raw.githubusercontent.com/vizoss/THK-Markdown/maven-repo/`，下载无需账号或 Token。配置见 [安装依赖](../README.md#安装依赖)；维护者流水线见 [android-publish.yml](../.github/workflows/android-publish.yml)。只有 CI 推送分支使用自动提供的 GITHUB_TOKEN，不需要用户创建个人 Token。

## 专题

- [SSE 接入](../docs/sse.md)
- [P0](../docs/P0.zh-CN.md) / [P1](../docs/P1.zh-CN.md) / [P2](../docs/P2.zh-CN.md) / [P3](../docs/P3.zh-CN.md)
- [性能与增量解析](../docs/performance-review.md)

历史验收文档只描述对应提交的结果，不代表当前版本已完成全部设备验收。
