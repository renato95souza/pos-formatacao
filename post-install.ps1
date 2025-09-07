#requires -Version 5.1
<#!
    Script:    post-install.ps1
    Autor:     Renato de Souza de Carvalho ;)
    Objetivo:  Utilitário pós-formatação com menu e funções
    Idioma:    pt-BR
!#>

# Lista de pacotes Winget
$Global:WingetPackages = @(
    'GNU.Nano',
    'Famatech.AdvancedIPScanner',
    'PuTTY.PuTTY',
    'Python.Python.3.13',
    'yt-dlp.yt-dlp',
    'Gyan.FFmpeg',
    'Flameshot.Flameshot',
    'Adobe.Acrobat.Reader.64-bit',
    'Mozilla.Firefox.pt-BR',
    'TeamViewer.TeamViewer',
    'Notepad++.Notepad++',
    'Bitwarden.Bitwarden',
    'Mobatek.MobaXterm',
    'VideoLAN.VLC',
    'RARLab.WinRAR',
    'GNU.Wget2',
    'Spotify.Spotify',
    'Microsoft.PowerToys',
    'Fortinet.FortiClientVPN',
    'Rufus.Rufus',
    'Oracle.VirtualBox',
    'KeeperSecurity.KeeperDesktop',
    'RevoUninstaller.RevoUninstaller'
)

# Lista de pacotes para instalar via chocolatey, caso não esteja disponível via winget
$Global:ChocoPackages = @(
    'partition-manager'
)
# ====================================================

#region Utilidades básicas

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERRO]  $msg" -ForegroundColor Red }

function Pause-Enter {
    Write-Host ""; Write-Host "Pressione ENTER para continuar..." -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ensure-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Warn "Este script precisa ser executado como Administrador. Reabrindo elevado..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Process -Id $PID).Path
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        try {
            [Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            Write-Err "Execução cancelada. Este script requer privilégios de administrador."
        }
        exit
    }
}

#endregion Utilidades básicas

#region Restauração do Sistema

function CreateSystemRestorePoint {
    Write-Output "> Attempting to create a system restore point..."
    
    $SysRestore = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "RPSessionInterval"

    if ($SysRestore.RPSessionInterval -eq 0) {
        if ($Silent -or $( Read-Host -Prompt "System restore is disabled, would you like to enable it and create a restore point? (y/n)") -eq 'y') {
            $enableSystemRestoreJob = Start-Job { 
                try {
                    Enable-ComputerRestore -Drive "$env:SystemDrive"
                } catch {
                    Write-Host "Error: Failed to enable System Restore: $_" -ForegroundColor Red
                    Write-Output ""
                    return
                }
            }
    
            $enableSystemRestoreJobDone = $enableSystemRestoreJob | Wait-Job -TimeOut 20

            if (-not $enableSystemRestoreJobDone) {
                Write-Host "Error: Failed to enable system restore and create restore point, operation timed out" -ForegroundColor Red
                Write-Output ""
                Write-Output "Press any key to continue anyway..."
                $null = [System.Console]::ReadKey()
                return
            } else {
                Receive-Job $enableSystemRestoreJob
            }
        } else {
            Write-Output ""
            return
        }
    }

    $createRestorePointJob = Start-Job { 
        try {
            $recentRestorePoints = Get-ComputerRestorePoint | Where-Object { (Get-Date) - [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -le (New-TimeSpan -Hours 24) }
        } catch {
            Write-Host "Error: Unable to retrieve existing restore points: $_" -ForegroundColor Red
            Write-Output ""
            return
        }
    
        if ($recentRestorePoints.Count -eq 0) {
            try {
                Checkpoint-Computer -Description "Restore point created by Win11Debloat" -RestorePointType "MODIFY_SETTINGS"
                Write-Output "System restore point created successfully"
            } catch {
                Write-Host "Error: Unable to create restore point: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "A recent restore point already exists, no new restore point was created." -ForegroundColor Yellow
        }
    }
    
    $createRestorePointJobDone = $createRestorePointJob | Wait-Job -TimeOut 20

    if (-not $createRestorePointJobDone) {
        Write-Host "Error: Failed to create system restore point, operation timed out" -ForegroundColor Red
        Write-Output ""
        Write-Output "Press any key to continue anyway..."
        $null = [System.Console]::ReadKey()
    } else {
        Receive-Job $createRestorePointJob
    }

    Write-Output ""
}

#endregion Restauração do Sistema

#region Windebloat

function Run-Windebloat {
    Write-Info "Executando Windebloat com parâmetros padrão..."
    try {
        & ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -RunDefaults
        Write-Ok "Windebloat concluído."
    } catch {
        Write-Warn "Falha ao executar Windebloat: $($_.Exception.Message)"
    }
}

#endregion Windebloat

#region Sudo no Windows 11

function Enable-WindowsSudo {
    Write-Info "Habilitando 'sudo' no Windows 11 (modo normal)..."
    try {
        sudo config --enable normal
        Write-Ok "'sudo' habilitado."
    } catch {
        Write-Warn "Falha ao habilitar 'sudo'. Verifique se o recurso está disponível nesta versão do Windows. Detalhe: $($_.Exception.Message)"
    }
}

#endregion Sudo

#region Chocolatey

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Ok "Chocolatey já está instalado."
        return
    }
    Write-Info "Instalando Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Ok "Chocolatey instalado."
    } catch {
        Write-Err "Falha na instalação do Chocolatey: $($_.Exception.Message)"
    }
}

