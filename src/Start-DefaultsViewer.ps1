<#
    .SYNOPSIS
    GUI viewer for Windows Enterprise Defaults configuration profiles.
#>
[CmdletBinding(SupportsShouldProcess = $false)]
param(
    [System.String] $ConfigsPath = (Join-Path -Path $PSScriptRoot -ChildPath "configs"),
    [System.String] $SchemaUrl = "https://raw.githubusercontent.com/aaronparker/defaults/refs/heads/main/schema/configuration.schema.json"
)

#region Configure the environment
Set-StrictMode -Version Latest
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
$WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# P/Invoke wrapper used to set the OS title-bar caption colour via DWM
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DwmHelper {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    public const int DWMWA_CAPTION_COLOR = 35;
    public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
}
"@

function Get-ObjectPropertyValue {
    param(
        [System.Object] $Object,
        [System.String] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Get-FallbackSchemaMap {
    $map = @{}

    $map["Description"] = "Human-readable description of the configuration profile."
    $map["MinimumBuild"] = "Minimum Windows build number this profile applies to."
    $map["MaximumBuild"] = "Maximum Windows build number this profile applies to."
    $map["Targets"] = "Target device attributes used to determine profile applicability."
    $map["Targets.Platforms"] = "Supported OS platform categories."
    $map["Targets.Models"] = "Hardware model categories."

    $map["MachineRegistry"] = "Registry operations for HKLM and machine-scoped hives."
    $map["MachineRegistry.ChangeOwner"] = "Registry keys where owner or SID updates are required before modification."
    $map["MachineRegistry.ChangeOwner.Root"] = "Registry root hive."
    $map["MachineRegistry.ChangeOwner.Key"] = "Registry key path."
    $map["MachineRegistry.ChangeOwner.Sid"] = "Security identifier to assign as owner."
    $map["MachineRegistry.ChangeOwner.note"] = "Reason for the ownership change."
    $map["MachineRegistry.Set"] = "Registry values to set at machine scope."
    $map["MachineRegistry.Set.path"] = "Registry key path."
    $map["MachineRegistry.Set.name"] = "Registry value name."
    $map["MachineRegistry.Set.type"] = "Registry value type."
    $map["MachineRegistry.Set.value"] = "Registry value data."
    $map["MachineRegistry.Set.protected"] = "Windows protected registry value."
    $map["MachineRegistry.Set.note"] = "Human-readable explanation for this setting."
    $map["MachineRegistry.Remove"] = "Machine registry paths to remove when present."
    $map["MachineRegistry.Remove.path"] = "Registry path to remove."
    $map["MachineRegistry.Remove.note"] = "Reason for removing this path."

    $map["UserRegistry"] = "Registry operations for HKCU and user-scoped hives."
    $map["UserRegistry.Source"] = "Source profile or group for this user registry block."
    $map["UserRegistry.Set"] = "Registry values to set at user scope."
    $map["UserRegistry.Set.path"] = "Registry key path."
    $map["UserRegistry.Set.name"] = "Registry value name."
    $map["UserRegistry.Set.type"] = "Preferred registry value type field."
    $map["UserRegistry.Set.Type"] = "Legacy casing for registry value type."
    $map["UserRegistry.Set.value"] = "Registry value data."
    $map["UserRegistry.Set.protected"] = "Windows protected registry value."
    $map["UserRegistry.Set.note"] = "Human-readable explanation for this setting."
    $map["UserRegistry.Others"] = "Registry values applied for non-default user contexts."

    $map["Paths"] = "Path operations."
    $map["Paths.Remove"] = "File system paths to remove."

    $map["Features"] = "Optional Windows features configuration."
    $map["Features.Disable"] = "Optional Windows features to disable."

    $map["Capabilities"] = "Windows capability package operations."
    $map["Capabilities.Remove"] = "Capability names to remove."
    $map["Capabilities.Others"] = "Additional capability names to remove for special cases."

    $map["Packages"] = "Provisioned package operations."
    $map["Packages.Remove"] = "Provisioned packages to remove."

    $map["Services"] = "Service control operations and optional role or feature gating."
    $map["Services.Feature"] = "Optional feature or role gate required before applying service actions."
    $map["Services.Start"] = "Service names to start."
    $map["Services.Stop"] = "Service names to stop."
    $map["Services.Restart"] = "Service names to restart."
    $map["Services.Enable"] = "Service names to set as enabled."

    $map["Shortcuts"] = "Shortcut editing operations."
    $map["Shortcuts.Edit"] = "Shortcut files to modify and their target arguments."
    $map["Shortcuts.Edit.Path"] = "Path to the shortcut file."
    $map["Shortcuts.Edit.Arguments"] = "Arguments to assign to the shortcut target."

    $map["Files"] = "File operations to apply during configuration."
    $map["Files.Copy"] = "Copy operations from source to destination."
    $map["Files.Copy.Source"] = "Path to source file or folder."
    $map["Files.Copy.Destination"] = "Path to destination file or folder."

    return $map
}

function Add-SchemaDescriptions {
    param(
        [hashtable] $Map,
        [System.String] $Prefix,
        [System.Object] $Node
    )

    if ($null -eq $Node) {
        return
    }

    $description = Get-ObjectPropertyValue -Object $Node -Name "description"
    if (-not [System.String]::IsNullOrWhiteSpace([System.String] $Prefix) -and -not [System.String]::IsNullOrWhiteSpace([System.String] $description)) {
        $Map[$Prefix] = [System.String] $description
    }

    $properties = Get-ObjectPropertyValue -Object $Node -Name "properties"
    if ($null -ne $properties) {
        foreach ($propertyName in $properties.PSObject.Properties.Name) {
            $childPrefix = if ([System.String]::IsNullOrWhiteSpace($Prefix)) {
                $propertyName
            }
            else {
                "$Prefix.$propertyName"
            }

            Add-SchemaDescriptions -Map $Map -Prefix $childPrefix -Node $properties.$propertyName
        }
    }

    $items = Get-ObjectPropertyValue -Object $Node -Name "items"
    if ($null -ne $items) {
        Add-SchemaDescriptions -Map $Map -Prefix $Prefix -Node $items
    }
}

function Get-SchemaMap {
    param(
        [System.String] $RemoteSchemaUrl
    )

    $map = Get-FallbackSchemaMap

    try {
        $schemaObject = Invoke-RestMethod -Uri $RemoteSchemaUrl -Method Get -TimeoutSec 10

        if ($schemaObject -is [System.String]) {
            $schemaObject = $schemaObject | ConvertFrom-Json
        }

        $properties = Get-ObjectPropertyValue -Object $schemaObject -Name "properties"
        if ($null -ne $properties) {
            foreach ($propertyName in $properties.PSObject.Properties.Name) {
                Add-SchemaDescriptions -Map $map -Prefix $propertyName -Node $properties.$propertyName
            }
        }
    }
    catch {
        Write-Information "Schema fetch failed. Using built-in descriptions only. $($_.Exception.Message)"
    }

    return $map
}

function ConvertTo-DisplayValue {
    param(
        [System.Object] $Value
    )

    if ($null -eq $Value) {
        return "(not set)"
    }

    if ($Value -is [System.Boolean]) {
        return $Value.ToString().ToLowerInvariant()
    }

    if ($Value -is [System.Array]) {
        return [System.String]::Join(", ", $Value)
    }

    return [System.String] $Value
}

function Get-PropertyValue {
    param(
        [System.Object] $Object,
        [System.String[]] $Names
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($name in $Names) {
        $value = Get-ObjectPropertyValue -Object $Object -Name $name
        if ($null -ne $value) {
            return $value
        }
    }

    return $null
}

function New-TextBlock {
    param(
        [System.String] $Text,
        [System.Double] $FontSize = 13,
        [System.Windows.Media.Brush] $Foreground,
        [System.Windows.FontWeight] $Weight = [System.Windows.FontWeights]::Normal,
        [System.Windows.Thickness] $Margin = ([System.Windows.Thickness]::new(0))
    )

    $textBlock = [System.Windows.Controls.TextBlock]::new()
    $textBlock.Text = $Text
    $textBlock.FontSize = $FontSize
    $textBlock.Foreground = $Foreground
    $textBlock.FontWeight = $Weight
    $textBlock.Margin = $Margin
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    return $textBlock
}

function Add-FieldRow {
    param(
        [System.Windows.Controls.Panel] $Parent,
        [System.String] $Label,
        [System.Object] $Value,
        [System.String] $Description,
        [hashtable] $Theme
    )

    $container = [System.Windows.Controls.StackPanel]::new()
    $container.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

    $grid = [System.Windows.Controls.Grid]::new()
    $columnLabel = [System.Windows.Controls.ColumnDefinition]::new()
    $columnLabel.Width = [System.Windows.GridLength]::new(160)
    $columnValue = [System.Windows.Controls.ColumnDefinition]::new()
    $columnValue.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    [void] $grid.ColumnDefinitions.Add($columnLabel)
    [void] $grid.ColumnDefinitions.Add($columnValue)

    $labelBlock = New-TextBlock -Text $Label -FontSize 12 -Foreground $Theme.MutedBrush -Weight ([System.Windows.FontWeights]::SemiBold)
    $valueBlock = New-TextBlock -Text (ConvertTo-DisplayValue -Value $Value) -FontSize 12 -Foreground $Theme.PrimaryTextBrush

    [System.Windows.Controls.Grid]::SetColumn($labelBlock, 0)
    [System.Windows.Controls.Grid]::SetColumn($valueBlock, 1)

    [void] $grid.Children.Add($labelBlock)
    [void] $grid.Children.Add($valueBlock)
    [void] $container.Children.Add($grid)

    if (-not [System.String]::IsNullOrWhiteSpace($Description)) {
        $descriptionBlock = New-TextBlock -Text $Description -FontSize 11 -Foreground $Theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(160, 1, 0, 0))
        [void] $container.Children.Add($descriptionBlock)
    }

    [void] $Parent.Children.Add($container)
}

function New-ItemExpander {
    param(
        [System.Object] $Item,
        [System.String] $Header,
        [System.Object[]] $Fields,
        [System.String] $SchemaPrefix,
        [hashtable] $SchemaMap,
        [hashtable] $Theme
    )

    $expander = [System.Windows.Controls.Expander]::new()
    $expander.Header = $Header
    $expander.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $expander.Padding = [System.Windows.Thickness]::new(8)
    $expander.Background = $Theme.SectionBackgroundBrush
    $expander.BorderBrush = $Theme.BorderBrush
    $expander.BorderThickness = [System.Windows.Thickness]::new(1)
    $expander.Foreground = $Theme.PrimaryTextBrush

    $contentPanel = [System.Windows.Controls.StackPanel]::new()

    $note = Get-PropertyValue -Object $Item -Names @("note", "Note")
    $itemDescription = if (-not [System.String]::IsNullOrWhiteSpace([System.String] $note)) {
        [System.String] $note
    }
    elseif ($SchemaMap.ContainsKey($SchemaPrefix)) {
        [System.String] $SchemaMap[$SchemaPrefix]
    }
    else {
        ""
    }

    if (-not [System.String]::IsNullOrWhiteSpace($itemDescription)) {
        $descriptionCard = [System.Windows.Controls.Border]::new()
        $descriptionCard.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $descriptionCard.Padding = [System.Windows.Thickness]::new(8)
        $descriptionCard.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $descriptionCard.Background = $Theme.CalloutBrush

        $descriptionText = New-TextBlock -Text $itemDescription -FontSize 12 -Foreground $Theme.PrimaryTextBrush
        $descriptionCard.Child = $descriptionText
        [void] $contentPanel.Children.Add($descriptionCard)
    }

    foreach ($field in $Fields) {
        $fieldLabel = [System.String] $field.Label
        $fieldNames = [System.String[]] $field.Names
        $fieldSchemaKey = [System.String] $field.SchemaKey

        $value = Get-PropertyValue -Object $Item -Names $fieldNames
        if ($null -eq $value) {
            continue
        }

        $fieldDescription = ""
        if ($SchemaMap.ContainsKey($fieldSchemaKey)) {
            $fieldDescription = [System.String] $SchemaMap[$fieldSchemaKey]
        }

        Add-FieldRow -Parent $contentPanel -Label $fieldLabel -Value $value -Description $fieldDescription -Theme $Theme
    }

    $expander.Content = $contentPanel
    return $expander
}

function New-StringListGroup {
    param(
        [System.String] $Title,
        [System.Object[]] $Items,
        [System.String] $SchemaKey,
        [hashtable] $SchemaMap,
        [hashtable] $Theme
    )

    $groupPanel = [System.Windows.Controls.StackPanel]::new()
    $groupPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

    $titleText = New-TextBlock -Text ("{0} ({1})" -f $Title, $Items.Count) -FontSize 13 -Foreground $Theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold)
    [void] $groupPanel.Children.Add($titleText)

    if ($SchemaMap.ContainsKey($SchemaKey)) {
        $groupDescription = New-TextBlock -Text ([System.String] $SchemaMap[$SchemaKey]) -FontSize 11 -Foreground $Theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 2, 0, 8))
        [void] $groupPanel.Children.Add($groupDescription)
    }

    if ($Items.Count -eq 0) {
        $emptyState = New-TextBlock -Text "No entries in this group." -FontSize 12 -Foreground $Theme.MutedBrush
        [void] $groupPanel.Children.Add($emptyState)
        return $groupPanel
    }

    foreach ($item in $Items) {
        $itemBorder = [System.Windows.Controls.Border]::new()
        $itemBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        $itemBorder.Padding = [System.Windows.Thickness]::new(8)
        $itemBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $itemBorder.Background = $Theme.SectionBackgroundBrush
        $itemBorder.BorderBrush = $Theme.BorderBrush
        $itemBorder.BorderThickness = [System.Windows.Thickness]::new(1)

        $valueText = New-TextBlock -Text (ConvertTo-DisplayValue -Value $item) -FontSize 12 -Foreground $Theme.PrimaryTextBrush
        $itemBorder.Child = $valueText
        [void] $groupPanel.Children.Add($itemBorder)
    }

    return $groupPanel
}

