# Android real-device QA foundation

This harness uses PowerShell 7 for orchestration, ADB for the stable device
transport, and `uiautomator2` for semantic selectors and Unicode text input.
Appium is intentionally not required for the baseline because its server,
driver and WebDriver layers add startup cost without improving the existing
Flutter/ADB flows in this repository.

## Initialize

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\real-device-qa\Initialize-RealDeviceQa.ps1
```

When exactly one authorized device is online, its serial is selected
automatically. With multiple online devices, pass `-Serial <serial>`.

## Device actions

```powershell
# Probe
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 probe

# Semantic click and Unicode input
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 tap-selector text "消息"
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 type "中文 IM smoke" --clear

# Coordinates, swipe and evidence snapshot
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 tap 600 2200
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 swipe 600 1900 600 600 --duration 0.4
pwsh -File .\scripts\real-device-qa\Invoke-DeviceAction.ps1 snapshot .\artifacts\real-device-qa\manual --name step-001
```

## Continuous Logcat

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\real-device-qa\Start-RealDeviceLogcat.ps1 -ClearBuffer
```

The monitor saves the complete `main`, `system` and `crash` streams, plus a
filtered event log and JSONL event index. It tracks the app's changing PIDs and
only treats generic exceptions/socket errors as app events when the PID or
package belongs to `com.genericim.ma100`. Categories are:

- `CRASH`, `ANR`, `FATAL`: severe and session-failing.
- `EXCEPTION`: app exception requiring review.
- `IM_SOCKET`: WebSocket/socket disconnect, handshake, heartbeat and timeout
  evidence. These are review events because expected network-interruption
  cases deliberately produce them.

## Closed-loop test session

Wrap any PowerShell test script so Logcat begins first, stops last, and severe
events propagate to a failing session result:

```powershell
pwsh -File `
  .\scripts\real-device-qa\Invoke-RealDeviceQaSession.ps1 `
  -TestScript .\scripts\p2_real_device_network_resume.ps1 `
  -TestArguments @("-Device", "UQG5T20915006269")
```

Generated evidence is written below `artifacts/real-device-qa/`, which is
already excluded from Git.
