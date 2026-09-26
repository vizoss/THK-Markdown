# iOS 二进制 CocoaPods 分发

## 当前状态

本目录维护二进制构建配置，不是可直接安装的已发布产物。是否完成归档、pod lint 和发布，请以对应版本的构建记录与实际附件为准。
Maaku 适配器和专属测试已移除；SPM 与 XCFramework 都编译同一份
`Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift`，使用 swift-markdown。

## 打包范围

仅编译 `ios/Sources/THKMDView`，静态链接 swift-markdown / swift-cmark 到动态
THKMDView.framework。解析器通过 implementation-only import 隔离，调用方不需要安装
Markdown 或 Maaku 模块。框架内包含 Mermaid、MathJax HTML/JS 资源和相应许可文件。

不包含 Example、Fixtures、mock、主题设置界面、本地偏好保存或 Tests。
源码使用方走 SPM；不要在同一个 App 中同时安装 THKMDView 的 SPM 和 pod 版本。

## 二进制消费端兼容性检查

2026-09-26 使用 Xcode 自带 Swift 6.3.3 验证 1.0.1 XCFramework：下载和校验通过，但独立 SPM 消费端编译模拟器目标时，`.private.swiftinterface` 中 `THKMDView.THKMDTheme` 等模块限定名被解析为同名类的成员，导致导入失败。此前 CocoaPods lint 通过不能代替跨工具链 Swift 消费端验证。

当前构建脚本保留源码类型写法，并修正编译器生成的同名模块限定前缀（仅处理已声明的顶层类型，不改类名、ABI、字符串或注释）。打包前强制检查每个架构的 public/private 文本接口，并编译、链接独立 Swift 消费端，避免同版本编译器的 `.swiftmodule` 缓存掩盖错误。

根目录 SPM 仍采用源码接入。此修复需要通过新版本二进制发布生效，不要覆盖已发布 ZIP 或移动已有 1.0.1 / 1.0.2 tag。

## 本地构建（维护者执行）

需要 Xcode 26+ / Swift 6.2+、XcodeGen、CocoaPods。选择合适的 Xcode 工具链后，在仓库根目录执行：

```sh
bash ios/scripts/build-xcframework.sh
```

脚本将：

1. 检查二进制项目的解析器 revision 与 `ios/Package.resolved` 一致。
2. 生成临时 Xcode 工程，分别归档真机 arm64 与模拟器 arm64/x86_64。
3. 检查框架没有外部 Markdown/cmark 动态依赖、公开接口没有泄露解析器模块、Mermaid / MathJax 资源齐全；强制验证三种架构的文本接口和 Swift 消费端链接。
4. 创建 XCFramework，携带 SDK 和第三方许可证。
5. 在本地产物目录执行 CocoaPods 集成 lint（不启动示例 App）。
6. 生成 `ios/Binary/build-*/THKMDView-<版本>.zip`、SHA256SUMS 和 podspec。

产物保留在独立目录，不覆盖旧包。请保留构建日志及实际 Xcode 版本。
Swift 模块稳定性不保证新工具链产物可被任意旧 Xcode 导入，发布前需验证消费端最低工具链。

## 本地 pod 验证

脚本成功后可在宿主 Podfile 中指向产物目录：

```ruby
pod 'THKMDView', :path => '/绝对路径/ios/Binary/build-XXXXXX/release'
```

该目录必须同时存在 podspec 与 XCFramework。原先指向 Git 源码的 pod 接入方式不再构建 SDK。
共享 P0/P1/P2/P3 数据仍供源码示例和测试使用；二进制宿主需要另外接入验收界面，不能将源码测试通过
等同于二进制集成或 UI 验收通过。

## Tag 自动发布

推送 `x.y.z` tag（无 `v` 前缀）会自动构建并上传 `THKMDView-<版本>-binary` Actions 附件。成功后，`ios-release.yml` 自动校验构建来源、tag 提交和 ZIP 校验和，再创建对应 GitHub Release，上传 ZIP、SHA256SUMS 和 podspec。不会发布到 CocoaPods trunk，也不会覆盖已有 Release。

普通分支推送不触发构建；手动构建分支只生成候选包，不发布 Release。通过后再创建版本 tag。Android VERSION_NAME 和 podspec 必须一致，tag 构建还会检查两者与 tag 一致。

如需补发历史成功的 tag 构建，可手动运行 `iOS – publish verified binary release`，填写该构建的 `build_run_id`。分支候选构建、失败构建、tag 已移动的构建都会被拒绝。发布脚本先创建 draft 并上传完整附件，再公开 Release；如果上传失败留下草稿，应由维护者核对后处理，不覆盖已发布文件。

维护者应选择未占用的版本号。安装地址以根目录 podspec 的 `s.source` 为准；发布后需验证匿名下载和远端 pod 集成。

```ruby
# 发布相应资产后才可使用；这里不是已可用版本的承诺。
pod 'THKMDView', :podspec => 'https://raw.githubusercontent.com/vizoss/THK-Markdown/<版本>/THKMDView.podspec'
```

共享数据里的 `ios-binary` 表示待验收的二进制接入目标，不表示已经验收。
历史文档中 Maaku、旧 pod lint 的记录仅描述旧版本，不能用于证明当前二进制可用。
