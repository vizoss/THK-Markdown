# SSE 状态与流式正文

THKMDView 不建立网络连接，也不解析服务端的 SSE 事件格式。业务解析事件后，
通过正文和状态 API 更新视图。所有视图 API 在主线程调用。

## 默认状态层

- 默认 `sseEnabled = false`，普通 Markdown 用法不变。
- 开启后，`waiting` / `streaming` 在正文下方左侧显示三个循环变亮的点。
  第一段正文尚未到达时单独显示。圆点不是 Markdown，不参与正文复制。
- 等待期间收到非空分片自动变为输出中；完成、停止、失败必须由业务明确通知。
- `completed` / `stopped` 隐藏状态层；`failed` 保留正文，展示错误文字。
  设置 `onRetry` 后才出现重试按钮，点击只回调业务，不自动清空正文或发起请求。
- 三种终态立即刷新最后尚未提交的分片，避免最后几个字停留在防抖缓冲中。
- `reset()` 清空正文并回到 idle、停止动画；保留配置和业务回调，复用时应重新绑定回调。

### iOS

```swift
markdownView.sseEnabled = true
markdownView.setSSEState(.waiting)
markdownView.appendMarkdownChunk("你好，下面是我的建议：")
markdownView.setSSEState(.completed)
// 连接失败时改用：
markdownView.setSSEState(.failed, errorMessage: "连接中断，已保留收到的内容")
markdownView.onRetry = { [weak self] in self?.retryCurrentMessage() }
```

### Android

```kotlin
markdownView.sseEnabled = true
markdownView.setSSEState(THKSSEState.WAITING)
markdownView.appendMarkdownChunk("你好，下面是我的建议：")
markdownView.setSSEState(THKSSEState.COMPLETED)
// 连接失败时改用：
markdownView.setSSEState(THKSSEState.FAILED, "连接中断，已保留收到的内容")
markdownView.onRetry = { retryCurrentMessage() }
```

## 外部传入状态视图

`sseIndicatorView` 接受 UIView / View，替换等待和输出期间的默认圆点。
传 nil / null 恢复默认；`sseStatusUIEnabled = false` 关闭整个默认状态层。
自定义视图不应已经挂载到其他父容器，不应在多个 THKMDView 间共享同一实例。
iOS 自定义视图需提供 intrinsicContentSize 或高度约束；Android 使用自身测量高度。

```swift
markdownView.sseIndicatorView = customIndicator
markdownView.onSSEIndicatorActivityChanged = { [weak customIndicator] _, active in
    // 根据 active 启停业务动画；不要强捕获宿主控制器。
    customIndicator?.setAnimating(active)
}
```

```kotlin
markdownView.sseIndicatorView = customIndicator
markdownView.onSSEIndicatorActivityChanged = { _, active ->
    customIndicator.setAnimating(active)
}
```

上述 `setAnimating` 是业务自定义方法，不是库内建接口。建议先绑定回调，再开启 SSE。
视图替换、移出窗口、窗口不可见和 reset 会停止动画并通知；重新挂载且仍在输出时恢复。
宿主若只是滚出可见区域但仍保留在窗口中，应主动用 `sseStatusUIEnabled` 控制展示。
`onSSEStateChanged` 提供消息状态变化，与动画当前是否在屏幕上运行是不同概念。

默认圆点通过 `sseIndicatorStyle` 配置：颜色（未指定时跟随正文主题）、直径、间距、周期。
iOS 为 `THKSSEIndicatorStyle(color:diameter:gap:cycleDuration:)`（点、秒），
Android 为 `THKSSEIndicatorStyle(color, diameterDp, gapDp, cycleMs)`（dp、毫秒）。
默认直径 6、间距 5、周期 0.9 秒。iOS 减少动态效果设置下使用静态圆点。

## 解析失败与网络失败分开

未闭合围栏、半行表格等合法流式中间态并不是错误。
对于可恢复的解析异常：先尝试全量解析，仍失败则按主题展示完整原始文本；
通过 `onRenderFailure` 报告 incremental / full 阶段及错误，不包含正文副本。
后续新内容仍尝试正常解析，不自动设置 SSE failed、不停止正在接收的连接。

- Android 捕获解析器的 Exception，不吞掉 OOM 等 JVM Error。
- iOS 在 `MarkdownRendering` 增加带默认实现的 `renderSafely` / `renderFull`，
  旧解析器不必修改；需要报告错误的自定义解析器可覆盖并 throw。
  swift-markdown 原有接口不抛错误；Swift trap、Objective-C 异常及底层原生崩溃
  **不能**被此机制捕获，不能把这套降级视为任意崩溃的保护罩。
- 这是解析边界的处理，不捕获业务回调中的错误或任意 UI 布局错误。

业务仍需通过消息 ID 和尝试 ID 隔离晚到的旧分片，并将状态保存在消息模型中，
使滚动复用后的视图能恢复状态。错误回调中不要无条件再次调用 setMarkdown，避免递归重试。

## 例子工程的 30 组回复

双端读取同一个 `examples/sse/replies.json`，只打包进例子工程，不进入库二进制。
任意文本按顺序选择回复；输入 1～30 可以选题；输入 `/停止` 中止当前模拟。
首段等待 900ms，之后每 80ms 发送一个预先固定的分片，两端正文及分片完全相同。
这是本地 SSE 模拟，不连接 AI 服务，也不是独立的逐字打字机调度器。

第 10、20、30 组会在中途模拟失败；重试清空当前尝试并完整重播同一条回复，不再故意失败。
发送新问题或离开页面会停止当前尝试，已显示内容保留。仅修改主题后返回不会自动续传。
