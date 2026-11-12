<#
.SYNOPSIS
  `.pero` ファイルを PERO に関連付ける(現在のユーザーのみ。管理者権限は不要)。
.DESCRIPTION
  HKCU\Software\Classes に登録する。ダブルクリックで PERO が起動し、すでに起動していれば既存のウィンドウで開く(単一インスタンス)。
  解除するときは -Unregister を付けて実行する。
.EXAMPLE
  .\register_file_association.ps1 -ExePath "C:\Apps\PERO\project_er_operation.exe"
  .\register_file_association.ps1 -Unregister
#>
param(
  [string]$ExePath,
  [switch]$Unregister
)

$ErrorActionPreference = 'Stop'
$progId = 'PERO.Model'
$classes = 'HKCU:\Software\Classes'

if ($Unregister) {
  foreach ($k in @("$classes\.pero", "$classes\$progId")) {
    if (Test-Path $k) { Remove-Item $k -Recurse -Force; Write-Host "削除: $k" }
  }
  Write-Host '関連付けを解除しました。'
  return
}

if (-not $ExePath) { throw '-ExePath に project_er_operation.exe のパスを指定してください。' }
$exe = (Resolve-Path $ExePath).Path

New-Item -Path "$classes\.pero" -Force | Out-Null
Set-ItemProperty -Path "$classes\.pero" -Name '(default)' -Value $progId
New-Item -Path "$classes\$progId" -Force | Out-Null
Set-ItemProperty -Path "$classes\$progId" -Name '(default)' -Value 'PERO ER図'
New-Item -Path "$classes\$progId\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$classes\$progId\DefaultIcon" -Name '(default)' -Value "`"$exe`",0"
New-Item -Path "$classes\$progId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$classes\$progId\shell\open\command" -Name '(default)' -Value "`"$exe`" `"%1`""
Write-Host "関連付けを登録しました: .pero -> $exe"
