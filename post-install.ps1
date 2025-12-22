#requires -Version 5.1
<#!
    Script:    post-install.ps1
    Author:    Renato de Souza de Carvalho ;)
    Objective: Post-format utility with menu and functions (Optimized)
    Language:  en-US
!#>

# Winget package list URL on GitHub
$Global:WingetListUrl = 'https://raw.githubusercontent.com/renato95souza/pos-formatacao/refs/heads/main/winget-packages.txt'
$Global:WingetPackages = @()

# --- Helpers ---
function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg`n" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Pause-Enter {
    Write-Host ""; Write-Host "Press ENTER to continue..." -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ensure-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Warn "This script must be run as Administrator. Restarting elevated..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Process -Id $PID).Path
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        try {
            [Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            Write-Err "Execution cancelled. This script requires administrator privileges."
        }
        exit
    }
}

# --- Functions ---

function CreateSystemRestorePoint {
    Write-Output "> Attempting to create a system restore point..."
    $SysRestore = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "RPSessionInterval"
    if ($SysRestore.RPSessionInterval -eq 0) {
        if ($( Read-Host -Prompt "System restore is disabled. Enable and create point? (y/n)") -eq 'y') {
            Enable-ComputerRestore -Drive "$env:SystemDrive"
        } else { return }
    }
    Checkpoint-Computer -Description "Post-Install Restore Point" -RestorePointType "MODIFY_SETTINGS"
    Write-Ok "System restore point process finished."
}

function Run-Windebloat {
    Write-Info "Running Windebloat with default parameters..."
    try {
        & ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -RunDefaults
        Write-Ok "Windebloat completed."
    } catch {
        Write-Warn "Failed to run Windebloat: $($_.Exception.Message)"
    }
}

function Enable-WindowsSudo {
    Write-Info "Enabling 'sudo' on Windows 11..."
    try {
        sudo config --enable normal
        Write-Ok "'sudo' enabled."
    } catch {
        Write-Warn "Could not enable sudo. Feature might be missing."
    }
}

function Get-WingetPackageList {
    Write-Info "Downloading Winget package list..."
    try {
        $listContent = Invoke-RestMethod -Uri $Global:WingetListUrl -UseBasicParsing -ErrorAction Stop
        $Global:WingetPackages = $listContent -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.Trim().StartsWith('#') } | ForEach-Object { $_.Trim() }
        Write-Ok "List loaded: $($Global:WingetPackages.Count) items."
        return $true
    } catch {
        Write-Err "Failed to download package list."
        return $false
    }
}

function Install-OneWinget {
    param([string]$Id)
    $start = Get-Date
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "winget"
    $psi.Arguments = "install -e --id $Id --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --silent"
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    return [pscustomobject]@{ Name=$Id; Status=$p.ExitCode; Duration=(Get-Date)-$start }
}

function Install-WingetPackageBatch {
    if (-not (Get-WingetPackageList)) { Pause-Enter; return }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($pkg in $Global:WingetPackages) {
        $r = Install-OneWinget -Id $pkg
        if ($r.Status -eq 0) { Write-Ok "Installed: $pkg" } else { Write-Warn "Result $pkg : $($r.Status)" }
        $results.Add($r) | Out-Null
    }

    # --- PYTHON & PYWIN32 FIX ---
    $pythonID = $Global:WingetPackages | Where-Object { $_ -match 'Python\.Python' } | Select-Object -First 1
    if ($pythonID) {
        Write-Info "Refreshing Environment Variables to detect Python..."
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Start-Sleep -Seconds 2

        if (Get-Command py -ErrorAction SilentlyContinue) {
            Write-Info "Configuring Python: upgrading pip and installing pywin32..."
            & py -m pip install --upgrade pip --quiet
            & py -m pip install pywin32 --quiet
            
            $pyPath = & py -c "import sys; print(sys.prefix)"
            $postInstall = Join-Path $pyPath "Scripts\pywin32_postinstall.py"
            if (Test-Path $postInstall) {
                & py $postInstall -install | Out-Null
                Write-Ok "pywin32 registered successfully."
            }
        } else {
            Write-Warn "Python 'py' command not found in current session Path."
        }
    }
    Pause-Enter
}

function Set-ThinkPadKeyboardLayout {
    if (-not (Test-IsAdmin)) { Ensure-Admin }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
    $target = [byte[]](0,0,0,0,0,0,0,0,2,0,0,0,0x73,0x00,0x1D,0xE0,0,0,0,0)
    Set-ItemProperty -Path $regPath -Name "Scancode Map" -Value $target -Type Binary
    Write-Ok "Keyboard Layout applied. Restart required."
    if ((Read-Host "Restart now? (y/n)") -eq 'y') { shutdown /r /t 5 }
}

function Disable-WindowsPrintScreen {
    Write-Info "Disabling native Snipping Tool on Print Screen key..."
    Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name PrintScreenKeyForSnippingEnabled -Value 0
    Write-Ok "Registry updated."
    if ((Read-Host "Restart Explorer now? (y/n)") -eq 'y') { Stop-Process -Name explorer -Force }
}

function Restore-OneDriveBackups {
    # IMPORTANTE: Captura o usuário real logado, ignorando o contexto de Admin
    $LoggedUser = (Get-WmiObject -class win32_process -Filter "Name='explorer.exe'" | 
                  ForEach-Object { $_.GetOwner().User } | Select-Object -First 1)
    
    # Se falhar por algum motivo, usa o env:username atual
    if ($null -eq $LoggedUser) { $LoggedUser = $env:USERNAME }

    $RealUserProfile = "C:\Users\$LoggedUser"
    $OneDriveRoot = "$RealUserProfile\OneDrive - Pague Menos Comercio de Produtos Alimenticios Ltda"
    $BackupPath = Join-Path $OneDriveRoot "Documentos\Backups"

    Clear-Host
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host " ATENÇÃO: Verifique se os arquivos estão baixados!" -ForegroundColor Yellow
    Write-Host " Usuário detectado: $LoggedUser" -ForegroundColor Cyan
    Write-Host " Local de busca: $BackupPath"
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Red
    
    $confirm = Read-Host "Os arquivos estão marcados para 'Manter sempre neste dispositivo'? (y/n)"
    if ($confirm -ne 'y') { return }

    if (-not (Test-Path $BackupPath)) {
        Write-Err "Pasta de backup não encontrada: $BackupPath"
        return
    }

    $Restores = @(
        @{ Zip="MobaXterm_Backup.zip";   Dest="AppData\Roaming\MobaXterm";      Proc="MobaXterm" }
        @{ Zip="DBeaverData_Backup.zip"; Dest="AppData\Roaming\DBeaverData";    Proc="dbeaver" }
        @{ Zip="NotepadPP_Backup.zip";   Dest="AppData\Roaming\Notepad++";      Proc="notepad++" }
        @{ Zip="OCI_Config_Backup.zip";  Dest=".oci";                          Proc=$null }
    )

    Write-Info "Iniciando restauração no perfil: $RealUserProfile"

    foreach ($item in $Restores) {
        $ZipFile = Join-Path $BackupPath $item.Zip
        $FullDestPath = Join-Path $RealUserProfile $item.Dest

        if (Test-Path $ZipFile) {
            if ($item.Proc -and (Get-Process $item.Proc -ErrorAction SilentlyContinue)) {
                Write-Warn "Fechando $($item.Proc)..."
                Stop-Process -Name $item.Proc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }

            if (-not (Test-Path $FullDestPath)) { 
                New-Item -Path $FullDestPath -ItemType Directory -Force | Out-Null 
            }
            
            try {
                Write-Info "Restaurando $($item.Zip)..."
                Expand-Archive -Path $ZipFile -DestinationPath $FullDestPath -Force
                Write-Ok "Sucesso: $($item.Zip)"
            } catch {
                Write-Err "Erro ao extrair $($item.Zip). Verifique permissões."
            }
        } else {
            Write-Warn "Arquivo ausente: $($item.Zip)"
        }
    }
    Write-Ok "O backup foi restaurado da pasta: $BackupPath"
}

# --- Menu Logic ---

function Show-Menu {
    Clear-Host
    Write-Host "================ Post-Install Utility (PowerShell) ================" -ForegroundColor White
    Write-Host "1) Enable Sudo"
    Write-Host "2) Create System Restore Point"
    Write-Host "3) Windows 11 Debloat (By Raphire)"
    Write-Host "4) Install App List (Winget) + Python/pywin32 Fix"
    Write-Host "5) Change Lenovo ThinkPad Keyboard Layout"
    Write-Host "6) Disable Native PrintScreen (Snipping Tool)"
    Write-Host "7) Update All Existing Apps (Winget Upgrade)"
    Write-Host "8) Restore Apps Backup (OneDrive)"
    Write-Host "0) Exit"
    Write-Host "===================================================================" -ForegroundColor White
}

function Run-Menu {
    Ensure-Admin
    do {
        Show-Menu
        $choice = Read-Host "Select an option"
        switch ($choice) {
            '1' { Enable-WindowsSudo; Pause-Enter }
            '2' { CreateSystemRestorePoint; Pause-Enter }
            '3' { Run-Windebloat; Pause-Enter }
            '4' { Install-WingetPackageBatch }
            '5' { Set-ThinkPadKeyboardLayout; Pause-Enter }
            '6' { Disable-WindowsPrintScreen; Pause-Enter }
            '7' { Write-Info "Updating all apps..."; winget upgrade --all --include-unknown; Pause-Enter }
            '8' { Restore-OneDriveBackups; Pause-Enter }
            '0' { break }
        }
    } while ($choice -ne '0')
}

Run-Menu
