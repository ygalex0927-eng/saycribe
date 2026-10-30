# Saycribe

按住一个键说话，松开后，整理好的文字出现在光标处。对标 Typeless，macOS 版。

- **本地识别**：SenseVoice-Small（int8，sherpa-onnx），录音不出本机，M2 上约 50 倍实时。
- **AI 整理**：DeepSeek `deepseek-flash`（关闭思考），负责去口头禅、处理改口、加标点、排列表、按场景调语气、按个人词典纠错。
- **语音改写**：先选中文字再说话，说出的话会被当作修改指令（"改得礼貌点""翻成英文"）。

- **会议同传**：边说中文，Zoom / 腾讯会议里的人听到英文语音。本机切句（Silero VAD）+ 识别，DeepSeek 翻译，本机 Kokoro 合成英文语音，送进虚拟麦克风 BlackHole。

产品与技术方案见 [docs/PRD.md](docs/PRD.md)。

## 使用
| 操作 | 效果 |
|---|---|
| 按住说话键说话，松开 | 识别、整理并写入 |
| 快速点一下说话键 | 开始收听（不用一直按着），说完再点一下结束 |
| 录音时按 Esc | 取消 |
| 设置 › 说话方式 | 可改成「只用按住说话」（双击锁定）或「点一下开始，再点一下结束」 |
| 先选中文字，再按住 Fn 说指令 | 改写选中的文字 |
| 按住 ⌘ + ⌥ 说话（任意语言），松开 | 直接写入译文（目标语言在设置里选，默认英语） |
| 按住说话键时再补按 ⌥ | 这一段改为翻译 |

### 会议同传
1. 安装虚拟麦克风（只需一次，要输入开机密码）：`brew install --cask blackhole-2ch`
2. 会议软件里把**麦克风**选成「BlackHole 2ch」（扬声器不用改）。
3. 菜单栏 Saycribe › 「会议同传（中 → 英语音）」，弹出字幕窗。说完一句停顿一下，约 2 秒后英文语音送进会议。
4. 建议戴耳机：外放时别人的英文会被麦克风听到（默认会忽略整句英文，可在设置里改）。
5. 声音、语速、输出设备在 设置 › 会议同传 里改。`open -a Saycribe --args --interpret-now` 可以启动即开始同传。

调试：`Saycribe --interpret in.wav out.wav` 离线跑一遍 切句→识别→翻译→合成，打印每句耗时。

首次启动需要开启三项权限：麦克风、辅助功能、输入监控。设置窗口里会逐项提示。
如果用 Fn 键，请把「系统设置 › 键盘 › 按下 🌐 键时」设为「不执行任何操作」。

## 开发
```bash
./scripts/build_app.sh                       # 编译 → build/Saycribe.app → 安装到 ~/Applications
python3 eval/run_eval.py                     # 口语整理评测（eval/cases.jsonl）
~/Applications/Saycribe.app/Contents/MacOS/Saycribe --selftest eval/audio/t1.wav chat   # 不用麦克风，跑一遍识别+整理
```
第一次编译前需要把依赖下载到 `vendor/`（已被 .gitignore 忽略）：
```bash
mkdir -p vendor && cd vendor
gh release download v1.13.8 -R k2-fsa/sherpa-onnx -p 'sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2'
gh release download asr-models -R k2-fsa/sherpa-onnx -p 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2'
gh release download tts-models -R k2-fsa/sherpa-onnx -p 'kokoro-en-v0_19.tar.bz2'   # 会议同传的英文语音（fp32 比 int8 快一倍多）
for f in *.tar.bz2; do tar xjf "$f"; done
mkdir -p vad && gh release download asr-models -R k2-fsa/sherpa-onnx -p 'silero_vad.onnx' -D vad
```
API Key 读取自 `~/.config/suikou/secrets.env`（`DEEPSEEK_API_KEY=...`，权限 600），也可以在设置窗口里填写。

## 目录
```
Sources/Suikou/
  HotkeyMonitor.swift   全局热键（CGEventTap，按住 / 双击锁定 / Esc）
  AudioRecorder.swift   AVAudioEngine 录音 → 16kHz 单声道
  Recognizer.swift      SenseVoice 本地识别（sherpa-onnx C API）
  Cleaner.swift         DeepSeek 整理与改写，提前建立连接以降低延迟
  AppContext.swift      前台 App → 场景风格；用辅助功能读取选中文字
  Inserter.swift        剪贴板 + ⌘V 写入，之后恢复原剪贴板
  HUD.swift             底部悬浮胶囊（波形 / 整理中 / 已写入）
  Coordinator.swift     串起整条流程
  Interpreter.swift     会议同传：VAD 切句 → 识别 → 翻译 → 按顺序播报；字幕浮窗
  Speaker.swift         Kokoro 英文语音合成，播放到指定输出设备（BlackHole）
Resources/prompts/      整理和改写的提示词（App 和评测脚本共用）
eval/                   口语整理评测集与评测脚本
design/                 图标源文件（Grok 生成）与生成脚本
```
