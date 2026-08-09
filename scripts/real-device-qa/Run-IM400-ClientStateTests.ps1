#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$OutputDir = "artifacts/real-device-qa/local-client-state"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

$testFiles = @(
    "test/features/chat/chat_list_status_test.dart",
    "test/features/chat/chat_draft_state_test.dart",
    "test/features/chat/message_reliability_test.dart"
)
& "D:\flutter\bin\flutter.bat" test @testFiles
if ($LASTEXITCODE -ne 0) {
    throw "Flutter client-state tests failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $OutputDir "client-state-$stamp.json"
$report = [ordered]@{
    run_id = $stamp
    results = @(
        [ordered]@{
            case_ids = @("IM-096")
            status = "PASS"
            detail = "Widget and state tests verified that a failed optimistic last message remains explicit in the conversation list, takes precedence over a restored draft, survives cache/server merge, and is superseded by a newer server message."
        },
        [ordered]@{
            case_ids = @("IM-125")
            status = "PASS"
            detail = "Client reliability tests verified stable retry ids, server-ack replacement of sending placeholders, and deduplication by message id and authoritative sequence."
        }
    )
    summary = [ordered]@{
        pass = 2
        fail = 0
        covered_case_ids = @("IM-096", "IM-125")
    }
}
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding utf8NoBOM
Write-Output "REPORT_PATH=$reportPath"
