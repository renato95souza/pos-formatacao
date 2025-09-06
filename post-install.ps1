#requires -Version 5.1
<#!
    Script:    post-install.ps1
    Autor:     Renato de Souza de Carvalho ;)
    Objetivo:  Utilitário pós-formatação com menu e funções
    Idioma:    pt-BR

    Opções do menu:
      1) Create Restore Point
      2) Windows Debloat
      3) Enable Sudo
      4) Install Chocolatey
      5) Install Apps with Chocolatey + Ensure-PyWin32

    Observações:
      - O script tenta se auto-elevar para Administrador.
      - Exibe mensagens durante cada instalação.
      - Ao final da Opção 5, roda Ensure-PyWin32 antes do sumário.
      - Mantém um resumo de sucessos e falhas.
!#>

# ================= LISTA DE PACOTES =================
$Global:ChocoPackages = @(
    'nano','advanced-ip-scanner','putty','python','yt-dlp','ffmpeg','flameshot',
    'adobereader','firefox','python3','teamviewer','notepadplusplus.install',
    'bitwarden','mobaxterm','vlc','winrar','wget','spotify','powertoys',
    'forticlientvpn','rufus','virtualbox','keeper', 'revo-uninstaller', 'partition-manager'
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

#endregion Chocolatey

#region Instalação de Aplicações + Ensure-PyWin32

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

function Ensure-PyWin32 {
    Write-Info "Garantindo PyWin32 instalado (via Python 'py')..."
    try {
        & py -m pip install --upgrade pip
        & py -m pip install pywin32
        Write-Ok "PyWin32 ok."
    } catch {
        Write-Warn "Falha no Ensure-PyWin32: $($_.Exception.Message)"
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

    Ensure-PyWin32

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

function Option1-RestorePoint { CreateSystemRestorePoint }
function Option2-Windebloat  { Run-Windebloat }
function Option3-EnableSudo  { Enable-WindowsSudo }
function Option4-InstallChoco{ Install-Chocolatey }
function Option5-InstallApps { Install-ChocoPackageBatch }
function Option6-ThinkPadLayout { Set-ThinkPadKeyboardLayout }

#endregion Fluxos das Opções

#region Menu

function Show-Menu {
    Clear-Host
    Write-Host "================ Pós-Formatação (PowerShell) ================" -ForegroundColor White
    Write-Host "1) Create Restore Point"
    Write-Host "2) Windows 11 Debloat By Raphire"
    Write-Host "3) Enable Sudo"
    Write-Host "4) Install Chocolatey"
    Write-Host "5) Install App List with Chocolatey + Ensure-PyWin32"
	Write-Host "6) Change Lenovo Thinkpad keyboard Layout"
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
			'4' { Install-Chocolatey;       Pause-Enter }
			'5' { Install-ChocoPackageBatch; Pause-Enter }
			'6' { Set-ThinkPadKeyboardLayout }  
			'0' { Write-Info "Saindo..."; break }
			default { Write-Warn "Opção inválida."; Pause-Enter }
}
    } while ($choice -ne '0')
}

#endregion Menu

# =========== PONTO DE ENTRADA ===========
Run-Menu
