# Pin Saycribe IME on emulator; disable Gboard (LatinIME) for the test session only.
# Usage: .\pin_saycribe_ime.ps1 [-Adb path]
param(
  [string]$Adb = "D:\saycribe-android\env\sdk\platform-tools\adb.exe"
)
$ErrorActionPreference = "Stop"
$Saycribe = "com.saycribe.android/com.saycribe.ime.SaycribeImeService"
$Gboard = "com.google.android.inputmethod.latin"

function Invoke-Adb { & $Adb @args }

Write-Host "== disable Gboard (emulator only) =="
Invoke-Adb shell pm disable-user --user 0 $Gboard 2>$null
Write-Host "== enable + set Saycribe =="
Invoke-Adb shell ime enable $Saycribe
Invoke-Adb shell ime set $Saycribe
Start-Sleep 1
$cur = (Invoke-Adb shell settings get secure default_input_method).Trim()
Write-Host "default_input_method=$cur"
if ($cur -ne $Saycribe) {
  Write-Error "IME pin failed: got '$cur', expected '$Saycribe'"
  exit 1
}
Write-Host "OK: Saycribe is default IME"
