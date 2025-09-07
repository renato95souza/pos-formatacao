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

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg`n" -ForegroundColor Green }
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

function Run-Windebloat {
    Write-Info "Executando Windebloat com parâmetros padrão..."
    try {
        & ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -RunDefaults
        Write-Ok "Windebloat concluído."
    } catch {
        Write-Warn "Falha ao executar Windebloat: $($_.Exception.Message)"
    }
}

function Enable-WindowsSudo {
    Write-Info "Habilitando 'sudo' no Windows 11 (modo normal)..."
    try {
        sudo config --enable normal
        Write-Ok "'sudo' habilitado."
    } catch {
        Write-Warn "Falha ao habilitar 'sudo'. Verifique se o recurso está disponível nesta versão do Windows. Detalhe: $($_.Exception.Message)"
    }
}

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
    Write-Info "Tentando instalar o pacote $Name..."
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

function Test-WingetAvailable { [bool](Get-Command winget -ErrorAction SilentlyContinue) }
function Get-WingetVersion    { if (Test-WingetAvailable) { try { winget --version 2>$null } catch { $null } } }

function Install-OneWinget {
    param(
        [Parameter(Mandatory)][string]$Id,
        [int]$MaxRetries = 1
    )

    $start = Get-Date
    if (-not (Test-WingetAvailable)) {
        return [pscustomobject]@{
            Name=$Id; Status='Fail'; Code=$null; Note='winget ausente'; Duration=[timespan]::Zero
        }
    }

    $attempt = 0
    while ($true) {
        $attempt++

        Write-Info "Instalando o pacote $Id..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "winget"
        $psi.Arguments = ("install -e --id {0} --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --silent" -f $Id)
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false

        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $code = $p.ExitCode

        $duration = (Get-Date) - $start

        switch ($code) {
            0 {
                return [pscustomobject]@{
                    Name=$Id; Status='OK'; Code=0; Note='Already installed'; Duration=$duration
                }
            }
            -1978335189 { # No applicable update found (já instalado / sem update)
                return [pscustomobject]@{
                    Name=$Id; Status='UpToDate'; Code=$code; Note='Already updated'; Duration=$duration
                }
            }
            -1978335146 { # Installer cannot run elevated (ex.: Spotify)
                return [pscustomobject]@{
                    Name=$Id; Status='SkipAdmin'; Code=$code; Note='Does not support elevated execution'; Duration=$duration
                }
            }
            default {
                if ($attempt -le $MaxRetries) {
                    Start-Sleep -Seconds 3
                    continue
                }

                # Pega apenas a 1ª linha relevante do erro para evitar poluição
                $firstErr = ($stderr + "`n" + $stdout) -split "`r?`n" |
                            Where-Object { $_ -and $_.Trim().Length -gt 0 } |
                            Select-Object -First 1
                if (-not $firstErr) { $firstErr = 'Unknown error' }

                return [pscustomobject]@{
                    Name=$Id; Status='Fail'; Code=$code; Note=$firstErr; Duration=$duration
                }
            }
        }
    }
}

