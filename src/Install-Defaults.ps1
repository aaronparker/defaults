#Requires -RunAsAdministrator
#Requires -PSEdition Desktop
<#
    .SYNOPSIS
    Implements Configuration changes to a default install of Windows to enable an enterprise ready installation.

    .PARAMETER Language
    A CultureInfo value that defines the locale / language configuration to install and configure for Windows.

    .PARAMETER TimeZone
    A string that is the StandardName or DaylightName properties of the TimeZoneInfo object. Use 'Get-TimeZone -ListAvailable' to list available time zones.

    .PARAMETER Path
    Path to where the scripts and configuration files are located.

    .PARAMETER Guid
    A GUID string that identifies the solution installation for detection via the Uninstall key in the Windows registry.

    .PARAMETER Publisher
    String that represents the publisher information that will be stored in the Uninstall key in the Windows registry.

    .PARAMETER RunOn
    Date time stamp that will be stored in the Uninstall key in the Windows registry.

    .PARAMETER Project
    A string that defines the name for the solution. This string will be used for the custom event log to track the installation and stored in the Windows registry.

    .PARAMETER Helplink
    A string that defines a URL for the solution. This string will be written to the Uninstall key in the Windows registry.

    .PARAMETER FeatureUpdatePath
    A directory path in which the solution will be copied into to enable running during Windows feature updates.

    .EXAMPLE
    PS C:\image-defaults> .\Install-Defaults.ps1 -Language "en-AU" -TimeZone "AUS Eastern Standard Time" -Verbose

    .NOTES
    NAME: Install-Defaults.ps1
    AUTHOR: Aaron Parker
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.Globalization.CultureInfo] $Language, # Set the specified locale / language

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $InstallLanguagePack, # Install the language pack for the specified language

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $TimeZone,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Path = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Guid = "f38de27b-799e-4c30-8a01-bfdedc622944",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Publisher = "stealthpuppy",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $RunOn = $(Get-Date -Format "yyyy-MM-dd"),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Project = "Windows Enterprise Defaults",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Helplink = "https://stealthpuppy.com/defaults/",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $FeatureUpdatePath = "$env:SystemRoot\System32\update\run\$Guid"
)

