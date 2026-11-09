# Repacks the already-built Windows directory. Does not run Flutter or tests.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$out = Join-Path $dist 'PazuluReader-1.0.0-windows'
$release = Join-Path $root 'build\windows\x64\runner\Release'
$zip = "$out.zip"
try {
    if (-not (Test-Path (Join-Path $release 'pazulu_reader.exe'))) {
        throw "Compilation introuvable dans $release : lancez Compiler-Windows.cmd d'abord."
    }
    if (Get-Process -Name 'pazulu_reader' -ErrorAction SilentlyContinue) {
        throw 'Fermez completement Pazulu Reader avant de recreer le ZIP.'
    }
    # Always re-stage the latest release: the previous packaging may have failed.
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Copy-Item $release $out -Recurse -ErrorAction Stop
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -ErrorAction Stop
    Write-Host "ZIP cree : $zip" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "Echec du packaging : $_" -ForegroundColor Red
    exit 1
}