function New-SectionCard {
    param(
        [System.String] $Title,
        [System.String] $Description,
        [System.Int32] $Count,
        [System.Windows.UIElement] $Content,
        [hashtable] $Theme
    )

    $card = [System.Windows.Controls.Border]::new()
    $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $card.Padding = [System.Windows.Thickness]::new(16)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $card.Background = $Theme.CardBrush
    $card.BorderBrush = $Theme.BorderBrush
    $card.BorderThickness = [System.Windows.Thickness]::new(1)

    $stack = [System.Windows.Controls.StackPanel]::new()

    $titleGrid = [System.Windows.Controls.Grid]::new()
    $titleLeft = [System.Windows.Controls.ColumnDefinition]::new()
    $titleLeft.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $titleRight = [System.Windows.Controls.ColumnDefinition]::new()
    $titleRight.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    [void] $titleGrid.ColumnDefinitions.Add($titleLeft)
    [void] $titleGrid.ColumnDefinitions.Add($titleRight)

    $titleText = New-TextBlock -Text $Title -FontSize 16 -Foreground $Theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold)
    $countText = New-TextBlock -Text ("Items: {0}" -f $Count) -FontSize 12 -Foreground $Theme.MutedBrush

    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)
    [System.Windows.Controls.Grid]::SetColumn($countText, 1)

    [void] $titleGrid.Children.Add($titleText)
    [void] $titleGrid.Children.Add($countText)

    [void] $stack.Children.Add($titleGrid)

    if (-not [System.String]::IsNullOrWhiteSpace($Description)) {
        $descriptionText = New-TextBlock -Text $Description -FontSize 12 -Foreground $Theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 4, 0, 10))
        [void] $stack.Children.Add($descriptionText)
    }

    if ($null -ne $Content) {
        [void] $stack.Children.Add($Content)
    }

    $card.Child = $stack
    return $card
}

