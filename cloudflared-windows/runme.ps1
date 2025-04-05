function Get-ProcessIDByPort {
    param(
        [int]$Port
    )

    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connection) {
        $connection | Select-Object -ExpandProperty OwningProcess -Unique
    } else {
        return 0
    }
}

function Get-ProcessByPort {
    param(
        [int]$Port
    )

    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connection) {
        $ProcessID = $connection | Select-Object -ExpandProperty OwningProcess -Unique
        (Get-Process -Id $ProcessID).Name 
    } else {
        Write-Output "No process is using port $Port."
    }
}

function Get-ProcessPorts {
    param(
        [int]$ProcessID, 
        [string]$ProcessName
    )

    if ($ProcessID -and $ProcessName) {
        Write-Error "Please provide either a ProcessID or a ProcessName, not both."
        return
    }

    if ($ProcessName) {
        $ProcessID = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    }

    if ($ProcessID) {
        Get-NetTCPConnection -OwningProcess $ProcessID -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique
    } else {
        Write-Error "No valid ProcessID or ProcessName provided."
    }
}

function Stop-App {
    param(
        [string]$app
    )

    # Stop Service if it exists
    $service = Get-Service -Name $app -ErrorAction SilentlyContinue
    if ($service) { 
        Stop-Service -Name $app -Force -Verbose
        Set-Service -Name $app -StartupType Manual -Status Stopped
        return
    }

    # Stop Process if running
    $processes = Get-Process -Name $app -ErrorAction SilentlyContinue
    if ($processes) {
        $processes | Stop-Process -Force -Verbose
    }
}

function Start-App {
    param(
        [string]$app
    )

    $service = Get-Service -Name $app -ErrorAction SilentlyContinue
    if ($service) { 
        Set-Service -Name $app -StartupType Automatic -Status Running
        Start-Service -Name $app -Verbose 
    } else { 
        Start-Process $app -ErrorAction SilentlyContinue -Verbose
    }
}

function Restart-App {
    param(
        [string]$app
    )

    $service = Get-Service -Name $app -ErrorAction SilentlyContinue
    if ($service) { 
        Restart-Service -Name $app -Force -Verbose
        Set-Service -Name $app -StartupType Automatic -Status Running
    } else {
        $process = Get-Process -Name $app -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Name $app -Force -Verbose
            Start-Process $app -ErrorAction SilentlyContinue -Verbose
        }
    }
}


function FreePort {
    param(
        [int]$Port
    )

    $ProcessID = Get-ProcessIDByPort $Port
    if ($ProcessID -is [string]) {
        Write-Output $ProcessID
        return
    }

    if ($ProcessID) {
        $Service = Get-CimInstance -ClassName Win32_Service | Where-Object { $_.ProcessId -eq $ProcessID }
        
        if ($Service) {
            Stop-App -app $Service.Name
        } else {
            Stop-Process -Id $ProcessID -Force -Verbose
            Write-Output "Freed port $Port by stopping process ID $ProcessID."
        }
    } else {
        Write-Output "No process is using port $Port."
    }
}

function ConfigureSystemDNS {
    param(
        [string]$mode
    )

    if ($mode -eq 'r') {
        Write-Host 'Reseting System DNS to default' -ForegroundColor Green
        Get-NetAdapter -Physical | Set-DnsClientServerAddress -ResetServerAddresses
    } elseif ($mode -eq 'l') {
        Write-Host 'Configuring System DNS to use loopback address' -ForegroundColor Green
        Get-NetAdapter -Physical | Set-DnsClientServerAddress -ServerAddresses @('127.0.0.1', '::1')
    } else {
        Write-Error 'Select valid option.'
    }
}

function ConfigureService {
    New-Item -Path $servicepath -ItemType Directory -Force -ErrorAction SilentlyContinue -Verbose
    New-Item -Path "$servicepath\config.yml" -ItemType SymbolicLink -Value "$datapath\config.yml" -Force -Verbose
    & $Application service install; Get-Service $Command
    ipconfig /flushdns
}

