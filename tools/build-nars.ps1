<#
.SYNOPSIS
  ゴースト本体と追加シェル（サンプル）の nar を、SSP のオフラインツールで build/ に作る。

.DESCRIPTION
  ssp.exe --offline-tool nar を使う（SSP 2.9.01 以降）。
  SSP のフォルダのドラッグ＆ドロップで作る nar と同じ形式になる。

  * ゴースト本体：リポジトリのルートを対象にする。
    .narignore（ルート直下）の内容が適用され、profile/ は SSP が自動で除外する。
    出力は <install.txt の directory>.nar（例：lnx_ukaclock.nar）。
  * 追加シェル：shell/<名前>/ を対象にする。出力は <名前>.nar。
    シェルのフォルダ直下に .narignore を置けば、その内容も適用される。

  ゴースト本体の nar を作る前に、ネットワーク更新ファイルを作り直す（-SkipUpdateData で省略）。
    * updates2.dau と updates.txt を、リポジトリのルートと ghost/master/ の両方に書き出す。
    * 内容は .updateignore（ルート直下）の除外が適用される。
    * nar には、作り直したこれらのファイルが入る。

.PARAMETER SspPath
  ssp.exe のパス。省略時は環境変数 SSP_PATH を使う。

.PARAMETER Shells
  nar にするシェルのフォルダ名（shell/ 以下）。

.PARAMETER SkipGhost
  ゴースト本体の nar を作らない。

.PARAMETER SkipUpdateData
  ネットワーク更新ファイル（updates2.dau / updates.txt）を作り直さない。

.PARAMETER OutDir
  nar の出力先。省略時は <リポジトリのルート>/build。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-nars.ps1 -SspPath D:\ssp\ssp.exe
#>
param(
	[string]$SspPath = $env:SSP_PATH,
	[string[]]$Shells = @('digital_seconds', 'sample_analog_seconds'),
	[switch]$SkipGhost,
	[switch]$SkipUpdateData,
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

# 作る nar の一覧（対象フォルダ, 出力名）
$jobs = @()

if (-not $SkipGhost) {
	$installTxt = Join-Path $root 'install.txt'
	if (-not (Test-Path -LiteralPath $installTxt)) {
		Write-Error 'install.txt がありません。'
		exit 1
	}
	# install.txt は Shift_JIS だが、directory の値は半角英数なので Latin1 として読んでよい
	$raw = [IO.File]::ReadAllText($installTxt, [Text.Encoding]::GetEncoding('iso-8859-1'))
	if ($raw -notmatch '(?m)^directory,([^\r\n]+)') {
		Write-Error 'install.txt に directory の指定がありません。'
		exit 1
	}
	$jobs += , @($root, $Matches[1].Trim())
}

foreach ($name in $Shells) {
	$jobs += , @((Join-Path $root "shell\$name"), $name)
}

$failed = 0

# ネットワーク更新ファイル（ゴースト本体の nar に入れるので、nar より先に作る）
if (-not $SkipGhost -and -not $SkipUpdateData) {
	$files = @('updates2.dau', 'updates.txt')
	foreach ($file in $files) {
		# 出力先がリポジトリ内でも、SSP は対象フォルダ直下・ghost\master の updates 系ファイルを収録しない
		$output = Join-Path $root $file
		$argList = @('--offline-tool', 'updatedata', '--target-dir', "`"$root`"", '--output', "`"$output`"")
		$p = Start-Process -FilePath $SspPath -ArgumentList $argList -Wait -PassThru
		if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
			Write-Warning "$file : 作成に失敗しました（終了コード $($p.ExitCode)）。"
			$failed++
			continue
		}
		# ghost/master/ にも同じものを置く
		Copy-Item -LiteralPath $output -Destination (Join-Path $root "ghost\master\$file") -Force
		Write-Host "$file -> ルートと ghost/master/"
	}
}

foreach ($job in $jobs) {
	$target = $job[0]
	$name = $job[1]
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
