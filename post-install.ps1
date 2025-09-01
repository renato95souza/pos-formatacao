# inicial.ps1

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThruArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===================== LISTA DE PACOTES (EDITÁVEL) =====================
$Packages = @(
    'nano'
    'advanced-ip-scanner',
    'putty',
    'python',
    'yt-dlp',
    'ffmpeg',
    'flameshot',
    'adobereader',
    'firefox',
    'python3',
    'teamviewer',
    'notepadplusplus.install',
    'bitwarden',
    'mobaxterm',
    'vlc',
    'winrar',
    'wget',
    'spotify',
    'powertoys',
    'forticlientvpn',
    'rufus',
    'virtualbox'
)
# =======================================================================

#region ===== Instalação do PyWin32 via pip =====
function Ensure-PyWin32 {
    Write-Info "Verificando instalação do pywin32 via pip..."

    # Testa se Python Launcher está disponível
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if (-not $pyCmd) {
        Write-Err "Python Launcher 'py' não encontrado. Certifique-se de que o pacote 'python3' foi instalado via Chocolatey."
        return
    }

    try {
        $check = & py -m pip show pywin32 2>$null
        if ($LASTEXITCODE -eq 0 -and $check) {
            # Já instalado
            $verLine = ($check -split "`n" | Where-Object { $_ -like "Version:*" }) -replace "Version:\s*",""
            Write-Ok "pywin32 já instalado (versão $verLine)."
            return
        }
    } catch { }

    Write-Info "Instalando pywin32 via pip..."
    $res = Invoke-ProcessSilent -FilePath 'py' -ArgumentList @('-m','pip','install','pywin32')

    if ($res.ExitCode -ne 0) {
        Write-Err "Falha ao instalar pywin32:"
        if ($res.StdErr) { Write-Host $res.StdErr }
        elseif ($res.StdOut) { Write-Host $res.StdOut }
        else { Write-Host "(sem saída de erro; código $($res.ExitCode))" }
        return
    }

    # Confirmação final
    $check = & py -m pip show pywin32 2>$null
    if ($LASTEXITCODE -eq 0 -and $check) {
        $verLine = ($check -split "`n" | Where-Object { $_ -like "Version:*" }) -replace "Version:\s*",""
        Write-Ok "pywin32 instalado com sucesso (versão $verLine)."
    } else {
        Write-Err "Não foi possível confirmar a instalação do pywin32."
    }
}
#endregion