#region Restart if running in a 32-bit session
if (!([System.Environment]::Is64BitProcess)) {
    if ([System.Environment]::Is64BitOperatingSystem) {

        # Create a string from the passed parameters
        [System.String]$ParameterString = ""
        foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
            $ParameterString += " -$($Parameter.Key) $($Parameter.Value)"
        }

        # Execute the script in a 64-bit process with the passed parameters
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Definition)`"$ParameterString"
        $ProcessPath = $(Join-Path -Path $Env:SystemRoot -ChildPath "\Sysnative\WindowsPowerShell\v1.0\powershell.exe")
        $params = @{
            FilePath     = $ProcessPath
            ArgumentList = $Arguments
            Wait         = $true
            WindowStyle  = "Hidden"
        }
        Start-Process @params
        exit 0
    }
}
#endregion

# Configure the environment
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

# Get start time of the script
$StartTime = Get-Date

# Splat WhatIf and Verbose preferences to pass to functions
$prefs = @{
    WhatIf  = $WhatIfPreference
    Verbose = $VerbosePreference
}

# Configure working path
if ($Path.Length -eq 0) { $WorkingPath = $PWD.Path } else { $WorkingPath = $Path }
Push-Location -Path $WorkingPath

#region Import functions
$ModuleFile = $(Join-Path -Path $PSScriptRoot -ChildPath "Install-Defaults.psm1")
Test-Path -Path $ModuleFile -PathType "Leaf" -ErrorAction "Stop" | Out-Null
Import-Module -Name $ModuleFile -Force -ErrorAction "Stop"
Write-LogFile -Message "Execution path: $WorkingPath"
#endregion

# Start logging
$PSProcesses = Get-CimInstance -ClassName "Win32_Process" -Filter "Name = 'powershell.exe'" | Select-Object -Property "CommandLine"
foreach ($Process in $PSProcesses) {
    Write-LogFile -Message "Running process: $($Process.CommandLine)"
}

# Get system properties
$Platform = Get-Platform

$Build = ([System.Environment]::OSVersion.Version).Build
$OSVersion = [System.Environment]::OSVersion.Version
Write-LogFile -Message "Build: $Build"

$Model = Get-Model
$OSName = Get-OSName

$DisplayVersion = Get-ChildItem -Path $WorkingPath -Include "VERSION.txt" -Recurse | Get-Content -Raw
Write-LogFile -Message "Script version: $DisplayVersion"

#region Gather configs
$AllConfigs = @(Get-ChildItem -Path "$WorkingPath\configs" -Include "*.All.json" -Recurse -ErrorAction "Continue")
$ModelConfigs = @(Get-ChildItem -Path "$WorkingPath\configs" -Include "*.$Model.json" -Recurse -ErrorAction "Continue")
$BuildConfigs = @(Get-ChildItem -Path "$WorkingPath\configs" -Include "*.$Build.json" -Recurse -ErrorAction "Continue")
$PlatformConfigs = @(Get-ChildItem -Path "$WorkingPath\configs" -Include "*.$Platform.json" -Recurse -ErrorAction "Continue")
Write-LogFile -Message "Found: $(($AllConfigs + $ModelConfigs + $BuildConfigs + $PlatformConfigs).Count) configs"

# Implement the settings defined in each config file
foreach ($Config in ($AllConfigs + $PlatformConfigs + $BuildConfigs + $ModelConfigs)) {

    # Read the settings JSON
    Write-LogFile -Message "Running config: $($Config.FullName)"
    $Settings = Get-SettingsContent -Path $Config.FullName @prefs

    # Implement the settings only if the local build is greater or equal that what's specified in the JSON
    if ([System.Version]$OSVersion -ge [System.Version]$Settings.MinimumBuild) {
        if ([System.Version]$OSVersion -le [System.Version]$Settings.MaximumBuild) {

            #region Implement each setting in the JSON
            if ($Settings.Registry.ChangeOwner.Length -gt 0) {
                foreach ($Item in $Settings.Registry.ChangeOwner) {
                    Set-RegistryOwner -RootKey $Item.Root -Key $Item.Key -Sid $Item.Sid @prefs
                }
            }
            switch ($Settings.Registry.Type) {
                "DefaultProfile" {
                    Set-DefaultUserProfile -Setting $Settings.Registry.Set @prefs; break
                }
                "Direct" {
                    Set-Registry -Setting $Settings.Registry.Set @prefs; break
                    Remove-RegistryPath -Path $Settings.Registry.Remove @prefs; break
                }
                default {
                    Write-LogFile -Message "Skipped registry settings: $($Config.FullName)"
                }
            }

            switch ($Settings.StartMenu.Type) {
                "Server" {
                    if ((Get-WindowsFeature -Name $Settings.StartMenu.Feature).InstallState -eq "Installed") {
                        Copy-File -Path $Settings.StartMenu.Exists -Parent $WorkingPath @prefs
                    }
                    else {
                        Copy-File -Path $Settings.StartMenu.NotExists -Parent $WorkingPath @prefs
                    }
                }
                "Client" {
                    Copy-File -Path $Settings.StartMenu.$OSName -Parent $WorkingPath @prefs
                }
            }

            Copy-File -Path $Settings.Files.Copy -Parent $WorkingPath @prefs
            Remove-Path -Path $Settings.Paths.Remove @prefs
            Remove-Feature -Feature $Settings.Features.Disable @prefs
            Remove-Capability -Capability $Settings.Capabilities.Remove @prefs
            Remove-Package -Package $Settings.Packages.Remove @prefs
            Stop-NamedService -Service $Settings.Services.Stop @prefs
            Start-NamedService -Service $Settings.Services.Start @prefs
            Restart-NamedService -Service $Settings.Services.Restart @prefs
            #endregion
        }
        else {
            Write-LogFile -Message "Skipped maximum version: $($Config.FullName)"
        }
    }
    else {
        Write-LogFile -Message "Skipped minimum version: $($Config.FullName)"
    }
}
#endregion

#region If on a client OS, remove AppX applications
if ($Platform -eq "Client") {
    if (Test-IsOobeComplete) {
        # If OOBE is complete, we should play it safe and not attempt to remove AppX apps
        # Explicitly call Remove-AppxApps.ps1 instead, e.g. for gold images
        Write-LogFile -Message "OOBE is complete. To remove AppX apps, explicitly call Remove-AppxApps.ps1" -LogLevel 2
    }
    else {
        # Run the script to remove AppX/UWP apps; Get the script location
        $Script = Get-ChildItem -Path $WorkingPath -Include "Remove-AppxApps.ps1" -Recurse -ErrorAction "Continue"
        if ($null -eq $Script) {
            Write-LogFile -Message "Script not found: $WorkingPath\Remove-AppxApps.ps1" -LogLevel 3
        }
        else {
            Write-LogFile -Message "Run script: $WorkingPath\Remove-AppxApps.ps1"
            $Apps = & $Script.FullName @prefs -Confirm:$false
            foreach ($App in $Apps) { Write-LogFile -Message "Removed AppX app: $App" }
        }
    }
}
#endregion

#region Set system language, locale and regional settings
if ($PSBoundParameters.ContainsKey('Language')) {
    if ($OSVersion -ge [System.Version]"10.0.22000") {
        
        if ($InstallLanguagePack.IsPresent) {
            # Set language support by installing the specified language pack
            Install-SystemLanguage -Language $Language
        }

        # Set locale settings
        Set-SystemLocale -Language $Language
    }
    else {
        # On Windows Server 2022 or below, use dism to install language packs
        # https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-languages-and-international-servicing-command-line-options

        # Set locale settings
        Set-SystemLocale -Language $Language
    }
}
else {
    Write-LogFile -Message "-Language parameter not specified. Skipping install language support"
}

if ($PSBoundParameters.ContainsKey('TimeZone')) {
    Set-TimeZoneUsingName -TimeZone $TimeZone
}
else {
    Write-LogFile -Message "-TimeZone parameter not specified. Skipping set time zone"
}
#endregion

# Copy the source files for use with upgrades
if (Test-Path -Path "$FeatureUpdatePath\Install-Defaults.ps1" -PathType "Leaf") {
    Write-LogFile -Message "Skipping copy to $FeatureUpdatePath"
}
else {
    try {
        Write-LogFile -Message "New directory: $FeatureUpdatePath"
        New-Item -Path $FeatureUpdatePath -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" | Out-Null
        Copy-Item -Path "$WorkingPath\*" -Destination $FeatureUpdatePath -Recurse -ErrorAction "SilentlyContinue"
        Write-LogFile -Message "Copied $WorkingPath\* to $FeatureUpdatePath"
    }
    catch {
        Write-LogFile -Message $_.Exception.Message -LogLevel 3
    }
}

# Set uninstall registry value for detecting as an installed application
$Key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
New-Item -Path "$Key\{$Guid}" -Type "RegistryKey" -Force -ErrorAction "Continue" | Out-Null
if ($PSCmdlet.ShouldProcess("Set uninstall key values")) {
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "DisplayName" -Value $Project -Type "String" -Force -ErrorAction "Continue" | Out-Null
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "Publisher" -Value $Publisher -Type "String" -Force -ErrorAction "Continue" | Out-Null
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "DisplayVersion" -Value $DisplayVersion -Type "String" -Force -ErrorAction "Continue" | Out-Null
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "RunOn" -Value $RunOn -Type "String" -Force -ErrorAction "Continue" | Out-Null
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "SystemComponent" -Value 1 -Type "DWord" -Force -ErrorAction "Continue" | Out-Null
    Set-ItemProperty -Path "$Key\{$Guid}" -Name "HelpLink" -Value $HelpLink -Type "String" -Force -ErrorAction "Continue" | Out-Null
}

# Write last entry to the event log and output 0 so that we don't fail image builds
$EndTime = (Get-Date) - $StartTime
Write-LogFile -Message "Install-Defaults.ps1 complete. Elapsed time: $EndTime"
return 0
