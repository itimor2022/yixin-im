#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ImageMessageId = '4fccd4bf-8e17-47f9-a1fc-43c87ccd1158',
    [string]$VideoMessageId = 'edb34ff0-0914-429e-9a4f-fb6783ceba08',
    [string]$ChatId = '',
    [string]$ArtifactDir = 'artifacts\cross-platform-media-acceptance-20260728\h5-pc'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:GENERIC_IM_SERVER_URL = 'http://127.0.0.1:8080'
$env:GENERIC_IM_H5_URL = 'http://127.0.0.1:5176'
$env:GENERIC_IM_SMOKE_USERNAME = 'smoke_alice'
$env:GENERIC_IM_SMOKE_PEER_USERNAME = 'smoke_bob'
$env:GENERIC_IM_SMOKE_PASSWORD = 'Smoke123'
$env:GENERIC_IM_SMOKE_EXISTING_ONLY = '1'
$env:GENERIC_IM_SMOKE_EXISTING_IMAGE_MSG_ID = $ImageMessageId
$env:GENERIC_IM_SMOKE_EXISTING_VIDEO_MSG_ID = $VideoMessageId
$env:GENERIC_IM_SMOKE_CHAT_ID = $ChatId
$env:GENERIC_IM_SMOKE_ARTIFACT_DIR = $ArtifactDir

Push-Location $repo
try {
    & node scripts\smoke_h5_chat_media.mjs
    if ($LASTEXITCODE -ne 0) {
        throw "H5 PC existing-media acceptance failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