function New-Badge {
    param(
        [System.String] $Text,
        [hashtable] $Theme
    )

    $badge = [System.Windows.Controls.Border]::new()
    $badge.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
    $badge.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $badge.CornerRadius = [System.Windows.CornerRadius]::new(12)
    $badge.Background = $Theme.BadgeBrush

    $label = New-TextBlock -Text $Text -FontSize 11 -Foreground $Theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold)
    $badge.Child = $label
    return $badge
}

function Get-OsBuildList {
    param(
        [System.String] $ScriptRoot
    )

    $entries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $csvPaths = @(
        (Join-Path -Path $ScriptRoot -ChildPath "builds\WindowsClient.csv"),
        (Join-Path -Path $ScriptRoot -ChildPath "builds\WindowsServer.csv")
    )

    foreach ($csvPath in $csvPaths) {
        if (Test-Path -Path $csvPath) {
            Import-Csv -Path $csvPath | ForEach-Object {
                $entries.Add([PSCustomObject]@{
                    Label    = $_.Label
                    Build    = $_.Build
                    Platform = $_.Platform
                })
            }
        }
    }

    return , ($entries.ToArray() | Sort-Object -Property @{Expression = { [System.Version] $_.Build }} -Descending)
}

function Get-ConfigEntry {
    param(
        [System.String] $Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Config path not found: $Path"
    }

    $entries = @()
    $files = Get-ChildItem -Path $Path -Filter "*.json" -File | Where-Object { $_.Name -ne "_Configuration.Template.json" } | Sort-Object -Property Name

    foreach ($file in $files) {
        try {
            $raw = Get-Content -Path $file.FullName -Raw
            $config = $raw | ConvertFrom-Json
            $entries += [PSCustomObject]@{
                Name = $file.Name
                FullName = $file.FullName
                ParseError = $null
                Config = $config
            }
        }
        catch {
            $entries += [PSCustomObject]@{
                Name = $file.Name
                FullName = $file.FullName
                ParseError = $_.Exception.Message
                Config = $null
            }
        }
    }

    return ,$entries
}

function Get-ThemeBrushes {
    # Windows 11 Fluent / WinUI 3 design token colours for the Light and Dark themes
    param(
        [ValidateSet("Light", "Dark")]
        [System.String] $Mode = "Light"
    )

    function New-Brush {
        param([System.Byte] $R, [System.Byte] $G, [System.Byte] $B)
        return [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($R, $G, $B))
    }

    if ($Mode -eq "Dark") {
        return @{
            PrimaryTextBrush        = New-Brush 255 255 255  # #FFFFFF  TextPrimary
            SubtleTextBrush         = New-Brush 197 197 197   # #C5C5C5  TextSecondary
            MutedBrush              = New-Brush 157 157 157   # #9D9D9D  TextTertiary
            CardBrush               = New-Brush 44 44 44      # #2C2C2C  LayerFillDefault
            BorderBrush             = New-Brush 59 59 59      # #3B3B3B  StrokeCardDefault
            WindowBrush             = New-Brush 32 32 32      # #202020  MicaBase
            SectionBackgroundBrush  = New-Brush 41 41 41      # #292929  SubtleFillSecondary
            BadgeBrush              = New-Brush 15 58 87      # #0F3A57  AccentLight3 (dark)
            BadgeHoverBrush         = New-Brush 21 74 112     # #154A70  AccentLight3 hover (dark)
            CalloutBrush            = New-Brush 51 51 51      # #333333  SubtleFillDefault
            ErrorBrush              = New-Brush 255 153 164   # #FF99A4  SystemCritical (dark)
            ErrorCardBackgroundBrush = New-Brush 68 39 38     # #442726
            ErrorCardBorderBrush    = New-Brush 241 112 122   # #F1707A
        }
    }

    return @{
        PrimaryTextBrush        = New-Brush 27 27 27      # #1B1B1B  TextPrimary
        SubtleTextBrush         = New-Brush 96 96 96      # #606060  TextSecondary
        MutedBrush              = New-Brush 138 138 138   # #8A8A8A  TextTertiary
        CardBrush               = New-Brush 255 255 255   # #FFFFFF  LayerFillDefault
        BorderBrush             = New-Brush 224 224 224   # #E0E0E0  StrokeCardDefault
        WindowBrush             = New-Brush 243 243 243   # #F3F3F3  MicaBase
        SectionBackgroundBrush  = New-Brush 250 250 250   # #FAFAFA  SubtleFillSecondary
        BadgeBrush              = New-Brush 204 228 247   # #CCE4F7  AccentLight3
        BadgeHoverBrush         = New-Brush 184 217 240   # #B8D9F0  AccentLight3 hover
        CalloutBrush            = New-Brush 245 245 245   # #F5F5F5  SubtleFillDefault
        ErrorBrush              = New-Brush 196 43 28     # #C42B1C  SystemCritical
        ErrorCardBackgroundBrush = New-Brush 254 226 226  # #FEE2E2
        ErrorCardBorderBrush    = New-Brush 248 113 113   # #F87171
    }
}

function Get-SystemThemeMode {
    # Reads the current Windows "app mode" (light/dark) from the registry so the viewer
    # can default to the same theme as the rest of the OS. Falls back to "Light" on
    # Server SKUs or if the value/key does not exist.
    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    try {
        $appsUseLightTheme = Get-ItemPropertyValue -Path $registryPath -Name "AppsUseLightTheme" -ErrorAction "Stop"
        if ($appsUseLightTheme -eq 0) {
            return "Dark"
        }
    }
    catch {
        # Value or key not present (e.g. Windows Server); default to Light
    }

    return "Light"
}

function ConvertTo-HexColor {
    # Renders a SolidColorBrush back to a "#RRGGBB" string for embedding into the XAML
    # resource dictionary seed values.
    param(
        [System.Windows.Media.SolidColorBrush] $Brush
    )

    $color = $Brush.Color
    return ("#{0:X2}{1:X2}{2:X2}" -f $color.R, $color.G, $color.B)
}

$script:themeMode = Get-SystemThemeMode
$script:theme = Get-ThemeBrushes -Mode $script:themeMode
$theme = $script:theme

