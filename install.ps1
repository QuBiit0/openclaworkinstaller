#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw Workspace Installer — Wrapper PowerShell que invoca install.sh
    vía Git Bash (cmd: bash.exe).

.DESCRIPTION
    En Windows, Git Bash viene incluido con Git para Windows.
    Este wrapper detecta bash.exe y ejecuta el install.sh original con los
    argumentos traducidos a formato POSIX.

    Si preferís correr manualmente:
        bash install.sh --mode empresa ...

    Flujo recomendado:
      1. npm install -g openclaw
      2. openclaw setup           ← canal, modelo, tools
      3. .\install.ps1            ← este wrapper → install.sh
      4. openclaw gateway restart

.PARAMETER Mode
    Modo: 'personal' o 'empresa'

.PARAMETER Empresa
    Nombre de la empresa (modo empresa)

.PARAMETER Rubro
    Rubro que sugiere áreas (software, saas, ferreteria, distribuidora, etc.)

.PARAMETER Areas
    Lista de áreas separadas por coma

.PARAMETER OrchestratorId
    ID del agente principal (default: gerencia). Ej: ceo, main, director

.PARAMETER User
    Nombre del responsable principal

.PARAMETER Cargo
    Cargo del usuario (modo empresa)

.PARAMETER TemplatesDir
    Directorio local con plantillas

.PARAMETER TemplatesUrl
    URL base para descargar plantillas remotas

.PARAMETER OpenClawHome
    Override de ~/.openclaw

.PARAMETER NonInteractive
    Sin prompts

.PARAMETER Force
    Sobrescribir sin avisar

.EXAMPLE
    # Wizard interactivo
    .\install.ps1

.EXAMPLE
    # OneFix, no-interactivo
    .\install.ps1 -Mode empresa -Empresa "OneFix" -Rubro saas `
        -OrchestratorId ceo `
        -Areas "dev,research,ops,qa,ventas,atencion-cliente,marketing,contabilidad" `
        -User "Leandro Álvarez" -Cargo "CEO" -NonInteractive

.EXAMPLE
    # One-liner remoto — arranca el wizard INTERACTIVO
    irm https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1 | iex

.EXAMPLE
    # One-liner remoto con parámetros (requiere ScriptBlock para pasar args)
    & ([ScriptBlock]::Create((irm https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1))) -Mode empresa -Empresa "OneFix" -Rubro saas -NonInteractive

.EXAMPLE
    # Alternativa: descargar primero y correr con params
    iwr https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1 -OutFile install.ps1
    .\install.ps1 -Mode empresa -Empresa "OneFix" -NonInteractive
#>

[CmdletBinding()]
param(
    [string]$Mode = '',
    [string]$Empresa,
    [string]$Rubro,
    [string]$Areas,
    [string]$OrchestratorId,
    [string]$User,
    [string]$Cargo,
    [string]$TemplatesDir,
    [string]$TemplatesUrl = 'https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/templates',
    [string]$OpenClawHome,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$WRAPPER_VERSION = '2.3.1'
$REPO_URL = 'https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main'

function Write-Info($m) { Write-Host "[i] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m) {
    Write-Host "[ERROR] $m" -ForegroundColor Red
    # Pausa en ejecucion remota para que el usuario vea el error
    if (-not $PSScriptRoot -and -not $NonInteractive) {
        Write-Host ''
        Write-Host 'Presiona ENTER para cerrar esta ventana...' -ForegroundColor Yellow
        try { [void][Console]::ReadLine() } catch { Start-Sleep -Seconds 30 }
    }
    exit 1
}

Write-Host ''
Write-Host "  OpenClaw Workspace Installer v$WRAPPER_VERSION (PowerShell wrapper)" -ForegroundColor Blue
Write-Host '  delega ejecucion a install.sh via Git Bash' -ForegroundColor DarkGray
Write-Host ''

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

# Validar Mode si vino con valor (permitir vacío para que el wizard lo pregunte)
if ($Mode -and $Mode -notin @('personal', 'empresa')) {
    Die "Mode debe ser 'personal' o 'empresa' (recibido: '$Mode')"
}

# =====================================================================
# 1. Detectar bash.exe (Git Bash o WSL)
# =====================================================================

function Test-BashWorks($path) {
    # Verifica que el bash encontrado realmente funciona (no es un stub roto
    # de WSL sin distro, ni un path que apunta a algo no-ejecutable).
    if (-not $path -or -not (Test-Path $path)) { return $false }
    try {
        $marker = 'OPENCLAW_BASH_OK'
        $out = & $path -c "echo $marker" 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0) -and ($out -match $marker)
    } catch {
        return $false
    }
}

function Find-Bash {
    # Orden de preferencia — Git Bash primero (es lo que recomendamos)
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\usr\bin\bash.exe'
    )
    foreach ($c in $candidates) {
        if (Test-BashWorks $c) {
            return $c
        }
    }

    # Fallback: buscar bash en PATH — PERO rechazar el stub de WSL de Windows
    # Store (C:\Users\...\AppData\Local\Microsoft\WindowsApps\bash.exe) que
    # falla si WSL no tiene distro instalada.
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) {
        $path = $cmd.Source
        # El stub de WSL en WindowsApps da "Subsistema de Windows para Linux
        # no tiene distribuciones instaladas" — saltalo
        if ($path -match 'WindowsApps\\bash\.exe$' -and -not (Test-BashWorks $path)) {
            Write-Host "[!] Detectado stub de WSL sin distro: $path (saltado)" -ForegroundColor Yellow
        } elseif (Test-BashWorks $path) {
            return $path
        }
    }

    return $null
}

$bashExe = Find-Bash
if (-not $bashExe) {
    Die @'
No encuentro un bash funcional en esta VM.

OPCIONES (elegi UNA):

  1) [RECOMENDADO] Instala Git para Windows (~50MB, 2 min):
     https://git-scm.com/download/win

     Viene con Git Bash que incluye bash.exe listo para usar.
     Despues de instalar, cerra y abri PowerShell de nuevo, y corre:
        irm https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1 | iex

  2) Instala WSL con Ubuntu (mas pesado, requiere reinicio):
        wsl --install -d Ubuntu

     Despues corre el instalador desde dentro de WSL:
        curl -fsSL https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.sh | bash

  3) Si ya tenes Git Bash pero no se detecto, verifica donde esta bash:
        Get-Command bash
        Test-Path "C:\Program Files\Git\bin\bash.exe"

Nota: detecte que tenes "bash" en PATH pero es el stub de Microsoft Store
(WSL) que no tiene distro instalada. Ese no sirve — necesitas Git Bash
o WSL con una distro real.
'@
}
Write-Ok "bash detectado y validado: $bashExe"

# =====================================================================
# 2. Localizar install.sh — local o descargar del repo
# =====================================================================

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installSh = Join-Path $scriptDir 'install.sh'

if (-not (Test-Path $installSh)) {
    Write-Info 'install.sh no encontrado localmente — descargando del repo...'
    $installSh = Join-Path $env:TEMP "openclaw_install_$PID.sh"
    try {
        Invoke-WebRequest -Uri "$REPO_URL/install.sh" -OutFile $installSh -UseBasicParsing
        Write-Ok "install.sh descargado a $installSh"
    } catch {
        Die "No pude descargar install.sh desde $REPO_URL/install.sh`n$($_.Exception.Message)"
    }
}

