# インストーラーを生成する。
#   .\inno\build_installer.ps1            生成のみ
#   .\inno\build_installer.ps1 -Upload    生成後、GitHub の release(zip と同じ場所)へ配置する(gh が必要)
param(
    [switch]$Upload,
    [string]$Iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# pubspec.yaml の version(+ビルド番号を除く)を版とする
$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]

& $Iscc "/DAppVersion=$version" "inno\pero.iss"
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = "build\windows\setup\pero_$version.exe"
Write-Host "Created: $setup"

if ($Upload) {
    gh release upload "v$version" $setup --clobber
    if ($LASTEXITCODE -ne 0) { throw "release upload failed" }
}
