# 从 sqlite.org 下载官方 Windows x64 sqlite3.dll，供 build_binary.sh 放到 nava.exe 旁边。
# 用法：powershell -ExecutionPolicy Bypass -File tool/fetch_sqlite3_dll.ps1 [-Output 路径]
param(
  [string]$Output = "$PSScriptRoot/../sqlite3.dll"
)

$ErrorActionPreference = 'Stop'
$page = Invoke-WebRequest -UseBasicParsing 'https://www.sqlite.org/download.html'
$match = [regex]::Match($page.Content, 'href="(?<path>\d{4}/sqlite-dll-win-x64-\d+\.zip)"')
if (-not $match.Success) {
  throw '未能从 sqlite.org 找到 Windows x64 sqlite3.dll 下载链接'
}
$url = 'https://www.sqlite.org/' + $match.Groups['path'].Value
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('nava-sqlite-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $zip = Join-Path $temp 'sqlite.zip'
  Invoke-WebRequest -UseBasicParsing $url -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath $temp -Force
  Copy-Item (Join-Path $temp 'sqlite3.dll') $Output -Force
  Write-Host "已下载：$Output"
} finally {
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