#region ===== Console / Encoding / Mensagens =====
function Set-ConsoleUtf8 {
    try {
        if ($Host.Name -eq 'ConsoleHost') { chcp 65001 > $null }
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        if ([Console]::InputEncoding.EncodingName -ne "Unicode (UTF-8)") {
            [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        }
        $script:Glyphs = $true
    } catch { $script:Glyphs = $false }
}

function Write-Ok   { param([string]$m) if ($script:Glyphs) { Write-Host "✅ $m" -ForegroundColor Green } else { Write-Host "[OK] $m" -ForegroundColor Green } }
function Write-Warn { param([string]$m) if ($script:Glyphs) { Write-Host "⚠ $m"  -ForegroundColor Yellow } else { Write-Host "[WARN] $m" -ForegroundColor Yellow } }
function Write-Err  { param([string]$m) if ($script:Glyphs) { Write-Host "❌ $m" -ForegroundColor Red }  else { Write-Host "[ERRO] $m" -ForegroundColor Red } }
function Write-Info { param([string]$m) if ($script:Glyphs) { Write-Host "ℹ️ $m"  -ForegroundColor Cyan }  else { Write-Host "[INFO] $m" -ForegroundColor Cyan } }

function Pause-Enter { [void](Read-Host "Pressione Enter para sair...") }
#endregion

#region ===== Admin / Elevação =====
function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = [Security.Principal.WindowsPrincipal]::new($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-AsAdministrator {
    param([string[]]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "powershell.exe"

    $quotedArgs = @()
    foreach ($a in ($Arguments | ForEach-Object { $_ })) {
        $quotedArgs += ('"'+ ($a -replace '"','\"') +'"')
    }

    # Prepara o ambiente em UTF-8 e executa o script elevado; -NoExit mantém a janela aberta
    $prep = @(
        'chcp 65001 > $null',
        '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8',
        '[Console]::InputEncoding  = [System.Text.Encoding]::UTF8',
        ('& "{0}" {1}' -f $PSCommandPath, ($quotedArgs -join ' '))
    ) -join '; '

    $psi.Arguments = "-NoExit -NoProfile -ExecutionPolicy Bypass -Command $prep"
    $psi.Verb      = "runas"
    $psi.UseShellExecute = $true

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit 0
    } catch {
        Write-Err "Execução cancelada. Este script requer privilégios de administrador."
        exit 1
    }
}

function Ensure-Administrator {
    if (-not (Test-IsAdministrator)) {
        Write-Warn "Este script precisa ser executado como Administrador. Tentando reiniciar elevado..."
        Restart-AsAdministrator -Arguments $PassThruArgs
    } else {
        Write-Ok "Privilégios de administrador confirmados."
    }
}
#endregion

#region ===== Chocolatey (detectar/instalar) =====
function Test-ChocolateyInstalled {
    try {
        $cmd = Get-Command choco -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $true }
        return (Test-Path 'C:\ProgramData\chocolatey\bin\choco.exe')
    } catch { return $false }
}

function Get-ChocolateyVersion {
    try {
        $ver = choco --version 2>$null
        if ([string]::IsNullOrWhiteSpace($ver)) { return $null }
        return $ver.Trim()
    } catch { return $null }
}

function Install-Chocolatey {
@"
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
"@ | Out-Null

    Write-Warn "Chocolatey não encontrado. Iniciando instalação..."

    $oneLiner = @'
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
'@

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = "powershell.exe"
    $psi.Verb      = "runas"
    $psi.Arguments = "-NoExit -NoProfile -ExecutionPolicy Bypass -Command ""$oneLiner; Read-Host 'Pressione Enter para sair do instalador...'"""
    $psi.UseShellExecute = $true

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "Instalador do Chocolatey retornou código $($p.ExitCode)." }
    } catch {
        Write-Err "Falha ao instalar o Chocolatey: $($_.Exception.Message)"
        throw
    }

    try {
        $machinePath = [Microsoft.Win32.Registry]::GetValue(
            'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment','Path',$null)
        $userPath = [Microsoft.Win32.Registry]::GetValue(
            'HKEY_CURRENT_USER\Environment','Path',$null)
        [System.Environment]::SetEnvironmentVariable('Path', @($machinePath,$userPath) -join ';','Process')
    } catch { }

    Start-Sleep -Seconds 2

    $ver = Get-ChocolateyVersion
    if (-not $ver) {
        $fallback = 'C:\ProgramData\chocolatey\bin\choco.exe'
        if (Test-Path $fallback) { $ver = & $fallback --version 2>$null }
    }

    if ($ver) { Write-Ok "Chocolatey instalado com sucesso. Versão: $ver" }
    else      { Write-Err "Não foi possível confirmar a instalação do Chocolatey."; throw "Chocolatey não detectado após instalação." }
}

function Ensure-Chocolatey {
    if (Test-ChocolateyInstalled) {
        $ver = Get-ChocolateyVersion
        if ($ver) { Write-Ok "Chocolatey já instalado. Versão: $ver" } else { Write-Ok "Chocolatey já instalado." }
        return
    }
    Install-Chocolatey
}
#endregion

#region ===== Instalação silenciosa de pacotes (com coleta de falhas) =====
$script:Failures = New-Object System.Collections.Generic.List[object]

function Get-ChocoInstalledVersion {
    param([Parameter(Mandatory)][string]$Name)
    $out = & choco list --local-only --exact --limit-output $Name 2>$null
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    $parts = $out.Trim() -split '\|'
    if ($parts.Length -ge 2) { return $parts[1].Trim() } else { return $null }
}

