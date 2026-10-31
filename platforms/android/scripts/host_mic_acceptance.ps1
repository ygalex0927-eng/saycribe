# One-click host-mic acceptance helper for 4060 emulator (windowed).
# Does NOT change host audio devices. Token: copy from Mac .relay-tokens.env into
# C:\Users\Administrator\relay.env BEFORE running; this script pushes then deletes.
# Usage:
#   .\host_mic_acceptance.ps1                 # start emu + pin IME + print checklist
#   .\host_mic_acceptance.ps1 -SkipStart      # emu already running
#   .\host_mic_acceptance.ps1 -StopOnly       # kill emu + wipe device token
param(
  [switch]$SkipStart,
  [switch]$StopOnly,
  [string]$Adb = "D:\saycribe-android\env\sdk\platform-tools\adb.exe",
  [string]$Emulator = "D:\saycribe-android\env\sdk\emulator\emulator.exe",
  [string]$Avd = "saycribe_api34",
  [string]$TokenHost = "C:\Users\Administrator\relay.env",
  [string]$Evidence = "D:\saycribe-android\测试证据",
  [string]$Apk = "D:\saycribe-android\产物\saycribe-app-debug.apk"
)
$ErrorActionPreference = "Stop"
$Saycribe = "com.saycribe.android/com.saycribe.ime.SaycribeImeService"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function A { & $Adb @args }

if ($StopOnly) {
  Write-Host "Stopping emulator + wiping device token..."
  try { A emu kill } catch {}
  Start-Sleep 2
  try { A shell run-as com.saycribe.android rm -f files/relay.env } catch {}
  if (Test-Path $TokenHost) { Remove-Item $TokenHost -Force }
  Write-Host "Done. Keep APK + 测试证据."
  exit 0
}

if (-not $SkipStart) {
  Write-Host "== start AVD $Avd (windowed, -allow-host-audio) =="
  Start-Process -FilePath $Emulator -ArgumentList @(
    "-avd", $Avd, "-gpu", "swiftshader_indirect", "-accel", "on",
    "-no-snapshot-save", "-no-boot-anim", "-allow-host-audio"
  )
  A wait-for-device
  for ($i=0; $i -lt 90; $i++) {
    if ((A shell getprop sys.boot_completed).Trim() -eq "1") { break }
    Start-Sleep 2
  }
  Write-Host "boot_completed=$(A shell getprop sys.boot_completed)"
  Write-Host "== hostmicon =="
  A emu avd hostmicon
}

Write-Host "== pin IME =="
& "$ScriptDir\pin_saycribe_ime.ps1" -Adb $Adb

if (Test-Path $Apk) {
  Write-Host "== install APK =="
  A install -r $Apk
}

if (Test-Path $TokenHost) {
  Write-Host "== push token (will delete host copy after) =="
  A push $TokenHost /data/local/tmp/relay.env | Out-Null
  A shell "run-as com.saycribe.android sh -c 'cat /data/local/tmp/relay.env > files/relay.env'"
  A shell rm -f /data/local/tmp/relay.env
  Remove-Item $TokenHost -Force
  Write-Host "token on device; host copy deleted"
} else {
  Write-Warning "No $TokenHost — put Mac .relay-tokens.env there first (do not cat)."
}

A shell pm grant com.saycribe.android android.permission.RECORD_AUDIO
A shell am start -n com.saycribe.android/com.saycribe.app.NotesActivity
Start-Sleep 1
A shell input tap 540 700

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
Write-Host @"

======== 人工验收清单（牙膏哥对着音箱说话）========
1) 确认状态栏 IME 为 Saycribe；Hold to talk 可见。
2) 对着「智能音箱 Pro」麦克风说：今天天气很好，我们一起去公园散步吧
3) 长按 Hold to talk 说完再松手；Notes 应出现整理后的中文。
4) 同样在 Chrome 地址/搜索框、短信正文各测一次。
5) 通过标准：out 非空且语义正确；采证据：
     adb exec-out run-as com.saycribe.android cat files/last_ime_mic.txt
     adb exec-out screencap -p > 测试证据\hostmic-notes.png
6) 收尾：
     .\host_mic_acceptance.ps1 -StopOnly
====================================================
"@
