<#
    .SYNOPSIS
    Removes unnecessary AppX packages from the local Windows system.

    .DESCRIPTION
    This script removes AppX packages from all users and provisioned packages on the system, except for those specified in $SafePackageList.
    The default list of packages provide baseline functionality and should work in desktops using FSLogix Profile Container.
    The script can be run with the -Targeted switch to remove a specific list of AppX packages, which is useful for in-place feature updates.
    Additionally, it deletes specific registry keys related to Outlook and DevHome updates if the script is run with elevated privileges.

    .PARAMETER SafePackageList
    An optional parameter that specifies a list of AppX package family names to be preserved during the removal process.
    By default, it includes common desktop apps, system applications, and image/video codecs.

    .PARAMETER Targeted
    An optional switch parameter that, when specified, runs the script with a targeted list of AppX packages to be removed.

    .PARAMETER TargetedPackageList
    An optional parameter that specifies a targeted list of AppX package family names to be removed when the -Targeted switch is used.

    .EXAMPLE
    .\Remove-AppxApps.ps1
    Runs the script with the default list of safe packages and removes all other removable AppX packages.

    .EXAMPLE
    .\Remove-AppxApps.ps1 -SafePackagesList @("Microsoft.WindowsCalculator_8wekyb3d8bbwe")
    Runs the script while preserving only the specified package (Microsoft.WindowsCalculator_8wekyb3d8bbwe) and removes all other removable AppX packages.

    .EXAMPLE
    .\Remove-AppxApps.ps1 -Targeted
    Runs the script with a targeted list of packages to be removed during a Windows feature upgrade.

    .NOTES
    - WARNING: If run on an existing desktop, this script may remove applications that users rely on.
    - The script must be run with elevated privileges to remove provisioned packages and delete specific registry keys.
    - The script checks the operating system version to determine whether it is running on Windows 10 or Windows 11 and adjusts the removal process accordingly.
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default", ConfirmImpact = "High")]
param (
    [Parameter(Mandatory = $false, ParameterSetName = "Default")]
    [System.Collections.ArrayList] $SafePackageList = @(
        # Common desktop apps
        "Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe", # Enable basic notes functionality. Supports Microsoft 365 accounts
        "Microsoft.Paint_8wekyb3d8bbwe", # Provides basic image editing functionality
        "Microsoft.PowerAutomateDesktop_8wekyb3d8bbwe", # Desktop automation tool
        "Microsoft.ScreenSketch_8wekyb3d8bbwe", # Capture and annotate screenshots
        "Microsoft.Windows.Photos_8wekyb3d8bbwe", # Basic image viewing. Supports Microsoft 365 accounts
        "Microsoft.WindowsAlarms_8wekyb3d8bbwe", # Clock app with timers, alarms, and world clock. Supports Microsoft 365 accounts
        "Microsoft.WindowsCalculator_8wekyb3d8bbwe", # Calculator app
        "Microsoft.WindowsNotepad_8wekyb3d8bbwe", # Notepad app
        "Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe", # Voice recording app
        "Microsoft.WindowsTerminal_8wekyb3d8bbwe", # Essential terminal app
        "Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe", # Microsoft Edge browser
        "Microsoft.Edge.GameAssist_8wekyb3d8bbwe", # Microsoft Edge browser component
        "Microsoft.ZuneMusic_8wekyb3d8bbwe", # Windows Media Player, video and music player

        # System applications
        "Microsoft.WindowsStore_8wekyb3d8bbwe",
        "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe",
        "Microsoft.ApplicationCompatibilityEnhancements_8wekyb3d8bbwe",
        "Microsoft.SecHealthUI_8wekyb3d8bbwe",
        "Microsoft.StorePurchaseApp_8wekyb3d8bbwe",
        "Microsoft.StartExperiencesApp_8wekyb3d8bbwe",
        "Microsoft.Wallet_8wekyb3d8bbwe",
        "MicrosoftWindows.CrossDevice_cw5n1h2txyewy",
        "MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy",
        "Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe", # Ensure policy disables Widgets 
        "MicrosoftCorporationII.WinAppRuntime.Singleton_8wekyb3d8bbwe",
        "Microsoft.Winget.Source_8wekyb3d8bbwe", # Winget package
        "Microsoft.WindowsPackageManagerManifestCreator_8wekyb3d8bbwe", # App to create manifests for winget
        "Microsoft.OneDriveSync_8wekyb3d8bbwe", # OneDrive sync client

        # Image & video codecs
        "Microsoft.MPEG2VideoExtension_8wekyb3d8bbwe",
        "Microsoft.AV1VideoExtension_8wekyb3d8bbwe",
        "Microsoft.AVCEncoderVideoExtension_8wekyb3d8bbwe",
        "Microsoft.HEIFImageExtension_8wekyb3d8bbwe",
        "Microsoft.HEVCVideoExtension_8wekyb3d8bbwe",
        "Microsoft.RawImageExtension_8wekyb3d8bbwe",
        "Microsoft.VP9VideoExtensions_8wekyb3d8bbwe",
        "Microsoft.WebMediaExtensions_8wekyb3d8bbwe",
        "Microsoft.WebpImageExtension_8wekyb3d8bbwe"),

    [Parameter(Mandatory = $false, ParameterSetName = "Default")]
    [System.Collections.ArrayList] $SafePackageWildCard = @(
        # Packages that include version numbers, so static names aren't effective
        "MicrosoftCorporationII.WinAppRuntime.Main*",
        "Microsoft.WinAppRuntime.DDLM*",
        "Microsoft.LanguageExperiencePack*",
        "Microsoft.Teams.SlimCoreVdi*"),

    # Use Targeted switch to remove a targeted list of packages. Useful for in-place feature updates
    [Parameter(Mandatory = $false, ParameterSetName = "Targeted")]
    [System.Management.Automation.SwitchParameter] $Targeted,

    [Parameter(Mandatory = $false, ParameterSetName = "Targeted")]
    [System.Collections.ArrayList] $TargetedPackageList = @(
        "Microsoft.BingNews_8wekyb3d8bbwe",
        "Microsoft.BingSearch_8wekyb3d8bbwe",
        "Microsoft.BingWeather_8wekyb3d8bbwe",
        # "Microsoft.Copilot_8wekyb3d8bbwe",
        "Microsoft.GetHelp_8wekyb3d8bbwe",
        # "Microsoft.OutlookForWindows_8wekyb3d8bbwe",
        # "Microsoft.Todos_8wekyb3d8bbwe",
        "Microsoft.Windows.DevHome_8wekyb3d8bbwe",
        "Microsoft.WindowsCamera_8wekyb3d8bbwe",
        "microsoft.windowscommunicationsapps_8wekyb3d8bbwe",
        "Microsoft.Xbox.TCUI_8wekyb3d8bbwe",
        "Microsoft.XboxGameOverlay_8wekyb3d8bbwe",
        "Microsoft.XboxIdentityProvider_8wekyb3d8bbwe",
        "Microsoft.XboxSpeechToTextOverlay_8wekyb3d8bbwe",
        "MSTeams_8wekyb3d8bbwe",
        "Microsoft.ZuneVideo_8wekyb3d8bbwe")
)

