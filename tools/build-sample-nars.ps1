<#
.SYNOPSIS
  追加シェル（サンプル）の nar を、SSP のオフラインツールで build/ に作る。

.DESCRIPTION
  ssp.exe --offline-tool nar を使う（SSP 2.9.01 以降）。
  SSP のシェルフォルダのドラッグ＆ドロップで作る nar と同じ形式になる。
  profile/ は SSP が自動で除外する。
  ゴースト本体の nar は対象外（ネットワーク更新に入れない追加シェルだけを作る）。

.PARAMETER SspPath
  ssp.exe のパス。省略時は環境変数 SSP_PATH を使う。

.PARAMETER Shells
  nar にするシェルのフォルダ名（shell/ 以下）。

.PARAMETER OutDir
  nar の出力先。省略時は <リポジトリのルート>/build。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-sample-nars.ps1 -SspPath D:\ssp\ssp.exe
#>
param(
	[string]$SspPath = $env:SSP_PATH,
	[string[]]$Shells = @('digital_seconds', 'sample_analog_seconds'),
	[string]$OutDir
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutDir) { $OutDir = Join-Path $root 'build' }

if (-not $SspPath -or -not (Test-Path -LiteralPath $SspPath)) {
	Write-Error 'ssp.exe が見つかりません。-SspPath か環境変数 SSP_PATH で指定してください。'
	exit 3
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$failed = 0
foreach ($name in $Shells) {
	$target = Join-Path $root "shell\$name"
	$output = Join-Path $OutDir "$name.nar"

	if (-not (Test-Path -LiteralPath (Join-Path $target 'install.txt'))) {
		Write-Warning "$name : install.txt がありません。スキップします。"
		$failed++
		continue
	}

	# SSP は GUI アプリなので、-Wait で終了を待ってから終了コードを見る
	$argList = @('--offline-tool', 'nar', '--target-dir', "`"$target`"", '--output', "`"$output`"")
	$p = Start-Process -FilePath $SspPath -ArgumentList $argList -Wait -PassThru
	if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
		Write-Warning "$name : nar の作成に失敗しました（終了コード $($p.ExitCode)）。"
		$failed++
		continue
	}
	Write-Host ("{0} -> {1} ({2:N0} bytes)" -f $name, $output, (Get-Item -LiteralPath $output).Length)
}

if ($failed -gt 0) { exit 1 }
