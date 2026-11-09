# Ajustements apres "flutter create" pour Windows uniquement. Idempotent : peut etre relance sans risque.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding $false

function Patch-File($path, [scriptblock]$transform) {
    if (-not (Test-Path $path)) {
        Write-Host "Absent (ignore) : $path" -ForegroundColor Yellow
        return
    }
    $text = [System.IO.File]::ReadAllText($path)
    $new = & $transform $text
    if ($new -ne $text) {
        [System.IO.File]::WriteAllText($path, $new, $utf8)
        Write-Host "Modifie : $path"
    } else {
        Write-Host "Deja a jour : $path"
    }
}

# --- Windows ---------------------------------------------------------------
$mainCpp = Join-Path $root 'windows\runner\main.cpp'
Patch-File $mainCpp {
    param($t)
    $t = $t.Replace('L"pazulu_reader"', 'L"Pazulu Reader"')
    $t = $t.Replace('Win32Window::Size size(1280, 720);', 'Win32Window::Size size(1360, 860);')
    return $t
}

# Icone de l'application (.exe, fenetre, barre des taches)
$icon = Join-Path $root 'assets\icon\app_icon.ico'
$target = Join-Path $root 'windows\runner\resources\app_icon.ico'
if ((Test-Path $icon) -and (Test-Path (Split-Path $target -Parent))) {
    Copy-Item $icon $target -Force
    Write-Host "Icone : $target"
}