begin {
    #region Functions
    function Test-IsOobeComplete {
        # https://oofhours.com/2023/09/15/detecting-when-you-are-in-oobe/
        $TypeDef = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace Api {
    public class Kernel32 {
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int OOBEComplete(ref int bIsOOBEComplete);
    }
}
"@
        Add-Type -TypeDefinition $TypeDef -Language "CSharp"
        $IsOOBEComplete = $false
        [Void][Api.Kernel32]::OOBEComplete([ref] $IsOOBEComplete)
        return [System.Boolean]$IsOOBEComplete
    }

    function Add-DeprovisionedPackageKey {
        # Explicitly create the registry key for deprovisioned packages
        # Silently fail if we don't have permissions to create the key
        param (
            [Parameter(Mandatory = $true)]
            [System.String] $PackageFamilyName
        )
        try {
            $Deprovisioned = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned"
            $Path = "$Deprovisioned\$($PackageFamilyName)"
            if (-not(Test-Path -Path $Path)) {
                New-Item -Path $Path -ErrorAction "SilentlyContinue" *>$null
            }
        }
        catch {
            Write-Verbose -Message "Failed to create registry key: $Path. Error: $($_.Exception.Message)"
        }
    }
    #endregion

    # Get elevated status. if elevated we'll remove packages from all users and provisioned packages
    $Role = [Security.Principal.WindowsBuiltInRole] "Administrator"
    [System.Boolean] $Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole($Role)

    if (Test-IsOobeComplete) {
        Write-Warning -Message "OOBE is complete. Removing applications on an existing desktop may remove applications that users rely on."
    }
}

