#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Flutter = 'D:\flutter\bin\flutter.bat',
    [string]$ChatId = 'a0420996-9c84-4a1c-b9a0-402fd8ba2992',
    [string]$ChatName = 'smoke_bob',
    [ValidateSet('private', 'group')]
    [string]$ChatType = 'private',
    [string]$IncomingImageMessageId = 'ca6bd378-6fed-44f8-b0b3-caf3bf5c4b6f',
    [string]$IncomingVideoMessageId = 'fd03ce7e-065c-48f7-a2a4-66e986634516',
    [string]$ImageFixture = 'web\icons\Icon-192.png',
    [string]$VideoFixture = 'artifacts\p1-s3-acceptance-20260727\p1-playable-100m.mp4',
    [string]$ArtifactDir = 'artifacts\cross-platform-media-acceptance-20260728\windows'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$imagePath = [IO.Path]::GetFullPath((Join-Path $repo $ImageFixture))
$videoPath = [IO.Path]::GetFullPath((Join-Path $repo $VideoFixture))
$artifactPath = [IO.Path]::GetFullPath((Join-Path $repo $ArtifactDir))

if (-not (Test-Path -LiteralPath $Flutter -PathType Leaf)) {
    throw "Flutter SDK not found: $Flutter"
}
if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    throw "Image fixture not found: $imagePath"
}
if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
    throw "Video fixture not found: $videoPath"
}

New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null
$env:PATH = (Join-Path $repo 'build\windows\x64') + ';' + $env:PATH

$flutterArguments = @(
    'test',
    'integration_test\windows_chat_media_ui_test.dart',
    '-d',
    'windows',
    '--dart-define=GENERIC_IM_SERVER_URL=http://127.0.0.1:8080',
    '--dart-define=GENERIC_IM_WS_URL=ws://127.0.0.1:8080/api/v1/ws',
    '--dart-define=GENERIC_IM_SMOKE_TEST=true',
    '--dart-define=GENERIC_IM_SMOKE_USERNAME=smoke_alice',
    '--dart-define=GENERIC_IM_SMOKE_PASSWORD=Smoke123',
    "--dart-define=GENERIC_IM_SMOKE_CHAT_ID=$ChatId",
    "--dart-define=GENERIC_IM_SMOKE_CHAT_NAME=$ChatName",
    "--dart-define=GENERIC_IM_SMOKE_CHAT_TYPE=$ChatType",
    "--dart-define=GENERIC_IM_QA_INCOMING_IMAGE_MSG_ID=$IncomingImageMessageId",
    "--dart-define=GENERIC_IM_QA_INCOMING_VIDEO_MSG_ID=$IncomingVideoMessageId",
    "--dart-define=GENERIC_IM_QA_IMAGE_FIXTURE=$imagePath",
    "--dart-define=GENERIC_IM_QA_VIDEO_FIXTURE=$videoPath",
    "--dart-define=GENERIC_IM_QA_ARTIFACT_DIR=$artifactPath"
)

Push-Location $repo
try {
    & $Flutter @flutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Windows media integration test failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