[xml] $windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Enterprise Defaults"
        Width="1280"
        Height="800"
        MinWidth="1100"
        MinHeight="680"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI Variable Text, Segoe UI"
        Background="{DynamicResource Brush.Window}"
        UseLayoutRounding="True">
    <Window.Resources>

        <SolidColorBrush x:Key="Brush.PrimaryText" Color="$(ConvertTo-HexColor $script:theme.PrimaryTextBrush)" />
        <SolidColorBrush x:Key="Brush.SubtleText" Color="$(ConvertTo-HexColor $script:theme.SubtleTextBrush)" />
        <SolidColorBrush x:Key="Brush.Muted" Color="$(ConvertTo-HexColor $script:theme.MutedBrush)" />
        <SolidColorBrush x:Key="Brush.Card" Color="$(ConvertTo-HexColor $script:theme.CardBrush)" />
        <SolidColorBrush x:Key="Brush.Border" Color="$(ConvertTo-HexColor $script:theme.BorderBrush)" />
        <SolidColorBrush x:Key="Brush.Window" Color="$(ConvertTo-HexColor $script:theme.WindowBrush)" />
        <SolidColorBrush x:Key="Brush.SectionBackground" Color="$(ConvertTo-HexColor $script:theme.SectionBackgroundBrush)" />
        <SolidColorBrush x:Key="Brush.Badge" Color="$(ConvertTo-HexColor $script:theme.BadgeBrush)" />
        <SolidColorBrush x:Key="Brush.BadgeHover" Color="$(ConvertTo-HexColor $script:theme.BadgeHoverBrush)" />
        <SolidColorBrush x:Key="Brush.Callout" Color="$(ConvertTo-HexColor $script:theme.CalloutBrush)" />
        <SolidColorBrush x:Key="Brush.Error" Color="$(ConvertTo-HexColor $script:theme.ErrorBrush)" />
        <SolidColorBrush x:Key="Brush.ErrorCardBackground" Color="$(ConvertTo-HexColor $script:theme.ErrorCardBackgroundBrush)" />
        <SolidColorBrush x:Key="Brush.ErrorCardBorder" Color="$(ConvertTo-HexColor $script:theme.ErrorCardBorderBrush)" />
        <SolidColorBrush x:Key="Brush.Accent" Color="#0078D4" />

        <!-- Fluent ScrollBar thumb: rounded, colour-reactive -->
        <Style x:Key="FluentScrollThumb" TargetType="Thumb">
            <Setter Property="IsTabStop" Value="False" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border Name="ThumbFill" Background="{DynamicResource Brush.Muted}" CornerRadius="3" />
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ThumbFill" Property="Background" Value="{DynamicResource Brush.SubtleText}" />
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="ThumbFill" Property="Background" Value="{DynamicResource Brush.PrimaryText}" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Transparent page-click area (replaces visible track segments) -->
        <Style x:Key="FluentScrollPageButton" TargetType="RepeatButton">
            <Setter Property="IsTabStop" Value="False" />
            <Setter Property="Focusable" Value="False" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Rectangle Fill="Transparent" />
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent ScrollBar: 6 px wide, transparent track, no arrow buttons -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="6" />
            <Setter Property="MinWidth" Value="6" />
            <Setter Property="Margin" Value="2,4" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand"
                                                  Style="{StaticResource FluentScrollPageButton}" />
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource FluentScrollThumb}" />
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand"
                                                  Style="{StaticResource FluentScrollPageButton}" />
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent ListBoxItem: Transparent default, callout hover, badge selected -->
        <Style x:Key="FluentListBoxItem" TargetType="ListBoxItem">
            <Setter Property="Padding" Value="10,8" />
            <Setter Property="Margin" Value="0,1" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{DynamicResource Brush.PrimaryText}" />
            <Setter Property="HorizontalContentAlignment" Value="Stretch" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border Name="ItemBorder"
                                Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}"
                                CornerRadius="4">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.Callout}" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.Badge}" />
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsSelected" Value="True" />
                                    <Condition Property="IsMouseOver" Value="True" />
                                </MultiTrigger.Conditions>
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.BadgeHover}" />
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent ComboBox toggle button: draws border + chevron, no content area -->
        <Style x:Key="FluentComboBoxToggleButton" TargetType="ToggleButton">
            <Setter Property="Focusable" Value="False" />
            <Setter Property="ClickMode" Value="Press" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border Name="ToggleBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <Path Name="Arrow"
                                  Data="M 0 0 L 4 4 L 8 0"
                                  Stroke="{DynamicResource Brush.SubtleText}"
                                  StrokeThickness="1.5"
                                  HorizontalAlignment="Right"
                                  VerticalAlignment="Center"
                                  Margin="0,0,10,0"
                                  SnapsToDevicePixels="True" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ToggleBorder" Property="Background" Value="{DynamicResource Brush.Callout}" />
                                <Setter TargetName="ToggleBorder" Property="BorderBrush" Value="{DynamicResource Brush.Muted}" />
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="ToggleBorder" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent ComboBoxItem -->
        <Style x:Key="FluentComboBoxItem" TargetType="ComboBoxItem">
            <Setter Property="Padding" Value="10,6" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{DynamicResource Brush.PrimaryText}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border Name="ItemBorder"
                                Background="Transparent"
                                Padding="{TemplateBinding Padding}"
                                CornerRadius="4"
                                Margin="2,1">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.Callout}" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.Badge}" />
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsSelected" Value="True" />
                                    <Condition Property="IsHighlighted" Value="True" />
                                </MultiTrigger.Conditions>
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource Brush.BadgeHover}" />
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent ComboBox: rounded border, custom chevron, styled dropdown -->
        <Style x:Key="FluentComboBox" TargetType="ComboBox">
            <Setter Property="Height" Value="32" />
            <Setter Property="VerticalContentAlignment" Value="Center" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{DynamicResource Brush.PrimaryText}" />
            <Setter Property="Background" Value="{DynamicResource Brush.Card}" />
            <Setter Property="BorderBrush" Value="{DynamicResource Brush.Border}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="ItemContainerStyle" Value="{StaticResource FluentComboBoxItem}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Name="ToggleButton"
                                          Background="{TemplateBinding Background}"
                                          BorderBrush="{TemplateBinding BorderBrush}"
                                          BorderThickness="{TemplateBinding BorderThickness}"
                                          IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"
                                          Style="{StaticResource FluentComboBoxToggleButton}" />
                            <ContentPresenter Name="ContentSite"
                                              IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="10,0,28,0"
                                              VerticalAlignment="Center" />
                            <Popup Name="PART_Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Fade">
                                <Border Name="DropDownBorder"
                                        MinWidth="{TemplateBinding ActualWidth}"
                                        MaxHeight="300"
                                        Background="{DynamicResource Brush.Card}"
                                        BorderBrush="{DynamicResource Brush.Border}"
                                        BorderThickness="1"
                                        CornerRadius="4"
                                        Margin="0,2,0,0">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                                        <ItemsPresenter />
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Fluent secondary Button: rounded, colour-reactive hover/pressed/focus states -->
        <Style x:Key="FluentButton" TargetType="Button">
            <Setter Property="Height" Value="32" />
            <Setter Property="Padding" Value="12,0" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{DynamicResource Brush.PrimaryText}" />
            <Setter Property="Background" Value="{DynamicResource Brush.Card}" />
            <Setter Property="BorderBrush" Value="{DynamicResource Brush.Border}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource Brush.Callout}" />
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource Brush.Muted}" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource Brush.Border}" />
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
                            </Trigger>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource Brush.Callout}" />
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource Brush.Border}" />
                                <Setter Property="Foreground" Value="{DynamicResource Brush.Muted}" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="{DynamicResource Brush.Card}" BorderBrush="{DynamicResource Brush.Border}" BorderThickness="1" CornerRadius="8" Padding="16,12" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Vertical">
                    <TextBlock Text="Enterprise Defaults Viewer" FontSize="20" FontWeight="SemiBold" Foreground="{DynamicResource Brush.PrimaryText}" />
                    <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                        <TextBlock Name="SubtitleTextBlock" FontSize="12" Foreground="{DynamicResource Brush.SubtleText}" VerticalAlignment="Center" />
                        <Button Name="BrowseConfigsPathButton"
                                Content="Browse..."
                                Style="{StaticResource FluentButton}"
                                Height="22"
                                Padding="10,0"
                                FontSize="11"
                                Margin="10,0,0,0" />
                    </StackPanel>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
                    <Button Name="ThemeToggleButton"
                            Content="$( if ($script:themeMode -eq "Dark") { [System.Char]::ConvertFromUtf32(0x1F319) } else { [System.Char]::ConvertFromUtf32(0x2600) } )"
                            ToolTip="$( if ($script:themeMode -eq "Dark") { "Switch to light theme" } else { "Switch to dark theme" } )"
                            Style="{StaticResource FluentButton}"
                            Height="28"
                            Width="32"
                            Padding="0"
                            FontSize="14"
                            Margin="0,0,16,0" />
                    <TextBlock Text="OS:" FontSize="12" Foreground="{DynamicResource Brush.SubtleText}" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0" />
                    <ComboBox Name="OsComboBox" Style="{StaticResource FluentComboBox}" MinWidth="200" Margin="0,0,16,0">
                        <ComboBox.ItemTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding Label}" />
                            </DataTemplate>
                        </ComboBox.ItemTemplate>
                    </ComboBox>
                    <TextBlock Text="Model:" FontSize="12" Foreground="{DynamicResource Brush.SubtleText}" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0" />
                    <ComboBox Name="ModelComboBox" Style="{StaticResource FluentComboBox}" MinWidth="120" />
                </StackPanel>
            </Grid>
        </Border>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="300" />
                <ColumnDefinition Width="12" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="{DynamicResource Brush.Card}" BorderBrush="{DynamicResource Brush.Border}" BorderThickness="1" CornerRadius="8" Padding="8">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="*" />
                    </Grid.RowDefinitions>
                    <TextBlock Name="ListHeaderTextBlock" Grid.Row="0" FontSize="13" FontWeight="SemiBold" Foreground="{DynamicResource Brush.PrimaryText}" Margin="4,4,4,8" />
                    <ListBox Name="ConfigsListBox" Grid.Row="1"
                             DisplayMemberPath="Name"
                             BorderThickness="0"
                             Background="Transparent"
                             ItemContainerStyle="{StaticResource FluentListBoxItem}"
                             ScrollViewer.HorizontalScrollBarVisibility="Disabled" />
                </Grid>
            </Border>

            <Border Grid.Column="2" Background="{DynamicResource Brush.Card}" BorderBrush="{DynamicResource Brush.Border}" BorderThickness="1" CornerRadius="8" Padding="16">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Name="DetailsPanel" />
                </ScrollViewer>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($windowXaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$configsListBox = [System.Windows.Controls.ListBox] $window.FindName("ConfigsListBox")
$detailsPanel = [System.Windows.Controls.StackPanel] $window.FindName("DetailsPanel")
$listHeaderTextBlock = [System.Windows.Controls.TextBlock] $window.FindName("ListHeaderTextBlock")
$subtitleTextBlock = [System.Windows.Controls.TextBlock] $window.FindName("SubtitleTextBlock")
$osComboBox = [System.Windows.Controls.ComboBox] $window.FindName("OsComboBox")
$modelComboBox = [System.Windows.Controls.ComboBox] $window.FindName("ModelComboBox")
$browseConfigsPathButton = [System.Windows.Controls.Button] $window.FindName("BrowseConfigsPathButton")
$themeToggleButton = [System.Windows.Controls.Button] $window.FindName("ThemeToggleButton")

function Set-SubtitleText {
    $subtitleTextBlock.Text = "Configuration profiles viewer. Path: $ConfigsPath"
}

Set-SubtitleText

$schemaMap = Get-SchemaMap -RemoteSchemaUrl $SchemaUrl
$script:allConfigEntries = @()

# Populate OS ComboBox from the Windows client and server build CSV files
$osBuildList = Get-OsBuildList -ScriptRoot $PSScriptRoot
[void] $osComboBox.Items.Add([PSCustomObject]@{ Label = "All OS"; Build = $null; Platform = $null })
foreach ($osBuildEntry in $osBuildList) {
    [void] $osComboBox.Items.Add($osBuildEntry)
}
$osComboBox.SelectedIndex = 0

# Populate Model ComboBox
foreach ($modelLabel in @("All", "Physical", "Virtual")) {
    [void] $modelComboBox.Items.Add($modelLabel)
}
$modelComboBox.SelectedIndex = 0

function Add-EmptyMessage {
    param(
        [System.String] $Message
    )

    $messageCard = [System.Windows.Controls.Border]::new()
    $messageCard.Padding = [System.Windows.Thickness]::new(16)
    $messageCard.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $messageCard.Background = $theme.SectionBackgroundBrush
    $messageCard.BorderBrush = $theme.BorderBrush
    $messageCard.BorderThickness = [System.Windows.Thickness]::new(1)

    $messageText = New-TextBlock -Text $Message -FontSize 13 -Foreground $theme.SubtleTextBrush
    $messageCard.Child = $messageText
    [void] $detailsPanel.Children.Add($messageCard)
}

function Add-GroupFromObjects {
    param(
        [System.Windows.Controls.Panel] $Parent,
        [System.String] $Title,
        [System.Object[]] $Items,
        [ScriptBlock] $HeaderFactory,
        [System.Object[]] $Fields,
        [System.String] $Prefix
    )

    $titleBlock = New-TextBlock -Text ("{0} ({1})" -f $Title, $Items.Count) -FontSize 14 -Foreground $theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold) -Margin ([System.Windows.Thickness]::new(0, 0, 0, 6))
    [void] $Parent.Children.Add($titleBlock)

    if ($schemaMap.ContainsKey($Prefix)) {
        $groupDescription = New-TextBlock -Text ([System.String] $schemaMap[$Prefix]) -FontSize 11 -Foreground $theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 0, 0, 8))
        [void] $Parent.Children.Add($groupDescription)
    }

    if ($Items.Count -eq 0) {
        $emptyText = New-TextBlock -Text "No entries in this group." -FontSize 12 -Foreground $theme.MutedBrush -Margin ([System.Windows.Thickness]::new(0, 0, 0, 8))
        [void] $Parent.Children.Add($emptyText)
        return
    }

    foreach ($item in $Items) {
        $header = [System.String] (& $HeaderFactory $item)
        $expander = New-ItemExpander -Item $item -Header $header -Fields $Fields -SchemaPrefix $Prefix -SchemaMap $schemaMap -Theme $theme
        [void] $Parent.Children.Add($expander)
    }
}

