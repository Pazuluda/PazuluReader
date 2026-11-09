# Pazulu Reader - diagnostic des plantages (lecture seule, ne modifie rien)
# Ecrit dist\diagnostic.txt : derniers plantages de pazulu_reader.exe
# (journal Windows), version de WebView2, fin du journal pazulu.log.

$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
$out = Join-Path $root 'dist\diagnostic.txt'
$lines = @()
$lines += "Diagnostic Pazulu Reader - $(Get-Date -Format s)"
$lines += "Windows : $([Environment]::OSVersion.VersionString)"
$lines += ''
$lines += '=== Plantages recents (journal Application, evenements 1000, 1001 et 1026) ==='
try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001, 1026 } -MaxEvents 200 -ErrorAction Stop |
        Where-Object { $_.Message -like '*pazulu_reader*' } | Select-Object -First 5
    if ($events) {
        foreach ($e in $events) { $lines += "--- $($e.TimeCreated) (id $($e.Id))"; $lines += $e.Message; $lines += '' }
    } else { $lines += 'Aucun plantage de pazulu_reader.exe trouve.' }
} catch { $lines += "Lecture du journal impossible : $_" }
$lines += ''
$lines += '=== WebView2 ==='
$wv = @(
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
  'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
) | ForEach-Object { (Get-ItemProperty -Path $_ -Name pv -ErrorAction SilentlyContinue).pv } | Where-Object { $_ }
if ($wv) { $lines += "Version : $($wv -join ', ')" } else { $lines += 'WebView2 introuvable dans le registre.' }
$lines += ''
$lines += '=== Garde anti-crash WebView V0.4.2 ==='
$guard = Join-Path $env:APPDATA 'com.pazulu\pazulu_reader\webview-v042-active.flag'
if (Test-Path $guard) {
    $lines += 'Marqueur present (plantage possible ou fermeture forcee pendant la lecture).'
    $lines += Get-Content $guard -ErrorAction SilentlyContinue
} else {
    $lines += 'Aucun marqueur dans le chemin standard du profil.'
}
$lines += ''
$lines += '=== Fin de pazulu.log ===' 
$log = Join-Path $env:APPDATA 'com.pazulu\pazulu_reader\pazulu.log'
if (Test-Path $log) { $lines += Get-Content $log -Tail 60 } else { $lines += "Absent : $log" }
$lines | Out-File -FilePath $out -Encoding utf8
Write-Host "Diagnostic ecrit dans : $out" -ForegroundColor Green
Write-Host 'Envoyez ce fichier pour diagnostic.'
