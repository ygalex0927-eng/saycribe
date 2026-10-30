# Saycribe core API（platforms/core，crate `saycribe-core` v0.1，2026-10-30）

Rust 共享核心，Windows / Linux（以及之后可选的 Android/iOS）复用。**平台层负责**：录音（并重采样到 16kHz 单声道 f32）、全局热键、注入文字、选区兜底、剪贴板恢复、HUD、托盘、系统钥匙串。**core 负责**：识别、VAD 分段、中转客户端、配置/历史/词典/语气映射、模型下载校验。

## 构建
- `cargo build` / `cargo test`（默认 feature `asr` 开启，sherpa-onnx 2.0.1 构建时自动下载 k2-fsa 官方预编译静态库）。
- 支持目标：Windows x64 (`x86_64-pc-windows-msvc`)、Linux x86_64 / aarch64 (`*-unknown-linux-gnu`)、macOS arm64/x64。离线/内网构建：设置 `SHERPA_ONNX_LIB_DIR` 或 `SHERPA_ONNX_ARCHIVE_DIR`。
- 只要中转/配置/历史（不含识别）：`--no-default-features`，无原生依赖。
- 自测 CLI：`cargo run --release --example saycribe-cli -- test.wav --models <dir> [--clean --relay URL]`，token 从环境变量 `SAYCRIBE_TOKEN` 读。

## 模块结构
```
saycribe_core
├── Platform            mac|windows|linux|ios|android；Platform::current()；SAMPLE_RATE=16000
├── error               CoreError, RelayErrorKind, Result
├── paths::Paths        标准目录（directories crate）
├── config::Config      配置 JSON，DEFAULT_RELAY_URL
├── token               TokenStore trait、FileTokenStore（0600）、DeviceToken
├── relay               RelayClient（阻塞/非阻塞/流式）、RelayRequest、RelayResponse、Usage
├── history             History、HistoryEntry、ExportFormat
├── dictionary          Dictionary（确认词+候选词、从修改中学词）
├── tone::AppToneMap    App→语气（字符串键）
├── models              ModelManager、ModelSpec、SENSE_VOICE、SILERO_VAD、sha256_file
├── asr   [feature asr] Recognizer（SenseVoice）、Transcript、read_wav（仅测试）
├── vad   [feature asr] Segmenter（Silero VAD）、Segment
└── pipeline [asr]      Engine、Session、SessionEvent、SessionOptions、EventSink
```

## 1. 目录（paths）
`Paths::standard()`（ProjectDirs `com.saycribe.Saycribe`）：
| | config_dir | data_dir（历史、模型） |
|---|---|---|
| Linux | `$XDG_CONFIG_HOME/saycribe` (~/.config/saycribe) | `$XDG_DATA_HOME/saycribe` |
| Windows | `%APPDATA%\saycribe\Saycribe\config` | `%LOCALAPPDATA%\saycribe\Saycribe\data` |
| macOS | `~/Library/Application Support/com.saycribe.Saycribe` | 同左 |

文件：`config.json`、`token.json`（兜底）、`dictionary.json`、`history.jsonl`、`models/<id>/`。`Paths::under(root)` 用于便携版/测试。

## 2. 配置 `Config`
字段：`relay_url`（默认 `https://saycribe-api.motomotos.com`，可改）、`language`（auto）、`default_style`（notes）、`app_tones`、`history_enabled`、`history_retention_days`（0=永久）、`vad_min_silence`（0.45s）、`max_concurrent_segments`（3）、`asr_threads`、`platform_extra`（平台私有键值，core 原样保存）。`Config::load(&paths)` / `save(&paths)`，缺省字段自动补默认。

## 3. Token
```rust
pub struct DeviceToken { token: String /*sct_...*/, platform: Platform, device: String, token_id: Option<String> }
pub trait TokenStore: Send + Sync { fn read(&self)->Result<Option<DeviceToken>>; fn write(&self,&DeviceToken)->Result<()>; fn delete(&self)->Result<()>; }
FileTokenStore::new(paths.token_file())   // 兜底：原子写，unix 0600
```
平台层实现 Keychain / 凭据管理器 / Secret Service 版本。请求时带 `Authorization: Bearer` 和 `X-Saycribe-Platform: <platform>`。

## 4. 中转客户端 `RelayClient`
```rust
let c = RelayClient::new(&cfg.relay_url, token_store.read()?);   // Clone 廉价，内部共享连接池（keep-alive）
c.warm_up();                         // 按下热键时调用：后台 ping 预连接，不阻塞
c.ping()? ; c.me()? -> Me{token_id,user,device}   // 设置页「测试连接」
c.call(&req)? -> RelayResponse       // 阻塞，502/504 自动重试 1 次
c.call_stream(&req, |delta| ..)?     // 阻塞 SSE，返回 done
c.call_async(req, |res| ..)          // 非阻塞，后台线程回调
c.call_stream_async(req, on_delta, on_done)
```
`RelayRequest::{Clean{transcript,style,dictionary,context,meta:SegmentMeta{session_id,seq,final}}, Edit{selection,instruction}, Translate{transcript,direction,style,dictionary}, Interpret{transcript,context,dictionary}}`；`RelayRequest::clean(text, style, dict)` 快捷构造。
`RelayResponse{text, session_id, seq, model, prompt_version, usage:Usage{prompt_tokens,completion_tokens,total_tokens,cache_hit_tokens}, timing, client_ms}`。
超时：连接 3s；整体 `4s + 字数×20ms`（同协议）。