# =====================================================================
# 3. Traducir paths de Windows → POSIX para bash
# =====================================================================

function Convert-ToPosixPath($winPath) {
    if (-not $winPath) { return '' }
    # C:\Users\x → /c/Users/x
    if ($winPath -match '^([A-Za-z]):\\(.*)') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\','/'
        return "/$drive/$rest"
    }
    return ($winPath -replace '\\','/')
}

$installShPosix = Convert-ToPosixPath $installSh

# =====================================================================
# 4. Construir argumentos para install.sh
# =====================================================================

$bashArgs = @($installShPosix)

if ($Mode)           { $bashArgs += '--mode';             $bashArgs += $Mode }
if ($Empresa)        { $bashArgs += '--empresa';          $bashArgs += $Empresa }
if ($Rubro)          { $bashArgs += '--rubro';            $bashArgs += $Rubro }
if ($Areas)          { $bashArgs += '--areas';            $bashArgs += $Areas }
if ($OrchestratorId) { $bashArgs += '--orchestrator-id';  $bashArgs += $OrchestratorId }
if ($User)           { $bashArgs += '--user';             $bashArgs += $User }
if ($Cargo)          { $bashArgs += '--cargo';            $bashArgs += $Cargo }
if ($TemplatesDir)   { $bashArgs += '--templates-dir';    $bashArgs += (Convert-ToPosixPath $TemplatesDir) }
if ($TemplatesUrl)   { $bashArgs += '--templates-url';    $bashArgs += $TemplatesUrl }
if ($OpenClawHome)   { $bashArgs += '--home';             $bashArgs += (Convert-ToPosixPath $OpenClawHome) }
if ($NonInteractive) { $bashArgs += '-y' }
if ($Force)          { $bashArgs += '--force' }

# =====================================================================
# 5. Ejecutar install.sh
# =====================================================================

Write-Info "Ejecutando: bash $($bashArgs -join ' ')"
Write-Host ''

# Detectar si estamos en ejecucion remota (irm | iex) — en ese caso,
# pausamos al final para que el usuario pueda ver el output antes de
# que la ventana se cierre automaticamente.
$RemoteExec = -not $PSScriptRoot

try {
    & $bashExe $bashArgs
    $exitCode = $LASTEXITCODE
} catch {
    $exitCode = 1
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
if ($exitCode -eq 0) {
    Write-Host '[OK] Instalacion completada' -ForegroundColor Green
} else {
    Write-Host "[ERROR] install.sh fallo con exit code $exitCode" -ForegroundColor Red
}

# Pausa SOLO si estamos en ejecucion remota (irm | iex) y la ventana
# podria cerrarse. Evita perder el output.
if ($RemoteExec -and -not $NonInteractive) {
    Write-Host ''
    Write-Host '─────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host 'Presiona ENTER para cerrar esta ventana...' -ForegroundColor Yellow
    try { [void][Console]::ReadLine() } catch { Start-Sleep -Seconds 30 }
}

exit $exitCode