function Add-ConfigSummary {
    param(
        [System.Object] $Config,
        [System.String] $Name
    )

    $summaryPanel = [System.Windows.Controls.StackPanel]::new()

    $description = [System.String] (Get-PropertyValue -Object $Config -Names @("Description"))
    if ([System.String]::IsNullOrWhiteSpace($description)) {
        $description = "No description provided."
    }

    $title = New-TextBlock -Text $Name -FontSize 22 -Foreground $theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::Bold)
    $desc = New-TextBlock -Text $description -FontSize 13 -Foreground $theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 4, 0, 12))

    [void] $summaryPanel.Children.Add($title)
    [void] $summaryPanel.Children.Add($desc)

    Add-FieldRow -Parent $summaryPanel -Label "Minimum Build" -Value (Get-PropertyValue -Object $Config -Names @("MinimumBuild")) -Description ($schemaMap["MinimumBuild"]) -Theme $theme
    Add-FieldRow -Parent $summaryPanel -Label "Maximum Build" -Value (Get-PropertyValue -Object $Config -Names @("MaximumBuild")) -Description ($schemaMap["MaximumBuild"]) -Theme $theme

    $targets = Get-PropertyValue -Object $Config -Names @("Targets")
    $platforms = @(Get-PropertyValue -Object $targets -Names @("Platforms"))
    $models = @(Get-PropertyValue -Object $targets -Names @("Models"))

    $targetsLabel = New-TextBlock -Text "Targets" -FontSize 12 -Foreground $theme.MutedBrush -Weight ([System.Windows.FontWeights]::SemiBold)
    [void] $summaryPanel.Children.Add($targetsLabel)

    $badgePanel = [System.Windows.Controls.WrapPanel]::new()
    $badgePanel.Margin = [System.Windows.Thickness]::new(0, 3, 0, 6)

    foreach ($platform in $platforms) {
        [void] $badgePanel.Children.Add((New-Badge -Text ("Platform: {0}" -f $platform) -Theme $theme))
    }
    foreach ($model in $models) {
        [void] $badgePanel.Children.Add((New-Badge -Text ("Model: {0}" -f $model) -Theme $theme))
    }

    if (($platforms.Count + $models.Count) -eq 0) {
        [void] $badgePanel.Children.Add((New-TextBlock -Text "No target metadata available." -FontSize 12 -Foreground $theme.MutedBrush))
    }

    [void] $summaryPanel.Children.Add($badgePanel)

    $summaryCard = New-SectionCard -Title "Profile Summary" -Description "Core metadata and target applicability for this configuration file." -Count 1 -Content $summaryPanel -Theme $theme
    [void] $detailsPanel.Children.Add($summaryCard)
}

