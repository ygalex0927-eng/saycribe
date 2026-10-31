#!/usr/bin/env bash
# X11 end-to-end self-test: Xvfb + xfwm4 + real apps (xfce4-terminal, Chrome
# textarea) + mock relay. Needs: Xvfb xfwm4 xdotool xprop xfce4-terminal
# google-chrome dbus-launch python3. Usage: tests/run_x11_selftest.sh
set -u
cd "$(dirname "$0")/.."
BIN=target/debug/saycribe; PORT=18999; T=$(mktemp -d /tmp/sc-selftest.XXXX)
unset WAYLAND_DISPLAY
export SAYCRIBE_BACKEND=x11
export DISPLAY=:77 XDG_CONFIG_HOME=$T/cfg XDG_DATA_HOME=$T/data MOCK_LOG=$T/mock.jsonl
PASS=0; FAIL=0; PIDS=()
ok(){ echo "PASS  $1"; PASS=$((PASS+1)); }; bad(){ echo "FAIL  $1 :: $2"; FAIL=$((FAIL+1)); }
check(){ if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi; }
cleanup(){ pkill -f "$BIN" 2>/dev/null; kill "${PIDS[@]}" 2>/dev/null; [ -n "${DBUS_SESSION_BUS_PID:-}" ] && kill $DBUS_SESSION_BUS_PID; rm -rf "$T"; }
trap cleanup EXIT
cargo build -q || exit 1
Xvfb :77 -screen 0 1280x800x24 >/dev/null 2>&1 & PIDS+=($!); sleep 1
eval "$(dbus-launch --sh-syntax)"
xfwm4 >/dev/null 2>&1 & PIDS+=($!)
python3 tests/mock_relay.py $PORT & PIDS+=($!); sleep 1
title(){ xprop -id "$1" _NET_WM_NAME | sed 's/^[^"]*"//; s/"$//'; }
hud(){ title "$(xdotool search --class Saycribe | tail -1)"; }
start(){ pkill -f "$BIN\$" 2>/dev/null; sleep 0.3
  SAYCRIBE_RELAY_URL=${URL:-http://127.0.0.1:$PORT} SAYCRIBE_TOKEN=${TOK:-sct_test} SAYCRIBE_STUB_TRANSCRIPT="$1" \
    $BIN >> $T/app.log 2>&1 & sleep 0.8
  # each instance keeps serving the restored clipboard; a restart drops it, so re-seed
  $BIN --clip-set "ORIGINAL-CLIP" & sleep 0.4; }
talk(){ xdotool keydown Alt_R; sleep "${1:-1.0}"; xdotool keyup Alt_R; sleep 1.0; }

echo "== detection"; check "detect X11 on Xvfb" "$($BIN --detect)" "X11"
check "detect Wayland when WAYLAND_DISPLAY set (WSLg-like)" "$(env -u SAYCRIBE_BACKEND WAYLAND_DISPLAY=wayland-0 $BIN --detect)" "Wayland { xwayland: true }"

echo "== terminal (xfce4-terminal, Ctrl+Shift+V)"
xfce4-terminal --disable-server -T SCTERM -x sh -c "cat > $T/term.txt" >/dev/null 2>&1 & PIDS+=($!); sleep 2.5
xdotool windowactivate --sync "$(xdotool search --name SCTERM | head -1)"; sleep 0.3
check "WM_CLASS of terminal" "$($BIN --app)" "xfce4-terminal/Xfce4-terminal"
start "嗯那个我们明天下午要不要一起去吃饭啊"
talk 1.5   # held 1.5 s: auto-repeat must not produce extra press/release
xdotool key Return; sleep 0.3
check "terminal received cleaned text" "$(cat $T/term.txt)" "我们明天下午要不要一起去吃饭啊。"
check "one press + one release while held" "$(grep -c '\[event\]' $T/app.log)" "2"
check "clipboard restored after paste" "$($BIN --clip-get)" "ORIGINAL-CLIP"
check "HUD final state" "$(hud)" "完成"
grep -q "style=code" $T/app.log && ok "terminal → code style" || bad "terminal style" "$(grep latency $T/app.log)"

echo "== GUI app (Chrome textarea, Ctrl+V)"
google-chrome --no-sandbox --user-data-dir=$T/chrome --no-first-run --no-default-browser-check --disable-gpu \
  --app='data:text/html,<title>T:</title><textarea autofocus oninput="document.title=%27T:%27+this.value"></textarea>' >/dev/null 2>&1 & PIDS+=($!)
sleep 6; W=$(xdotool search --name '^T:' | head -1); xdotool windowactivate --sync $W; sleep 0.5
start "第一段内容|嗯第二段内容"
talk 0.8
check "long recording 2 segments merged by seq" "$(title $W)" "T:第一段内容。第二段内容。"
check "clipboard restored (GUI)" "$($BIN --clip-get)" "ORIGINAL-CLIP"
start "改礼貌点"
xdotool key ctrl+a; sleep 0.3; talk 0.5
check "fresh PRIMARY selection → edit replaces it" "$(title $W)" "T:第一段内容。第二段内容。（已按“改礼貌点”改写）"
start "再加一句"
xdotool key End; sleep 0.2; talk 0.5
check "stale PRIMARY ignored, Ctrl+C probe finds nothing → insert" "$(title $W)" "T:第一段内容。第二段内容。（已按“改礼貌点”改写）再加一句。"
xdotool key ctrl+a; sleep 0.2; xdotool key ctrl+a; sleep 0.2
start "翻成英文"   # restart resets PRIMARY freshness → selection must come via Ctrl+C probe
xdotool key ctrl+a; sleep 0.2; talk 0.5
case "$(title $W)" in *"（已按“翻成英文”改写）") ok "Ctrl+C fallback reads unchanged selection";; *) bad "Ctrl+C fallback" "$(title $W)";; esac
check "clipboard restored after Ctrl+C probe" "$($BIN --clip-get)" "ORIGINAL-CLIP"
xdotool key ctrl+a BackSpace; sleep 0.2

echo "== cancel / errors"
start "不应该出现"; xdotool keydown Alt_R; sleep 0.4; xdotool key Escape; xdotool keyup Alt_R; sleep 0.8
check "Esc cancels (nothing inserted)" "$(title $W)" "T:"
grep -q "\[event\] cancelled" $T/app.log && ok "cancel event" || bad "cancel event" ""
URL=http://127.0.0.1:1 start "断网测试"; talk 0.4
check "offline → HUD 需要联网" "$(hud)" "需要联网"
check "offline → nothing inserted" "$(title $W)" "T:"
grep -q '"raw":"断网测试","text":null' $XDG_DATA_HOME/saycribe/history.jsonl && ok "offline → raw text kept in history" || bad "history" "$(cat $XDG_DATA_HOME/saycribe/history.jsonl)"
TOK=sct_bad start "无效token"; talk 0.4
check "401 → token hint" "$(hud)" "请在设置里填写/重新获取 token"
start "限流#429"; talk 0.4; check "429 → rate limited" "$(hud)" "请求太频繁，请稍后重试"
start "嗯呃"; talk 0.4; check "filler-only → nothing inserted" "$(title $W)" "T:"
echo "== latency (mock relay, release→paste keystroke sent; recognizer is a stub)"; grep latency $T/app.log | sed 's/ app=.*//'
echo "RESULT: $PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