$Global:InstallSuccess = New-Object System.Collections.Generic.List[string]
$Global:InstallFail    = New-Object System.Collections.Generic.List[string]

function Install-OnePackage {
    param([Parameter(Mandatory=$true)][string]$Name)
    Write-Info "Instalando $Name..."
    try {
        choco install $Name -y --no-progress --limit-output | Out-Null
        if ($LASTEXITCODE -eq 0) { $Global:InstallSuccess.Add($Name); Write-Ok "$Name instalado." }
        else { $Global:InstallFail.Add($Name); Write-Warn "$Name falhou com código $LASTEXITCODE." }
    } catch {
        $Global:InstallFail.Add($Name)
        Write-Warn "Erro instalando $($Name): $($_.Exception.Message)"
    }
}

function Install-ChocoPackageBatch {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Warn "Chocolatey não encontrado. Instalando primeiro..."
        Install-Chocolatey
    }

    foreach ($pkg in $Global:ChocoPackages) {
        Install-OnePackage -Name $pkg
    }

    Write-Host ""; Write-Host "================= SUMÁRIO DA INSTALAÇÃO =================" -ForegroundColor White
    Write-Host "SUCESSOS:" -ForegroundColor Green
    if ($Global:InstallSuccess.Count -gt 0) { $Global:InstallSuccess | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green } }
    else { Write-Host "  (nenhum)" -ForegroundColor DarkGray }

    Write-Host "FALHAS:" -ForegroundColor Red
    if ($Global:InstallFail.Count -gt 0)   { $Global:InstallFail    | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red } }
    else { Write-Host "  (nenhuma)" -ForegroundColor DarkGray }

    Write-Host "==========================================================" -ForegroundColor White
}

#endregion Instalação de Aplicações

#region Winget - Instalação em lote

