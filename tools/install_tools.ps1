# Pazulu Reader - installation des outils de compilation (une seule fois)
#
# Installe, si absent : Git, Flutter (dans %USERPROFILE%\dev\flutter),
# Visual Studio 2022 Community (C++ Desktop), et active
# le mode developpeur Windows. Des fenetres d'autorisation (UAC) vont
# s'ouvrir : cliquez "Oui".
#
# Journal : dist\install-log.txt

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
Start-Transcript -Path (Join-Path $root 'dist\install-log.txt') -Force | Out-Null

$problems = @()

function Step($m) { Write-Host ''; Write-Host "=== $m ===" -ForegroundColor Cyan }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Winget-Install($id, $label, $extra = @()) {
    $found = winget list --id $id -e --accept-source-agreements 2>$null | Select-String $id
    if ($found) {
        Write-Host "$label : deja installe." -ForegroundColor Green
        return $true
    }
    Write-Host "$label : installation (cela peut prendre du temps)..."
    $wargs = @('install', '--id', $id, '-e', '--accept-package-agreements', '--accept-source-agreements') + $extra
    & winget @wargs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$label : echec (code $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }
    Write-Host "$label : installe." -ForegroundColor Green
    return $true
}

try {
    Step 'Verification de winget'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget est absent. Installez 'App Installer' depuis le Microsoft Store puis relancez."
    }

    Step 'Git'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        if (-not (Winget-Install 'Git.Git' 'Git')) { $problems += 'Git' }
        Refresh-Path
    } else { Write-Host 'Git : deja installe.' -ForegroundColor Green }

    Step 'Flutter'
    $flutterDir = Join-Path $env:USERPROFILE 'dev\flutter'
    $flutterBin = Join-Path $flutterDir 'bin'
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        Write-Host 'Flutter : deja installe.' -ForegroundColor Green
    } else {
        if (-not (Test-Path (Join-Path $flutterBin 'flutter.bat'))) {
            New-Item -ItemType Directory -Force -Path (Split-Path $flutterDir) | Out-Null
            Write-Host "Telechargement de Flutter (stable) dans $flutterDir ..."
            git clone https://github.com/flutter/flutter.git -b stable $flutterDir | Out-Host
            if ($LASTEXITCODE -ne 0) { $problems += 'Flutter (telechargement)' }
        }
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$flutterBin*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$flutterBin", 'User')
            Write-Host 'Flutter ajoute au PATH utilisateur.'
        }
        Refresh-Path
    }

    Step 'Visual Studio 2022 Community (C++ Desktop)'
    $vsOverride = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended'
    if (-not (Winget-Install 'Microsoft.VisualStudio.2022.Community' 'Visual Studio 2022' @('--override', $vsOverride))) {
        $problems += 'Visual Studio 2022'
    }

    Step 'NuGet (lecteur officiel integre)'
    if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
        if (-not (Winget-Install 'Microsoft.NuGet' 'NuGet')) { $problems += 'NuGet' }
    } else { Write-Host 'NuGet : deja installe.' -ForegroundColor Green }

    Step 'Mode developpeur Windows (liens symboliques pour les plugins Flutter)'
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $current = (Get-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    if ($current -eq 1) {
        Write-Host 'Mode developpeur : deja actif.' -ForegroundColor Green
    } else {
        $p = Start-Process reg -Verb RunAs -Wait -PassThru -ArgumentList 'add', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock', '/t', 'REG_DWORD', '/f', '/v', 'AllowDevelopmentWithoutDevLicense', '/d', '1'
        if ($p.ExitCode -eq 0) { Write-Host 'Mode developpeur : active.' -ForegroundColor Green }
        else { $problems += 'Mode developpeur'; Write-Host 'Mode developpeur : echec.' -ForegroundColor Red }
    }

    Step 'Premier lancement de Flutter'
    Refresh-Path
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        flutter config --no-analytics | Out-Host
        flutter --version | Out-Host
        flutter doctor | Out-Host
    } else {
        $problems += 'Flutter introuvable apres installation'
    }
}
catch {
    Write-Host "ARRET : $_" -ForegroundColor Red
    $problems += "$_"
}
finally {
    Write-Host ''
    if ($problems.Count -eq 0) {
        Write-Host 'Outils installes.' -ForegroundColor Green
    } else {
        Write-Host 'Problemes :' -ForegroundColor Yellow
        $problems | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host 'Etape suivante : lancer Compiler-Windows.cmd.' -ForegroundColor Cyan
    Stop-Transcript | Out-Null
}