function Add-MachineRegistrySection {
    param(
        [System.Object] $MachineRegistry
    )

    $changeOwnerItems = @(Get-PropertyValue -Object $MachineRegistry -Names @("ChangeOwner"))
    $setItems = @(Get-PropertyValue -Object $MachineRegistry -Names @("Set"))
    $removeItems = @(Get-PropertyValue -Object $MachineRegistry -Names @("Remove"))
    $total = $changeOwnerItems.Count + $setItems.Count + $removeItems.Count

    $body = [System.Windows.Controls.StackPanel]::new()

    Add-GroupFromObjects -Parent $body -Title "ChangeOwner" -Items $changeOwnerItems -HeaderFactory { param($item) "{0}\\{1}" -f (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("Root"))), (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("Key"))) } -Fields @(
        @{ Label = "Root"; Names = @("Root"); SchemaKey = "MachineRegistry.ChangeOwner.Root" },
        @{ Label = "Key"; Names = @("Key"); SchemaKey = "MachineRegistry.ChangeOwner.Key" },
        @{ Label = "SID"; Names = @("Sid", "SID"); SchemaKey = "MachineRegistry.ChangeOwner.Sid" },
        @{ Label = "Note"; Names = @("note", "Note"); SchemaKey = "MachineRegistry.ChangeOwner.note" }
    ) -Prefix "MachineRegistry.ChangeOwner"

    Add-GroupFromObjects -Parent $body -Title "Set" -Items $setItems -HeaderFactory { param($item) "{0}  ->  {1}" -f (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("path", "Path"))), (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("name", "Name"))) } -Fields @(
        @{ Label = "Path"; Names = @("path", "Path"); SchemaKey = "MachineRegistry.Set.path" },
        @{ Label = "Name"; Names = @("name", "Name"); SchemaKey = "MachineRegistry.Set.name" },
        @{ Label = "Type"; Names = @("type", "Type"); SchemaKey = "MachineRegistry.Set.type" },
        @{ Label = "Value"; Names = @("value", "Value"); SchemaKey = "MachineRegistry.Set.value" },
        @{ Label = "Protected"; Names = @("protected", "Protected"); SchemaKey = "MachineRegistry.Set.protected" },
        @{ Label = "Note"; Names = @("note", "Note"); SchemaKey = "MachineRegistry.Set.note" }
    ) -Prefix "MachineRegistry.Set"

    Add-GroupFromObjects -Parent $body -Title "Remove" -Items $removeItems -HeaderFactory { param($item) (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("path", "Path"))) } -Fields @(
        @{ Label = "Path"; Names = @("path", "Path"); SchemaKey = "MachineRegistry.Remove.path" },
        @{ Label = "Note"; Names = @("note", "Note"); SchemaKey = "MachineRegistry.Remove.note" }
    ) -Prefix "MachineRegistry.Remove"

    $card = New-SectionCard -Title "MachineRegistry" -Description ($schemaMap["MachineRegistry"]) -Count $total -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Add-UserRegistrySection {
    param(
        [System.Object] $UserRegistry
    )

    $setItems = @(Get-PropertyValue -Object $UserRegistry -Names @("Set"))
    $otherItems = @(Get-PropertyValue -Object $UserRegistry -Names @("Others"))
    $source = Get-PropertyValue -Object $UserRegistry -Names @("Source")
    $total = $setItems.Count + $otherItems.Count

    $body = [System.Windows.Controls.StackPanel]::new()

    if (-not [System.String]::IsNullOrWhiteSpace([System.String] $source)) {
        $sourceBox = [System.Windows.Controls.Border]::new()
        $sourceBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $sourceBox.Padding = [System.Windows.Thickness]::new(8)
        $sourceBox.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $sourceBox.Background = $theme.CalloutBrush

        $sourceText = New-TextBlock -Text ("Source: {0}" -f $source) -FontSize 12 -Foreground $theme.PrimaryTextBrush
        $sourceBox.Child = $sourceText
        [void] $body.Children.Add($sourceBox)
    }

    Add-GroupFromObjects -Parent $body -Title "Set" -Items $setItems -HeaderFactory { param($item) "{0}  ->  {1}" -f (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("path", "Path"))), (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("name", "Name"))) } -Fields @(
        @{ Label = "Path"; Names = @("path", "Path"); SchemaKey = "UserRegistry.Set.path" },
        @{ Label = "Name"; Names = @("name", "Name"); SchemaKey = "UserRegistry.Set.name" },
        @{ Label = "Type"; Names = @("type", "Type"); SchemaKey = "UserRegistry.Set.type" },
        @{ Label = "Value"; Names = @("value", "Value"); SchemaKey = "UserRegistry.Set.value" },
        @{ Label = "Protected"; Names = @("protected", "Protected"); SchemaKey = "UserRegistry.Set.protected" },
        @{ Label = "Note"; Names = @("note", "Note"); SchemaKey = "UserRegistry.Set.note" }
    ) -Prefix "UserRegistry.Set"

    Add-GroupFromObjects -Parent $body -Title "Others" -Items $otherItems -HeaderFactory { param($item) "{0}  ->  {1}" -f (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("path", "Path"))), (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("name", "Name"))) } -Fields @(
        @{ Label = "Path"; Names = @("path", "Path"); SchemaKey = "UserRegistry.Set.path" },
        @{ Label = "Name"; Names = @("name", "Name"); SchemaKey = "UserRegistry.Set.name" },
        @{ Label = "Type"; Names = @("type", "Type"); SchemaKey = "UserRegistry.Set.type" },
        @{ Label = "Value"; Names = @("value", "Value"); SchemaKey = "UserRegistry.Set.value" },
        @{ Label = "Protected"; Names = @("protected", "Protected"); SchemaKey = "UserRegistry.Set.protected" },
        @{ Label = "Note"; Names = @("note", "Note"); SchemaKey = "UserRegistry.Set.note" }
    ) -Prefix "UserRegistry.Others"

    $card = New-SectionCard -Title "UserRegistry" -Description ($schemaMap["UserRegistry"]) -Count $total -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Add-SimpleStringSection {
    param(
        [System.String] $SectionName,
        [System.String] $GroupTitle,
        [System.Object[]] $Items,
        [System.String] $SchemaKey
    )

    $body = New-StringListGroup -Title $GroupTitle -Items $Items -SchemaKey $SchemaKey -SchemaMap $schemaMap -Theme $theme
    $description = ""
    if ($schemaMap.ContainsKey($SectionName)) {
        $description = [System.String] $schemaMap[$SectionName]
    }
    $card = New-SectionCard -Title $SectionName -Description $description -Count $Items.Count -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Add-ServicesSection {
    param(
        [System.Object] $Services
    )

    $startItems = @(Get-PropertyValue -Object $Services -Names @("Start"))
    $stopItems = @(Get-PropertyValue -Object $Services -Names @("Stop"))
    $restartItems = @(Get-PropertyValue -Object $Services -Names @("Restart"))
    $enableItems = @(Get-PropertyValue -Object $Services -Names @("Enable"))
    $feature = Get-PropertyValue -Object $Services -Names @("Feature")

    $total = $startItems.Count + $stopItems.Count + $restartItems.Count + $enableItems.Count
    if (-not [System.String]::IsNullOrWhiteSpace([System.String] $feature)) {
        $total += 1
    }

    $body = [System.Windows.Controls.StackPanel]::new()

    if (-not [System.String]::IsNullOrWhiteSpace([System.String] $feature)) {
        $featureBorder = [System.Windows.Controls.Border]::new()
        $featureBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $featureBorder.Padding = [System.Windows.Thickness]::new(8)
        $featureBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $featureBorder.Background = $theme.CalloutBrush

        $featureLabel = New-TextBlock -Text ("Feature gate: {0}" -f $feature) -FontSize 12 -Foreground $theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold)
        $featureDescription = New-TextBlock -Text ($schemaMap["Services.Feature"]) -FontSize 11 -Foreground $theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 2, 0, 0))

        $featurePanel = [System.Windows.Controls.StackPanel]::new()
        [void] $featurePanel.Children.Add($featureLabel)
        [void] $featurePanel.Children.Add($featureDescription)

        $featureBorder.Child = $featurePanel
        [void] $body.Children.Add($featureBorder)
    }

    [void] $body.Children.Add((New-StringListGroup -Title "Start" -Items $startItems -SchemaKey "Services.Start" -SchemaMap $schemaMap -Theme $theme))
    [void] $body.Children.Add((New-StringListGroup -Title "Stop" -Items $stopItems -SchemaKey "Services.Stop" -SchemaMap $schemaMap -Theme $theme))
    [void] $body.Children.Add((New-StringListGroup -Title "Restart" -Items $restartItems -SchemaKey "Services.Restart" -SchemaMap $schemaMap -Theme $theme))
    [void] $body.Children.Add((New-StringListGroup -Title "Enable" -Items $enableItems -SchemaKey "Services.Enable" -SchemaMap $schemaMap -Theme $theme))

    $card = New-SectionCard -Title "Services" -Description ($schemaMap["Services"]) -Count $total -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Add-ShortcutsSection {
    param(
        [System.Object] $Shortcuts
    )

    $editItems = @(Get-PropertyValue -Object $Shortcuts -Names @("Edit"))

    $body = [System.Windows.Controls.StackPanel]::new()

    Add-GroupFromObjects -Parent $body -Title "Edit" -Items $editItems -HeaderFactory { param($item) (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("Path"))) } -Fields @(
        @{ Label = "Path"; Names = @("Path", "path"); SchemaKey = "Shortcuts.Edit.Path" },
        @{ Label = "Arguments"; Names = @("Arguments", "arguments"); SchemaKey = "Shortcuts.Edit.Arguments" }
    ) -Prefix "Shortcuts.Edit"

    $card = New-SectionCard -Title "Shortcuts" -Description ($schemaMap["Shortcuts"]) -Count $editItems.Count -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Add-FilesSection {
    param(
        [System.Object] $FilesSection
    )

    $copyItems = @(Get-PropertyValue -Object $FilesSection -Names @("Copy"))
    $body = [System.Windows.Controls.StackPanel]::new()

    $fields = @(
        @{ Label = "Source"; Names = @("Source", "source"); SchemaKey = "Files.Copy.Source" },
        @{ Label = "Destination"; Names = @("Destination", "destination"); SchemaKey = "Files.Copy.Destination" }
    )

    Add-GroupFromObjects -Parent $body -Title "Copy" -Items $copyItems -HeaderFactory {
        param($item)
        "{0}  ->  {1}" -f (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("Source", "source"))), (ConvertTo-DisplayValue (Get-PropertyValue -Object $item -Names @("Destination", "destination")))
    } -Fields $fields -Prefix "Files.Copy"

    if ($copyItems.Count -gt 0) {
        $resolvedCard = [System.Windows.Controls.Border]::new()
        $resolvedCard.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $resolvedCard.Padding = [System.Windows.Thickness]::new(8)
        $resolvedCard.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $resolvedCard.Background = $theme.CalloutBrush

        $resolvedPanel = [System.Windows.Controls.StackPanel]::new()
        [void] $resolvedPanel.Children.Add((New-TextBlock -Text "Resolved source previews" -FontSize 12 -Foreground $theme.PrimaryTextBrush -Weight ([System.Windows.FontWeights]::SemiBold) -Margin ([System.Windows.Thickness]::new(0, 0, 0, 6))))

        foreach ($item in $copyItems) {
            $source = [System.String] (Get-PropertyValue -Object $item -Names @("Source", "source"))
            if ([System.String]::IsNullOrWhiteSpace($source)) {
                continue
            }

            $resolved = Join-Path -Path $PSScriptRoot -ChildPath $source
            [void] $resolvedPanel.Children.Add((New-TextBlock -Text ("{0} => {1}" -f $source, $resolved) -FontSize 11 -Foreground $theme.SubtleTextBrush -Margin ([System.Windows.Thickness]::new(0, 0, 0, 3))))
        }

        $resolvedCard.Child = $resolvedPanel
        [void] $body.Children.Add($resolvedCard)
    }

    $card = New-SectionCard -Title "Files" -Description ($schemaMap["Files"]) -Count $copyItems.Count -Content $body -Theme $theme
    [void] $detailsPanel.Children.Add($card)
}