### 错误分类 `RelayErrorKind`（core 已分好）
| kind | 来源 | `user_message()` | `retryable()` |
|---|---|---|---|
| Offline | DNS/连接拒绝/连接超时/读流中断 | 需要联网 | 否 |
| Unauthorized | 401 | 请在设置里填写/重新获取 token | 否 |
| Revoked | 403 | 同上 | 否 |
| RateLimited | 429 | 请求太频繁，请稍后再试 | 否 |
| Upstream | 500/502/503 | 整理服务暂时出错 | 是 |
| Timeout | 504 / 读超时 | 整理超时 | 是 |
| BadRequest | 400/413 等 | 请求无效 | 否 |
`CoreError::relay_kind()` 取分类。断网不做本地兜底，原文仍写历史。

## 5. 识别与分段（feature `asr`）
```rust
let rec = Recognizer::new(&model_dir, "auto", 4, None /* 或 Some("cuda") */)?;
rec.transcribe(&pcm)? -> Transcript{text, audio_seconds, decode_ms}
let mut seg = Segmenter::new(&silero_path, 0.45 /*停顿s*/, 12.0 /*最长段s》); // 或 with_config(VadConfig::default())?;
seg.push(&pcm) -> Vec<Segment{start, samples}>;  seg.finish() -> Vec<Segment>;  seg.speaking()
```
`Recognizer` 是 Send+Sync，可放 `Arc` 复用（启动加载一次，约 0.3–1s）。

## 6. 会话流水线（推荐平台层直接用）
```rust
let engine = Arc::new(Engine{ recognizer: Arc::new(rec), vad_model, relay, min_silence: 0.45, max_concurrent: 3 });
let sink: EventSink = Arc::new(|ev| match ev {
    SessionEvent::Recognized{seq, raw, decode_ms} => {/* HUD 显示原文 */}
    SessionEvent::Cleaned{seq, text, relay_ms}    => {/* 已按 seq 连续，可边说边插入 */}
    SessionEvent::Done{raw, text, error, segments, audio_seconds} => {/* text=None 时看 error（Offline→「需要联网」）；写历史 */}
});
let s = Session::start(engine, SessionOptions{ style: Some(tone), dictionary, clean: true }, sink)?; // 内部自动 warm_up
s.push(&pcm_chunk);   // 录音回调里调用，非阻塞
s.finish();           // 松开热键；或 s.cancel()
```
- 全部在后台线程，回调在 core 线程触发，平台层自己切回 UI 线程。
- 长录音：VAD 按停顿切段 → 识别 → 立即 `/v1/clean`（同 session_id，seq 递增，最后一段 final=true，context=前文原文末尾 300 字），并发 ≤3，按 seq 拼接。（context 用原文而非已整理文本，以便并发；服务端无状态。）

## 7. 历史 / 词典 / 语气
- `History::open(&paths, enabled, retention_days)`：`append`（enabled=false 时不写）、`list`、`prune`（按保留天数）、`delete(id)`、`clear`、`export(ExportFormat::{Json,Csv,Markdown}) -> String`。
- `Dictionary::load/save`；`add/remove`；候选：`learn_from_edit(inserted, edited) -> Vec<String>`（只进 candidates，需 `accept`/`reject` 确认）；`words` 随整理请求发送。
- `AppToneMap`（BTreeMap<String,String>，键大小写不敏感）：Windows 用 exe 名（`code.exe`）、mac 用 bundle id、Linux 用 WM_CLASS/app_id；`with_defaults()`、`set`、`remove`、`style_for(app, default)`。

## 8. 模型 `ModelManager`
`ModelManager::new(paths.models_dir()).ensure(&SENSE_VOICE, |done,total|{})? -> PathBuf`：未安装则下载 → 校验 sha256 → 解包 .tar.bz2 → 原子改名。已安装直接返回。
- SENSE_VOICE：目录名 `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2，sha256 `7305f790…8e63`（158MB）
- SILERO_VAD：直接放到 `models/silero_vad.onnx`，sha256 `9e2449e1…1fd6`
- 当前 URL 指向 GitHub releases（国内可能慢）。**分发镜像等 OSS 开通后再换，现在不自建分发。** 平台层也可直接把已有目录交给 `Recognizer::new`。

## 9. 待定 / 后续
- 耳语模式（增益+降噪）计划在 core 加 `audio::Preprocess`，当前未实现，平台层先做增益。
- C ABI（给 Swift/Kotlin 用）暂不提供，需要时再加 `ffi` feature。
