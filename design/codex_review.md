1. **致命｜AppContext.swift:37-40、Coordinator.swift:77-98、Inserter.swift:19-43**  
   问题：只保存 bundle ID 和选中文字，没有保存目标进程、focused AX element 或选区范围。识别/DeepSeek 返回期间用户切换窗口后，`⌘V` 会写入当前前台应用，甚至覆盖另一处选区。  
   修复：捕获目标 PID、focused `AXUIElement` 和 selected range；写入前再次验证目标仍一致。优先通过 Accessibility 写回原元素；目标失效时只复制到剪贴板并提示“目标已切换，结果已复制”，不要盲发 `⌘V`。

2. **致命｜HotkeyMonitor.swift:35-38、52-68，Coordinator.swift:39-65**  
   问题：CGEventTap callback 内同步执行 AX 查询、`AVAudioEngine.start/stop`、数组复制和 HUD 操作，可能触发 tap timeout。tap 被禁用后代码只重新 enable，却保留 `.holding/.locked` 状态；如果 release 事件丢失，会一直录音。  
   修复：callback 只提取事件并投递到串行状态队列，立即返回；delegate 操作异步到 MainActor。收到 `.tapDisabledByTimeout/.tapDisabledByUserInput` 时先强制取消录音、重置状态，再重新 enable。

3. **致命｜Coordinator.swift:39-106**  
   问题：松键后 hotkey 已回到 idle，但 ASR/DeepSeek Task 仍在运行，用户可以立即开始下一次录音。多个任务会乱序写入，旧任务还会覆盖新任务的 HUD、剪贴板和历史状态。  
   修复：增加明确的 `.idle/.recording/.processing` 状态和 session UUID；处理中禁止再次开始，或显式取消上一任务。所有异步完成、HUD 更新、写入前都校验 session UUID。

4. **高｜AudioRecorder.swift:19-62**  
   问题：tap 安装后 `engine.start()` 如果抛错，tap 没有移除，`isRunning` 仍为 false；下一次 `installTap` 很可能触发 “tap already installed” 异常。默认输入设备切换时也没有处理 configuration change，旧 format/converter 会继续使用，可能无声、转换失败或触发格式断言。  
   修复：用 `do/catch` 包住 prepare/start，失败时执行 `removeTap`、`stop`、`reset`。监听 `AVAudioEngineConfigurationChange`；录音中设备变化就取消本次录音并重建 engine/tap。安装前验证 `sampleRate > 0`、`channelCount > 0`。

5. **高｜Inserter.swift:7-31**  
   问题：固定 0.6 秒后恢复剪贴板没有 paste 完成确认。慢应用可能在恢复后才读取，最终粘贴的是旧内容；两次 insert 重叠时，第二次会把第一次的临时文本当成“原剪贴板”，导致真正的原内容永久丢失。  
   修复：把粘贴操作串行化，维护单一 paste transaction 和 generation token，只保存一次原剪贴板；新 transaction 必须取消旧恢复任务。首选 AX 直接写入；`⌘V` fallback 才使用延迟恢复，并确保只有最新 token 能恢复。

6. **高｜main.swift:23-35、Coordinator.swift:95-104、Inserter.swift:35-43**  
   问题：权限未齐时仍允许完整录音流程。Accessibility/事件注入权限不足时，`CGEvent.post` 可能不起作用，但代码仍写历史并显示“已写入”。  
   修复：开始录音前检查 microphone 和 Input Monitoring；写入前检查 `AXIsProcessTrusted()`/post-event 权限。让 `Inserter.insert` 返回明确结果，只有确认具备权限且目标有效时才记录“已写入”，否则提示开启权限并保留结果到剪贴板。

7. **高｜Settings.swift:31-43、Cleaner.swift:39-50、Coordinator.swift:69-87**  
   问题：`Settings` 是非 actor 隔离的 `ObservableObject`，UI 在主线程修改属性，同时非隔离 `Task`/Cleaner 读取 model、apiKey、dictionary，存在 Swift 数据竞争，用户录音时改设置可能读到不一致状态。  
   修复：将 `Settings` 和 Coordinator UI 状态标记为 `@MainActor`；启动任务前一次性快照 `llmEnabled/model/apiKey/dictionary`，以不可变参数传给 Cleaner，后台任务不要直接访问全局 Settings。

8. **中高｜HotkeyMonitor.swift:57-58、74-79、96-110**  
   问题：右 Option/Command 的按下状态通过聚合 modifier flags 判断。若左 Option 已按住，再按下并释放右 Option，释放事件仍包含 `.maskAlternate`，会被误判成按下，录音无法结束。右 Command 同理。  
   修复：为目标物理 keyCode 独立维护 down 状态，匹配到对应 `flagsChanged` 时按物理状态转换，而不是依赖聚合 flags；tap 重启、睡眠唤醒时重置该状态。

9. **中｜AudioRecorder.swift:9、29-48**  
   问题：实时音频线程里获取 `NSLock`、扩容 `samples`、逐样本算 RMS，并为每个 buffer 向主线程排队。长时间 locked 录音时数组无限增长，可能造成音频丢帧、主线程 level 更新积压和大量内存占用。  
   修复：使用预分配、有最大时长的 ring buffer；实时回调只做固定成本拷贝。level 更新合并到约 30 Hz，并设置录音时长/样本数上限，达到上限后自动结束。

10. **中｜Cleaner.swift:43-46、SettingsView.swift:76**  
    问题：设置页声称“只有识别出的文字会发给 DeepSeek”，但改写模式实际还会发送用户选中的原文，属于错误的隐私提示。  
    修复：明确写成“语音识别文字以及改写时选中的文字会发送给 DeepSeek”，并允许用户单独关闭云端选区改写。