function CreateLinks {
    do {
        $ProviderNames = @()
        for ($i = 0; $i -lt $providers.PSObject.Properties.Name.Count; $i++) {
            $ProviderNames += "$i`) $($providers.PSObject.Properties.Name[$i])"
        }
        
        Clear-Host
        Write-Host 'DNS Provider Selection Menu:'
        $ProviderNames | ForEach-Object { Write-Host "  $_" }
        $selectedIndex = Read-Host 'Select DNS provider'

        if ($selectedIndex -eq '') {
            $null
        } elseif ($selectedIndex -as [int] -ge 0 -and $selectedIndex -as [int] -lt $providers.PSObject.Properties.Name.Count) {
            $selectedProviderName = $providers.PSObject.Properties.Name[$selectedIndex]
            $selectedProviderInfo = $providers.$selectedProviderName
            Write-Host "Selected $selectedProviderName" -ForegroundColor Green
            $SelectedConfig = $selectedProviderInfo | ForEach-Object { ' - ' + "https://$_/dns-query" }
            return $SelectedConfig
        }
    } while (-not $SelectedConfig)
}

function CreateConfig {
    $SetConfig = Read-Host "Press 'd' for DOH Cloudflare. 'c' to configure, or 'e' for edit yourself. Anything else to skip."
    if ($SetConfig -eq 'd') {
        Get-Content "$PSScriptRoot\config.yaml" | Set-Content -Path "$datapath\config.yml" -Force
    } elseif ($SetConfig -eq 'c') {
        $configContent = Get-Content "$PSScriptRoot\config.yaml"
        $configContent += 'proxy-dns-upstream:'
        $configContent += CreateLinks
        $lastTwoLines = $configContent | Select-Object -Last 2
        if ($lastTwoLines -match 'f' -and $lastTwoLines -match 'https://') {
            $configContent = $configContent | Select-Object -SkipLast 2
        }
        if ((Read-Host 'Store Basic Logs?(y/n)') -eq 'y') { $configContent += "logDirectory:: $datapath" }
        $configContent | Set-Content -Path "$datapath\config.yml" -Force
    } elseif ($SetConfig -eq 'E') {
        Add-Content '' -Path "$datapath\config.yml" -Force
        notepad.exe "$datapath\config.yml"
    } else {
        $null
    }
}

function QuickSetup { 

    if (Get-ProcessByPort -Port 53 -ne $Command) {
        FreePort -Port 53
    }  
    CreateConfig;
    ConfigureSystemDNS -mode l; 
    ConfigureService; 
    ipconfig /flushdns 
}

function Reset-Setup {
    # Clear the service
    Stop-App -app $Command
    & $Application service uninstall 
    cmd /c sc delete $Command
    Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared' -Recurse -Force -ErrorAction SilentlyContinue
    Get-EventLog -List | ForEach-Object { Clear-EventLog -LogName $_.Log }

    # Remove config files
    ("$servicepath", "$datapath\config.yml") | ForEach-Object { Remove-Item -Path $_ -Recurse -Force -Verbose }

    # Reset dns address
    ConfigureSystemDNS -mode r

    # clear dns cache
    ipconfig /flushdns
    
}


function SetupMenu {
    Write-Host '1. Quick Setup'
    Write-Host '2. Create/Edit config.yml'
    Write-Host '3. Reset'
    Write-Host '4. <-- Back'
}

function StartSetup {
    Clear-Host
    do {
        SetupMenu
        $SetupChoice = Read-Host 'Enter your choice'

        switch ($SetupChoice) {
            '1' { QuickSetup }
            '2' { CreateConfig }
            '3' { Reset-Setup }
            '4' { return }
            default {
                Write-Host 'Invalid choice. Please select a valid option.' 
            }
        }
        Pause
        Clear-Host
    } while ($SetupChoice -ne '4')
}


mkdir $env:TEMP/dohsetup
cd $env:TEMP/dohsetup
irm https://github.com/chandeshpatwari/secure-dns-on-windows/raw/refs/heads/main/cloudflared-windows/config.yaml > config.yml
(irm https://raw.githubusercontent.com/chandeshpatwari/secure-dns-on-windows/refs/heads/main/cloudflared-windows/transformed_providers.json | ConvertTo-Json) > transformed_providers.json

$Command = 'cloudflared'
$Application = 'cloudflared.exe'
$servicepath = "$env:SYSTEMROOT\system32\config\systemprofile\.cloudflared"
$datapath = "$env:USERPROFILE\.cloudflared"
$providers = Get-Content "$PSScriptRoot\transformed_providers.json" | ConvertFrom-Json


StartSetup