process {
    if ($Targeted -eq $true) {
        # Targeted behavior: remove a specific list of AppX packages
        Write-Verbose -Message "Running with the targeted list of packages."

        # Find all AppX packages on the system and filter them based on the targeted list
        $AppxPackagesToRemove = Get-AppxPackage -AllUsers:$Elevated | Where-Object { $_.PackageFamilyName -in $TargetedPackageList }

        # Remove packages in the targeted list
        $AppxPackagesToRemove | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.PackageFullName, "Remove AppX package")) {
                Remove-AppxPackage -Package $_.PackageFullName -AllUsers:$Elevated
                Add-DeprovisionedPackageKey -PackageFamilyName $_.PackageFamilyName
            }
            $_.PackageFamilyName | Write-Output
        }
    }
    else {
        # Default behavior: remove all AppX packages except for the safe list
        Write-Verbose -Message "Running with the safe list of packages."

        # Find all AppX packages on the system
        $AppxPackages = Get-AppxPackage -AllUsers:$Elevated
        foreach ($Package in $AppxPackages) {
            Write-Verbose -Message "Currently installed package: $($Package.Name)"
        }

        # Remove all AppX packages, except for packages that can't be removed, frameworks, and the safe packages list
        $AppxPackagesToRemove = $AppxPackages | `
            Where-Object { $_.NonRemovable -eq $false -and $_.IsFramework -eq $false -and $_.PackageFamilyName -notin $SafePackageList }

        # Further filter out packages that match the safe wildcard patterns
        $MatchingPackages = $AppxPackagesToRemove | Where-Object {
            $Package = $_.PackageFamilyName
            $SafePackageWildCard | Where-Object { $Package -like $_ }
        }
        if ($MatchingPackages) {
            $AppxPackagesToRemove = $AppxPackagesToRemove | Where-Object { $_.PackageFamilyName -notin $MatchingPackages.PackageFamilyName }
        }
        Write-Verbose -Message "We found $($AppxPackagesToRemove.Count) packages to remove."

        # Check if we're running on Windows 11 or Windows Server 2025, or above
        if ([System.Environment]::OSVersion.Version -ge [System.Version]"10.0.22000") {
            $AppxPackagesToRemove | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.PackageFullName, "Remove AppX package")) {
                    Remove-AppxPackage -Package $_.PackageFullName -AllUsers:$Elevated
                    Add-DeprovisionedPackageKey -PackageFamilyName $_.PackageFamilyName
                }
                $_.PackageFamilyName | Write-Output
            }
        }
        else {
            # OS version is less than 10.0.22000, so we're on Windows 10, Windows Server 2022 or below
            if ($Elevated) {
                $ProvisionedAppxPackages = Get-AppxProvisionedPackage -Online
                $PackagesToRemove = $ProvisionedAppxPackages | Where-Object { $_.DisplayName -in $AppxPackagesToRemove.Name }
                $PackagesToRemove | ForEach-Object {
                    if ($PSCmdlet.ShouldProcess($_.PackageName, "Remove AppX provisioned package")) {
                        Remove-AppxProvisionedPackage -Package $_.PackageName -Online -AllUsers
                        Add-DeprovisionedPackageKey -PackageFamilyName $_.PackageFamilyName
                    }
                    $_.PackageName | Write-Output
                }
            }
            else {
                Write-Error -Message "This script must be run elevated to remove provisioned packages."
            }
        }
    }

    # Delete registry keys that govern the installation of Outlook and DevHome
    if ($Elevated) {
        try {
            reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate" /f *>$null
            reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" /f *>$null
            reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate" /f *>$null
            reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate" /f *>$null
            reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\MS_Outlook" /f *>$null
        }
        catch {
            Write-Verbose -Message "Failed to delete registry keys with: $($_.Exception.Message)."
        }
    }
}

end {
}
