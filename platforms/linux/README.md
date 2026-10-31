# Saycribe Linux 客户端（platforms/linux）

Rust 平台层：全局热键、录音、文本注入、HUD/托盘。识别与中转走 `platforms/core`（SenseVoice + Silero VAD + `pipeline::Session`）与可配置中转（协议 v1.1）。

## 构建

需要 **rustc ≥ 1.88**（sherpa-onnx 2.0.1）。本 box 使用 `~/.local/rust-sc` 的 rustup stable：

```bash
export RUSTUP_HOME=$HOME/.local/rust-sc/rustup CARGO_HOME=$HOME/.local/rust-sc/cargo
export PATH=$HOME/.local/rust-sc/cargo/bin:$PATH
# 若缺 libstdc++.so 链接名：ln -s /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ~/.local/rust-sc/libs/libstdc++.so
export RUSTFLAGS="-L $HOME/.local/rust-sc/libs"
cargo build --release
```

features：`default = ["tray","core"]`。`--no-default-features` 可去掉 tray；去掉 `core` 则只用 stub 识别。

## 模型

按 `docs/模型下载.md` 放到 `~/.local/share/saycribe/models/`（可用 `SAYCRIBE_MODELS_DIR` 覆盖）：

```
models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/{model.int8.onnx,tokens.txt}
models/silero_vad.onnx
```

```bash
saycribe --download-models   # 经 core ModelManager（仅 GitHub；无镜像/断点）
```

## 用法

```bash
saycribe --set-token          # stdin 读入设备 token（存 ~/.config/saycribe/token，0600）
saycribe --check              # GET /v1/me
saycribe --detect             # X11 / Wayland
saycribe --relay-bench        # 真中转 ping/me/clean 冷/热延迟（勿把 token 打进日志）
saycribe --transcribe WAV [--clean] [--style notes]  # 真识别（+整理）
saycribe --wayland-caps       # Wayland 能力探测
saycribe --portal-caps        # xdg-desktop-portal 接口探测（RemoteDesktop/GlobalShortcuts/Clipboard）
saycribe --portal-rd-test     # 建立 RemoteDesktop 会话（需授权弹窗；成功则写 restore_token）
saycribe --toggle             # Wayland 热键 toggle FIFO 兜底（自动清理残留 FIFO，非阻塞写）
saycribe --app                # 前台应用（X11 WM_CLASS / sway IPC app_id）
saycribe --paste TEXT         # Wayland 诊断：按听写结果方式注入 TEXT
saycribe                      # 前台运行（按住热键听写）
```

环境变量：`SAYCRIBE_TOKEN`、`SAYCRIBE_RELAY_URL`、`SAYCRIBE_MODELS_DIR`、`SAYCRIBE_TEST_WAV`（用 WAV 代替麦克风）、`SAYCRIBE_STUB_TRANSCRIPT`（自测 stub）、`SAYCRIBE_BACKEND=x11|wayland`、`SAYCRIBE_PORTAL_TIMEOUT_MS`（portal 授权超时，默认 12000）、`SAYCRIBE_TOGGLE_FIFO`。

配置：`~/.config/saycribe/config.json`（`relay_url` 默认 `https://saycribe-api.motomotos.com`）。

## 后端状态（交付以真机会话为准）

| 能力 | 状态 |
|---|---|
| 真识别 + 真中转 clean | box 上已用 WAV 自测（见报告）；非 mock |
| X11 热键/注入/选区 | 代码完成；**Xvfb 自测 22/22**，真机 / 4060 WSL **尚未交付** |
| Wayland GlobalShortcuts | **已实现**（ashpd）：优先 portal hold-to-talk；失败/超时回退 FIFO toggle。mutter+portal-gnome 接口探测通过；授权弹窗需真会话（见清单） |
| Wayland wlroots 虚拟键盘 | `wtype -s 80` 粘贴：headless sway foot/Chrome 实测通过（本轮回归 method=Wtype） |
| Wayland 前台应用 | sway IPC 已实测；GNOME/KDE 返回 "wayland" |
| Wayland RemoteDesktop | **已实现**（ashpd）：粘贴和弦 + Unicode keysym；`restore_token` → `data_dir()/rd_restore_token`。mutter+portal-gnome 探测通过；mutter 原生 RD keysym 注入已通；**portal 授权弹窗无法无头自动批准** |
| Wayland 剪贴板（GNOME） | wl-copy（读回校验）→ xclip(XWayland) → RemoteDesktop keysym；无 wlr-data-control 时靠后两档 |
| 注入降级链 | wtype → portal paste → ydotool → portal type → 仅剪贴板 |
| ydotool 兜底 | 已装；本机内核无 uinput，**仍未测实际注入** |

## 自测

```bash
cargo test
bash tests/run_x11_selftest.sh   # stub + mock 中转 + Xvfb（不算真机交付）
```

## 目录

- `src/x11/` X11 后端
- `src/wayland/` Wayland（clipboard / inject / hotkey / appctx / **portal**）
- 仓库旁 `自测记录/portal授权清单.txt`：GNOME/KDE portal 真机会话待测项
- `src/core_adapter.rs` 接 `saycribe-core`
- `src/audio.rs` PipeWire/Pulse/`arecord` 或 `SAYCRIBE_TEST_WAV`
- `tests/mock_relay.py` 协议 v1.1 mock
