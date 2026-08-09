#Requires -Version 7.0
<#
.SYNOPSIS
检查源码、MySQL 和 MongoDB 中已知乱码模式是否仍有残留。

.DESCRIPTION
先运行源码扫描，再对指定 Docker 数据库执行只读统计查询。Mongo 检查脚本
会临时复制进容器并在结束时删除；本脚本不会修复或删除业务数据。

.PARAMETER SkipDatabase
只扫描源码，不访问 Docker、MySQL 和 MongoDB。

.PARAMETER MysqlContainer
本地 MySQL 容器名称。

.PARAMETER MongoUri
从宿主机访问目标 MongoDB 的连接串；不得把生产凭据写入脚本。

.EXAMPLE
pwsh -File scripts/verify-mojibake-p1.ps1 -SkipDatabase
#>
[CmdletBinding()]
param(
    [switch]$SkipDatabase,
    [string]$MysqlContainer = "genericim-mysql",
    [string]$MongoContainer = "genericim-mongodb",
    [string]$MongoUri = "mongodb://genericim:genericim@127.0.0.1:27017/genericim_messages?authSource=admin"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Host "==> Check source mojibake"
& (Join-Path $PSScriptRoot "check-mojibake.ps1")

if ($SkipDatabase) {
    Write-Host "Database mojibake checks skipped."
    exit 0
}

function Assert-DockerContainer {
    param([Parameter(Mandatory = $true)][string]$Name)

    $state = docker inspect -f "{{.State.Running}}" $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or $state -ne "true") {
        throw "Docker container is not running: $Name"
    }
}

function Invoke-MysqlMojibakeCheck {
    $sqlPath = Join-Path $repoRoot "backend\scripts\check_mojibake_remaining.sql"
    $output = Get-Content -Raw -LiteralPath $sqlPath |
        docker exec -i $MysqlContainer mysql -ugenericim -pgenericim --default-character-set=utf8mb4 genericim
    $userChats = 0
    $pushLogs = 0
    for ($i = 0; $i -lt $output.Count; $i++) {
        if ($output[$i] -eq "user_chats_remaining" -and ($i + 1) -lt $output.Count) {
            $userChats = [int]$output[$i + 1]
        }
        if ($output[$i] -eq "push_delivery_logs_remaining" -and ($i + 1) -lt $output.Count) {
            $pushLogs = [int]$output[$i + 1]
        }
    }
    return [pscustomobject]@{
        user_chats_remaining = $userChats
        push_delivery_logs_remaining = $pushLogs
        raw = @($output)
    }
}

function Invoke-MongoMojibakeCheck {
    $scriptPath = Join-Path $repoRoot "backend\scripts\check_mojibake_remaining_mongo.js"
    docker cp $scriptPath "$($MongoContainer):/tmp/check_mojibake_remaining_mongo.js" | Out-Null
    try {
        $output = docker exec $MongoContainer mongosh --quiet $MongoUri /tmp/check_mojibake_remaining_mongo.js
    } finally {
        docker exec $MongoContainer rm -f /tmp/check_mojibake_remaining_mongo.js | Out-Null
    }
    $remaining = 0
    foreach ($line in $output) {
        if ($line -match '^mongo_remaining=(\d+)$') {
            $remaining = [int]$Matches[1]
        }
    }
    return [pscustomobject]@{
        mongo_remaining = $remaining
        raw = @($output)
    }
}

Write-Host "==> Check database mojibake"
Assert-DockerContainer -Name $MysqlContainer
Assert-DockerContainer -Name $MongoContainer

$mysql = Invoke-MysqlMojibakeCheck
$mongo = Invoke-MongoMojibakeCheck

$summary = [pscustomobject]@{
    mysql = $mysql
    mongo = $mongo
}
$summary | ConvertTo-Json -Depth 20

if (
    $mysql.user_chats_remaining -ne 0 -or
    $mysql.push_delivery_logs_remaining -ne 0 -or
    $mongo.mongo_remaining -ne 0
) {
    throw "Mojibake database check failed."
}

Write-Host "P1 mojibake guard passed."