function Invoke-ProcessSilent {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )
    $tempOut = [System.IO.Path]::GetTempFileName()
    $tempErr = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr `
            -NoNewWindow -Wait -PassThru
        $stdout = (Get-Content $tempOut -Raw -ErrorAction SilentlyContinue)
        $stderr = (Get-Content $tempErr -Raw -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            ExitCode = $p.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    } finally {
        Remove-Item $tempOut,$tempErr -ErrorAction SilentlyContinue
    }
}

function Add-Failure {
    param([string]$Name,[string]$Message,[int]$ExitCode)
    $script:Failures.Add([pscustomobject]@{
        Package  = $Name
        ExitCode = $ExitCode
        Reason   = $Message
    })
}

function Install-ChocoPackage {
    param([Parameter(Mandatory)][string]$Name)

    $installedVer = Get-ChocoInstalledVersion -Name $Name
    if ($installedVer) {
        Write-Ok "Já instalado: $Name v$installedVer"
        return
    }

    Write-Info "Instalando ${Name}..."

    $res = Invoke-ProcessSilent -FilePath 'choco' -ArgumentList @('install', $Name, '-y', '--no-progress', '--limit-output')

    if ($res.ExitCode -ne 0) {
        $msg = if (-not [string]::IsNullOrWhiteSpace($res.StdErr)) { $res.StdErr } elseif (-not [string]::IsNullOrWhiteSpace($res.StdOut)) { $res.StdOut } else { "(sem saída de erro; código $($res.ExitCode))" }
        Write-Err "Erro ao instalar ${Name}:"
        Write-Host $msg
        Add-Failure -Name $Name -Message $msg -ExitCode $res.ExitCode
        return
    }

    $newVer = Get-ChocoInstalledVersion -Name $Name
    if ($newVer) { Write-Ok "Instalado: $Name v$newVer" }
    else {
        Write-Err "Instalação de ${Name} concluída, mas não foi possível confirmar a versão."
        Add-Failure -Name $Name -Message "Instalado sem confirmação de versão." -ExitCode 0
    }
}

function Install-ChocoPackageList {
    param([string[]]$Names)

    $cInstalled = 0; $cSkipped = 0

    foreach ($pkg in $Names) {
        try {
            $v = Get-ChocoInstalledVersion -Name $pkg
            if ($v) {
                Write-Ok "Já instalado: $pkg v$v"
                $cSkipped++
                continue
            }

            Write-Info "Instalando ${pkg}..."

            $res = Invoke-ProcessSilent -FilePath 'choco' -ArgumentList @('install', $pkg, '-y', '--no-progress', '--limit-output')
            if ($res.ExitCode -ne 0) {
                $msg = if (-not [string]::IsNullOrWhiteSpace($res.StdErr)) { $res.StdErr } elseif (-not [string]::IsNullOrWhiteSpace($res.StdOut)) { $res.StdOut } else { "(sem saída de erro; código $($res.ExitCode))" }
                Write-Err "Erro ao instalar ${pkg}:"
                Write-Host $msg
                Add-Failure -Name $pkg -Message $msg -ExitCode $res.ExitCode
                continue
            }

            $v2 = Get-ChocoInstalledVersion -Name $pkg
            if ($v2) {
                Write-Ok "Instalado: $pkg v$v2"
                $cInstalled++
            } else {
                Write-Err "Instalação de ${pkg} concluída, mas versão não confirmada."
                Add-Failure -Name $pkg -Message "Instalado sem confirmação de versão." -ExitCode 0
            }
        } catch {
            Write-Err "Exceção ao processar ${pkg}: $($_.Exception.Message)"
            Add-Failure -Name $pkg -Message $_.Exception.Message -ExitCode -1
        }
    }

    Write-Host ""
    Write-Host "==== Resumo ===="
    Write-Host ("Instalados:    {0}" -f $cInstalled)
    Write-Host ("Já instalados: {0}" -f $cSkipped)
    Write-Host ("Falhas:        {0}" -f $($script:Failures.Count))

    if ($script:Failures.Count -gt 0) {
        Write-Host ""
        Write-Host "==== Detalhes das falhas ===="
        foreach ($f in $script:Failures) {
            Write-Host ("- {0}  (ExitCode: {1})" -f $f.Package, $f.ExitCode)
            Write-Host ($f.Reason.Trim())
            Write-Host ""
        }
    }
}
#endregion

#region ===== MAIN =====
function Invoke-Main {
    Set-ConsoleUtf8
    Ensure-Administrator
    Ensure-Chocolatey
    Install-ChocoPackageList -Names $Packages
    Ensure-PyWin32
}

try {
    Invoke-Main
} finally {
    Pause-Enter   # <-- garante pausa SEMPRE (sucesso ou erro)
}
#endregion
