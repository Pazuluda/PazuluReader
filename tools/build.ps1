# Pazulu Reader - compilation Windows uniquement (EXE)
#
# Utilisation (PowerShell, depuis n'importe ou) :
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1
# Options :
#   -SkipWindows   ne pas compiler la version Windows
#   -SkipTests     ne pas lancer les tests
#
# Le journal complet est ecrit dans dist\build-log.txt : envoyez-le si un probleme survient.

param(
    [switch]$SkipWindows,
    [switch]$SkipTests
)

# 'Continue' : les messages d'erreur de flutter (stderr) ne doivent pas interrompre le script ;
# chaque etape verifie elle-meme son code de sortie.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
New-Item -ItemType Directory -Force -Path dist | Out-Null
Start-Transcript -Path (Join-Path $root 'dist\build-log.txt') -Force | Out-Null

$version = '1.0.0'
$failures = @()

function Step($message) {
    Write-Host ''
    Write-Host "=== $message ===" -ForegroundColor Cyan
}

function Run($label, [scriptblock]$command) {
    & $command | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$label a echoue (code $LASTEXITCODE). Voir dist\build-log.txt"
    }
}

# L'Explorateur garde l'ancien PATH apres une installation : on relit celui du systeme.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$localFlutter = Join-Path $env:USERPROFILE 'dev\flutter\bin'
if ((Test-Path $localFlutter) -and ($env:Path -notlike "*$localFlutter*")) { $env:Path += ";$localFlutter" }

try {
    Step 'Verification de Flutter'
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter est introuvable. Installez-le (voir README.md, section Installation) puis relancez ce script."
    }
    Run 'flutter --version' { flutter --version }
    flutter doctor -v | Out-Host

    if (-not (Test-Path 'windows')) {
        Step 'Generation du projet Windows uniquement'
        Run 'flutter create' { flutter create --platforms=windows --org com.pazulu --project-name pazulu_reader . }
        if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' }
    }

    Step 'Configuration des plateformes'
    & (Join-Path $PSScriptRoot 'configure_platforms.ps1')

    Step 'Telechargement des dependances'
    Run 'flutter pub get' { flutter pub get }

    Step 'Analyse statique'
    flutter analyze --no-fatal-infos --no-fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { $failures += 'analyse (erreurs de code, voir le journal)' }

    if (-not $SkipTests) {
        Step 'Tests automatises'
        flutter test | Out-Host
        if ($LASTEXITCODE -ne 0) { $failures += 'tests' }
    }

    if (-not $SkipWindows) {
        Step 'Compilation Windows'
        # La WebView2 native utilise les dependances Windows du plugin. NuGet peut etre requis.
        if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
            Write-Host 'Installation de NuGet (necessaire au lecteur officiel)...'
            winget install --id Microsoft.NuGet -e --accept-package-agreements --accept-source-agreements | Out-Host
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        }
        flutter build windows --release | Out-Host
        if ($LASTEXITCODE -ne 0) {
            $failures += 'compilation Windows'
        } else {
            # Never remove/copy an existing portable distribution while its EXE is open.
            $out = Join-Path $root "dist\PazuluReader-$version-windows"
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package_windows.ps1') | Out-Host
            $packaged = $LASTEXITCODE -eq 0
            if (-not $packaged) {
                $failures += 'packaging Windows (fermer Pazulu Reader puis utiliser Packager-Windows.cmd)'
            }
            if ($packaged) {
            $iscc = @(
                "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
                "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($iscc) {
                & $iscc "/DAppVersion=$version" "/DSourceDir=$out" (Join-Path $PSScriptRoot 'installer.iss') | Out-Host
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Installateur : dist\PazuluReader-$version-setup.exe" -ForegroundColor Green
                } else {
                    $failures += 'installateur Inno Setup'
                }
            } else {
                Write-Host "Inno Setup non installe : pas d'installateur EXE (la version portable fonctionne)." -ForegroundColor Yellow
            }
            }
        }
    }


}
catch {
    Write-Host ''
    Write-Host "ARRET : $_" -ForegroundColor Red
    $failures += "$_"
}
finally {
    Write-Host ''
    if ($failures.Count -eq 0) {
        Write-Host 'Termine sans erreur. Les fichiers sont dans le dossier dist.' -ForegroundColor Green
    } else {
        Write-Host 'Termine avec des problemes :' -ForegroundColor Yellow
        $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
        Write-Host 'Envoyez dist\build-log.txt pour correction.' -ForegroundColor Yellow
    }
    Stop-Transcript | Out-Null
}