function Test-WingetAvailable {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Get-WingetVersion {
    if (-not (Test-WingetAvailable)) { return $null }
    try {
        $v = winget --version 2>$null
        return $v
    } catch { return $null }
}

function Install-OneWinget {
    param(
        [Parameter(Mandatory)][string]$Id,
        [int]$MaxRetries = 1
    )

    if (-not (Test-WingetAvailable)) {
        Write-Err "winget não está disponível neste sistema. Instale a Microsoft Store App Installer."
        return $false
    }

    $attempt = 0
    while ($true) {
        $attempt++
        Write-Info "Instalando (winget): $Id (tentativa $attempt)..."

        # Observação: não usamos --scope para evitar falhas em pacotes que não suportam.
        # --disable-interactivity evita prompts; --silent quando suportado pelos instaladores
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "winget"
        $psi.Arguments = @(
            "install",
            "-e", "--id", $Id,
            "--source", "winget",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--disable-interactivity",
            "--silent"
        ) -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false

        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $code = $p.ExitCode

        # Sucesso típico é 0. Em muitos casos, "já instalado/sem atualização" também sai com 0.
        if ($code -eq 0) {
            Write-Ok "Pacote '$Id' instalado (ou já presente)."
            return $true
        }

        Write-Warn "Falha ao instalar '$Id' (código $code)."
        if ($stdout) { Write-Warn "stdout: $($stdout -replace '\s+$','')" }
        if ($stderr) { Write-Warn "stderr: $($stderr -replace '\s+$','')" }

        if ($attempt -ge (1 + $MaxRetries)) {
            Write-Err "Desistindo do pacote '$Id' após $attempt tentativa(s). Continuando com os próximos…"
            return $false
        }

        Start-Sleep -Seconds 5
        Write-Info "Re-tentando '$Id'…"
    }
}

function Install-WingetPackageBatch {
    Write-Info "Verificando winget…"
    $v = Get-WingetVersion
    if (-not $v) {
        Write-Err "winget não está disponível. Instale 'App Installer' pela Microsoft Store e execute novamente."
        Pause-Enter
        return
    }
    Write-Ok "winget detectado (versão: $v)."

    $failures = @()
    foreach ($pkg in $Global:WingetPackages) {
        $ok = $false
        try {
            $ok = Install-OneWinget -Id $pkg -MaxRetries 1
        } catch {
            Write-Err "Exceção ao instalar '$pkg': $($_.Exception.Message)"
        }
        if (-not $ok) { $failures += $pkg }
    }

    # Opcional: se Python 3.13 foi instalado, garantir pip/pywin32
    if ($Global:WingetPackages -contains 'Python.Python.3.13') {
        try {
            if (Get-Command py -ErrorAction SilentlyContinue) {
                Write-Info "Ajustando Python: atualizando pip e instalando pywin32…"
                py -m pip install -U pip
                py -m pip install -U pywin32
                Write-Ok "pip/pywin32 ajustados."
            } else {
                Write-Warn "Comando 'py' não encontrado após instalação. Pulei ajuste de pip/pywin32."
            }
        } catch {
            Write-Err "Falha ao ajustar pip/pywin32: $($_.Exception.Message)"
        }
    }

    if ($failures.Count -gt 0) {
        Write-Warn "Alguns pacotes falharam: $($failures -join ', ')"
    } else {
        Write-Ok "Todos os pacotes winget foram instalados com sucesso."
    }

    Pause-Enter
}

function Set-ThinkPadKeyboardLayout {
    [CmdletBinding()]
    param()

    if (-not (Test-IsAdmin)) { Ensure-Admin }

    $regPath   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
    $valueName = 'Scancode Map'
    # alvo: 00 00 00 00 00 00 00 00 02 00 00 00 73 00 1D E0 00 00 00 00
    $target = [byte[]](0,0,0,0,0,0,0,0,2,0,0,0,0x73,0x00,0x1D,0xE0,0,0,0,0)

    try {
        # Lê valor atual de forma robusta
        $current = $null
        try {
            $current = Get-ItemPropertyValue -Path $regPath -Name $valueName -ErrorAction Stop
        } catch {
            # sem valor ainda
        }

        $toHex = { param($bytes) if ($bytes -is [byte[]]) { [System.BitConverter]::ToString($bytes) } else { '<null>' } }
        Write-Info ("Valor atual em hexa: {0}" -f (& $toHex $current))

        $alreadySet = ($current -is [byte[]]) -and ([System.Linq.Enumerable]::SequenceEqual($current, $target))

        if ($alreadySet) {
            Write-Ok "O Scancode Map já está com o valor esperado. Nenhuma alteração necessária."
            return
        }

        # Backup
        Write-Info "Criando backup do layout atual do teclado..."
        $backupDir = Join-Path $env:ProgramData 'PostInstall'
        if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory | Out-Null }
        $backupFile = Join-Path $backupDir ("keyboard-layout_backup_{0}.reg" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout' $backupFile /y | Out-Null
        Write-Ok "Backup salvo em: $backupFile"

        # Aplica novo valor
        Write-Info "Aplicando Scancode Map para teclado Lenovo ThinkPad..."
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

        if ($null -ne $current) {
            # já existe a propriedade -> atualiza
            Set-ItemProperty -Path $regPath -Name $valueName -Value $target
        } else {
            # cria REG_BINARY
            New-ItemProperty -Path $regPath -Name $valueName -PropertyType Binary -Value $target -Force | Out-Null
        }

        # Verificação pós-aplicação
        $applied = $null
        try { $applied = Get-ItemPropertyValue -Path $regPath -Name $valueName -ErrorAction Stop } catch {}
        $ok = ($applied -is [byte[]]) -and [System.Linq.Enumerable]::SequenceEqual($applied, $target)

        if ($ok) {
            Write-Ok "Scancode Map configurado com sucesso."
            Write-Warn "É necessário reiniciar o Windows para que a alteração tenha efeito."
            $resp = Read-Host "Deseja reiniciar agora? (S/N)"
            if ($resp -match '^(s|y|S|Y)$') {
                Write-Info "Reiniciando em 5 segundos..."
                Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r','/t','5','/c','Aplicando Scancode Map para teclado Lenovo ThinkPad' -Verb RunAs
            } else {
                Write-Info "Reinicie depois para aplicar as alterações."
            }
        } else {
            Write-Warn "Não foi possível confirmar a configuração do Scancode Map."
        }
    } catch {
        Write-Warn "Falha ao configurar Scancode Map: $($_.Exception.Message)"
    } finally {
        Pause-Enter
    }
}

#region Fluxos das Opções

#function Option1-RestorePoint { CreateSystemRestorePoint }
#function Option2-Windebloat  { Run-Windebloat }
#function Option3-EnableSudo  { Enable-WindowsSudo }
#function Option4-InstallChoco{ Install-Chocolatey }
#function Option5-InstallApps { Install-ChocoPackageBatch }
#function Option6-ThinkPadLayout { Set-ThinkPadKeyboardLayout }

#endregion Fluxos das Opções

#region Menu

function Show-Menu {
    Clear-Host
    Write-Host "================ Pós-Formatação (PowerShell) ================" -ForegroundColor White
    Write-Host "1) Create Restore Point"
    Write-Host "2) Windows 11 Debloat By Raphire"
    Write-Host "3) Enable Sudo"
	Write-Host "4) Install App list with Winget + Ensure-PyWin32"
    Write-Host "5) Install Chocolatey"
    Write-Host "6) Install App List with Chocolatey"
	Write-Host "7) Change Lenovo Thinkpad keyboard Layout"
    Write-Host "0) Exit"
    Write-Host "=============================================================" -ForegroundColor White
}

function Run-Menu {
    Ensure-Admin
    do {
        Show-Menu
        $choice = Read-Host "Choose an option"
        switch ($choice) {
			'1' { CreateSystemRestorePoint; Pause-Enter }
			'2' { Run-Windebloat;           Pause-Enter }
			'3' { Enable-WindowsSudo;       Pause-Enter }
            '4' { Install-WingetPackageBatch }
			'5' { Install-Chocolatey;       Pause-Enter }
			'6' { Install-ChocoPackageBatch; Pause-Enter }
			'7' { Set-ThinkPadKeyboardLayout }  
			'0' { Write-Info "Saindo..."; break }
			default { Write-Warn "Opção inválida."; Pause-Enter }
}
    } while ($choice -ne '0')
}

#endregion Menu

# =========== PONTO DE ENTRADA ===========
Run-Menu