function Render-Config {
    param(
        [System.Object] $Entry
    )

    $detailsPanel.Children.Clear()

    if ($null -eq $Entry) {
        Add-EmptyMessage -Message "Select a configuration file from the left pane to view details."
        return
    }

    if (-not [System.String]::IsNullOrWhiteSpace([System.String] $Entry.ParseError)) {
        $errorCard = [System.Windows.Controls.Border]::new()
        $errorCard.Padding = [System.Windows.Thickness]::new(14)
        $errorCard.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $errorCard.Background = $theme.ErrorCardBackgroundBrush
        $errorCard.BorderBrush = $theme.ErrorCardBorderBrush
        $errorCard.BorderThickness = [System.Windows.Thickness]::new(1)

        $errorPanel = [System.Windows.Controls.StackPanel]::new()
        [void] $errorPanel.Children.Add((New-TextBlock -Text ("Unable to parse {0}" -f $Entry.Name) -FontSize 16 -Foreground $theme.ErrorBrush -Weight ([System.Windows.FontWeights]::Bold)))
        [void] $errorPanel.Children.Add((New-TextBlock -Text ([System.String] $Entry.ParseError) -FontSize 12 -Foreground $theme.ErrorBrush -Margin ([System.Windows.Thickness]::new(0, 4, 0, 0))))
        $errorCard.Child = $errorPanel
        [void] $detailsPanel.Children.Add($errorCard)
        return
    }

    $config = $Entry.Config

    Add-ConfigSummary -Config $config -Name $Entry.Name
    Add-MachineRegistrySection -MachineRegistry (Get-PropertyValue -Object $config -Names @("MachineRegistry"))
    Add-UserRegistrySection -UserRegistry (Get-PropertyValue -Object $config -Names @("UserRegistry"))

    Add-SimpleStringSection -SectionName "Paths" -GroupTitle "Remove" -Items @(Get-PropertyValue -Object (Get-PropertyValue -Object $config -Names @("Paths")) -Names @("Remove")) -SchemaKey "Paths.Remove"
    Add-SimpleStringSection -SectionName "Features" -GroupTitle "Disable" -Items @(Get-PropertyValue -Object (Get-PropertyValue -Object $config -Names @("Features")) -Names @("Disable")) -SchemaKey "Features.Disable"

    $capabilities = Get-PropertyValue -Object $config -Names @("Capabilities")
    $capBody = [System.Windows.Controls.StackPanel]::new()
    [void] $capBody.Children.Add((New-StringListGroup -Title "Remove" -Items @(Get-PropertyValue -Object $capabilities -Names @("Remove")) -SchemaKey "Capabilities.Remove" -SchemaMap $schemaMap -Theme $theme))
    [void] $capBody.Children.Add((New-StringListGroup -Title "Others" -Items @(Get-PropertyValue -Object $capabilities -Names @("Others")) -SchemaKey "Capabilities.Others" -SchemaMap $schemaMap -Theme $theme))
    [void] $detailsPanel.Children.Add((New-SectionCard -Title "Capabilities" -Description ($schemaMap["Capabilities"]) -Count (@(Get-PropertyValue -Object $capabilities -Names @("Remove")).Count + @(Get-PropertyValue -Object $capabilities -Names @("Others")).Count) -Content $capBody -Theme $theme))

    Add-SimpleStringSection -SectionName "Packages" -GroupTitle "Remove" -Items @(Get-PropertyValue -Object (Get-PropertyValue -Object $config -Names @("Packages")) -Names @("Remove")) -SchemaKey "Packages.Remove"

    Add-ServicesSection -Services (Get-PropertyValue -Object $config -Names @("Services"))
    Add-ShortcutsSection -Shortcuts (Get-PropertyValue -Object $config -Names @("Shortcuts"))
    Add-FilesSection -FilesSection (Get-PropertyValue -Object $config -Names @("Files"))
}