function Install-WingetPackageBatch {
    Write-Info "Verificando winget…"
    $v = Get-WingetVersion
    if (-not $v) {
        Write-Err "Winget não está disponível. Instale 'App Installer' e execute novamente."
        Pause-Enter
        return
    }
  
    Write-Ok "winget detectado (versão: $v).`n"


    $results = New-Object System.Collections.Generic.List[object]
    $t0 = Get-Date

    foreach ($pkg in $Global:WingetPackages) {
        #Write-Info "→ $pkg"
        try {
            $r = Install-OneWinget -Id $pkg -MaxRetries 1
        } catch {
            $r = [pscustomobject]@{
                Name=$pkg; Status='Fail'; Code=$null; Note=$_.Exception.Message; Duration=[timespan]::Zero
            }
        }

        switch ($r.Status) {
            'OK'        { Write-Ok   "Installed         $($r.Name)" }
            'UpToDate'  { Write-Ok   "Updated $($r.Name)" }
            'SkipAdmin' { Write-Warn "Ignorado    $($r.Name) — $($r.Note)" }
            'Fail'      { Write-Err  "Failed       $($r.Name) (código $($r.Code)) — $($r.Note)" }
            default     { Write-Err  "Failed       $($r.Name) — Status inesperado '$($r.Status)'" }
        }

        $results.Add($r) | Out-Null
    }

    # Pós-instalação Python (se presente na lista e OK/UpToDate)
    if ($Global:WingetPackages -contains 'Python.Python.3.13') {
        $pyOk = $results | Where-Object { $_.Name -eq 'Python.Python.3.13' -and $_.Status -in 'OK','UpToDate' }
        if ($pyOk) {
            try {
                if (Get-Command py -ErrorAction SilentlyContinue) {
                    Write-Info "Ajustando Python (pip/pywin32)…"
                    py -m pip install -U pip    | Out-Null
                    py -m pip install -U pywin32| Out-Null
                    Write-Ok "pip/pywin32 OK."
                } else {
                    Write-Warn "Comando 'py' não encontrado; pulei ajuste de pip/pywin32."
                }
            } catch {
                Write-Err "Falha ao ajustar pip/pywin32: $($_.Exception.Message)"
            }
        }
    }

    # ===== Resumo estilo “relatório” =====
    $elapsed = (Get-Date) - $t0
    $byStatus = $results | Group-Object Status | Sort-Object Name
    $tot = $results.Count
    $ok  = ($byStatus | Where-Object Name -eq 'OK').Count
    $upd = ($byStatus | Where-Object Name -eq 'UpToDate').Count
    $skp = ($byStatus | Where-Object Name -eq 'SkipAdmin').Count
    $fal = ($byStatus | Where-Object Name -eq 'Fail').Count

    Write-Info  "——— RESUMO ———"
    Write-Ok    ("Totais: {0}  |  OK: {1}  |  Atualizado: {2}  |  Ignorado(Admin): {3}  |  Falha: {4}  |  Tempo: {5:mm\:ss}" -f $tot,$ok,$upd,$skp,$fal,$elapsed)
    
    # Tabela compacta
    $table = $results |
        Sort-Object Status, Name |
        Select-Object @{n='Pacote';e={$_.Name}},
                      @{n='Status';e={$_.Status}},
                      @{n='Nota';e={$_.Note}},
                      @{n='Duração';e={ '{0:mm\:ss}' -f $_.Duration }}

    # Renderiza a tabela como string e imprime em bloco único
    $tblStr = $table | Format-Table -AutoSize | Out-String
    ($tblStr -split "`r?`n" | ForEach-Object {
        if ($_ -match '\S') { Write-Info $_ }
    }) | Out-Null

    # Se houve falhas, destacar a lista curta de motivos
    if ($fal -gt 0) {
        $fails = $results | Where-Object Status -eq 'Fail' |
                 Select-Object Name, Code, Note
        Write-Err "Falhas detalhadas:"
        $fails | ForEach-Object {
            Write-Err (" • {0} (código {1}) — {2}" -f $_.Name, $_.Code, $_.Note)
        }
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

function Show-Menu {
    Clear-Host
    Write-Host "================ Pós-Formatação (PowerShell) ================" -ForegroundColor White
    Write-Host "1) Enable Sudo"
    Write-Host "2) Create Restore Point"
    Write-Host "3) Windows 11 Debloat By Raphire"
	Write-Host "4) Install App list with Winget + Ensure-PyWin32"
    Write-Host "5) Install App list with Chocolatey (if not available on winget)"
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
            '1' { Enable-WindowsSudo;       Pause-Enter }
			'2' { CreateSystemRestorePoint; Pause-Enter }
			'3' { Run-Windebloat;           Pause-Enter }
            '4' { Install-WingetPackageBatch }
			'5' { Install-ChocoPackageBatch; Pause-Enter }
			'6' { Set-ThinkPadKeyboardLayout }  
			'0' { Write-Info "Exiting..."; break }
			default { Write-Warn "Invalid option."; Pause-Enter }
}
    } while ($choice -ne '0')
}

Run-Menu