function Apply-ConfigFilter {
    $selectedOs = $osComboBox.SelectedItem
    $selectedModel = [System.String] $modelComboBox.SelectedItem

    $filtered = $script:allConfigEntries

    if ($null -ne $selectedOs -and $null -ne $selectedOs.Build) {
        $osVersion = [System.Version] $selectedOs.Build
        $platform  = [System.String] $selectedOs.Platform

        $filtered = $filtered | Where-Object {
            if (-not [System.String]::IsNullOrWhiteSpace([System.String] $_.ParseError)) { return $true }
            $targets  = Get-PropertyValue -Object $_.Config -Names @("Targets")
            $platforms = @(Get-PropertyValue -Object $targets -Names @("Platforms"))
            $minBuild = Get-PropertyValue -Object $_.Config -Names @("MinimumBuild")
            $maxBuild = Get-PropertyValue -Object $_.Config -Names @("MaximumBuild")

            $platformMatch = $platform -in $platforms
            $minMatch = $null -eq $minBuild -or $osVersion -ge [System.Version]$minBuild
            $maxMatch = $null -eq $maxBuild -or $osVersion -le [System.Version]$maxBuild

            $platformMatch -and $minMatch -and $maxMatch
        }
    }

    if ($selectedModel -ne "All") {
        $modelValue = $selectedModel.ToLower()
        $filtered = $filtered | Where-Object {
            if (-not [System.String]::IsNullOrWhiteSpace([System.String] $_.ParseError)) { return $true }
            $targets = Get-PropertyValue -Object $_.Config -Names @("Targets")
            $models  = @(Get-PropertyValue -Object $targets -Names @("Models"))
            $modelValue -in $models
        }
    }

    $filteredArray = @($filtered)
    $configsListBox.ItemsSource = $null
    $configsListBox.ItemsSource = $filteredArray
    $listHeaderTextBlock.Text = "Configuration Files ({0})" -f $filteredArray.Count

    if ($filteredArray.Count -gt 0) {
        $configsListBox.SelectedIndex = 0
    }
    else {
        Render-Config -Entry $null
    }
}

function Reload-Configs {
    $script:allConfigEntries = Get-ConfigEntry -Path $ConfigsPath
    Apply-ConfigFilter
}

function Set-AppTheme {
    # Central theme-switch entry point: rebuilds the brush set, repaints all
    # DynamicResource-bound XAML chrome, restyles the toggle button, re-applies the
    # DWM caption/dark-mode attributes on the live window, and re-renders the details
    # pane (which holds direct brush references baked in at build time).
    param(
        [ValidateSet("Light", "Dark")]
        [System.String] $Mode
    )

    $script:themeMode = $Mode
    $script:theme = Get-ThemeBrushes -Mode $Mode
    $theme = $script:theme

    foreach ($brushName in @("PrimaryText", "SubtleText", "Muted", "Card", "Border", "Window", "SectionBackground", "Badge", "BadgeHover", "Callout", "Error", "ErrorCardBackground", "ErrorCardBorder")) {
        $window.Resources["Brush.$brushName"] = $script:theme["${brushName}Brush"]
    }

    if ($Mode -eq "Dark") {
        $themeToggleButton.Content = [System.Char]::ConvertFromUtf32(0x1F319)
        $themeToggleButton.ToolTip = "Switch to light theme"
    }
    else {
        $themeToggleButton.Content = [System.Char]::ConvertFromUtf32(0x2600)
        $themeToggleButton.ToolTip = "Switch to dark theme"
    }

    $helper = [System.Windows.Interop.WindowInteropHelper]::new($window)
    if ($helper.Handle -ne [System.IntPtr]::Zero) {
        $windowColor = $script:theme.WindowBrush.Color
        $captionColor = ([System.Int32] $windowColor.B -shl 16) -bor ([System.Int32] $windowColor.G -shl 8) -bor [System.Int32] $windowColor.R
        [void] [DwmHelper]::DwmSetWindowAttribute($helper.Handle, [DwmHelper]::DWMWA_CAPTION_COLOR, [ref] $captionColor, 4)

        $darkModeValue = if ($Mode -eq "Dark") { 1 } else { 0 }
        [void] [DwmHelper]::DwmSetWindowAttribute($helper.Handle, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref] $darkModeValue, 4)
    }

    if ($null -ne $configsListBox.SelectedItem) {
        Render-Config -Entry $configsListBox.SelectedItem
    }
    else {
        $detailsPanel.Children.Clear()
        Add-EmptyMessage -Message "Select a configuration file from the left pane to view details."
    }
}

$configsListBox.Add_SelectionChanged({
    Render-Config -Entry $configsListBox.SelectedItem
})

$osComboBox.Add_SelectionChanged({
    Apply-ConfigFilter
})

$modelComboBox.Add_SelectionChanged({
    Apply-ConfigFilter
})

$browseConfigsPathButton.Add_Click({
    $folderBrowser = [System.Windows.Forms.FolderBrowserDialog]::new()
    try {
        $folderBrowser.Description = "Select a folder containing configuration profiles"
        $folderBrowser.ShowNewFolderButton = $false

        # UseDescriptionForTitle only exists on .NET Core 3.0+ / .NET 5+ builds of Windows Forms
        if ($null -ne $folderBrowser.PSObject.Properties["UseDescriptionForTitle"]) {
            $folderBrowser.UseDescriptionForTitle = $true
        }

        if (Test-Path -Path $ConfigsPath -PathType "Container") {
            $folderBrowser.SelectedPath = (Resolve-Path -Path $ConfigsPath).Path
        }

        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:ConfigsPath = $folderBrowser.SelectedPath
            Set-SubtitleText
            Reload-Configs
        }
    }
    finally {
        $folderBrowser.Dispose()
    }
})

$themeToggleButton.Add_Click({
    $nextMode = if ($script:themeMode -eq "Dark") { "Light" } else { "Dark" }
    Set-AppTheme -Mode $nextMode
})

Reload-Configs

# Apply the initial caption colour and dark/light title bar mode once the HWND exists
# (Windows 11 build 22000+ for caption colour; DWMWA_USE_IMMERSIVE_DARK_MODE for the frame)
$window.Add_SourceInitialized({
    $helper = [System.Windows.Interop.WindowInteropHelper]::new($window)
    $windowColor = $script:theme.WindowBrush.Color
    $captionColor = ([System.Int32] $windowColor.B -shl 16) -bor ([System.Int32] $windowColor.G -shl 8) -bor [System.Int32] $windowColor.R
    [void] [DwmHelper]::DwmSetWindowAttribute($helper.Handle, [DwmHelper]::DWMWA_CAPTION_COLOR, [ref] $captionColor, 4)

    $darkModeValue = if ($script:themeMode -eq "Dark") { 1 } else { 0 }
    [void] [DwmHelper]::DwmSetWindowAttribute($helper.Handle, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref] $darkModeValue, 4)
})

[void] $window.ShowDialog()
