---
layout: doc
---
# Configurations

Configuration changes are implemented with `Install-Defaults.ps1`. This script reads configurations in JSON format and configures the local Windows instance with Windows feature states, registry settings, copies files into specified paths, imports a default Start menu, and modifies the default user profile.

Configurations are stored in the following JSON files with the logic to make changes to Windows includes in `Install-Defaults.ps1`:

* [Machine.All.json](https://github.com/aaronparker/defaults/blob/main/src/configs/Machine.All.json)
* [Machine.Client.json](https://github.com/aaronparker/defaults/blob/main/src/configs/Machine.Client.json)
* [Machine.RDS.json](https://github.com/aaronparker/defaults/blob/main/src/configs/Machine.RDS.json)
* [Machine.TeamsCopilot.json](https://github.com/aaronparker/defaults/blob/main/src/configs/Machine.TeamsCopilot.json)
* [User.All.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.All.json)
* [User.Client.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Client.json)
* [User.Virtual.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Virtual.json)
* [User.Windows10.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows10.json)
* [User.Windows11.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows11.json)
* [User.Windows2022RDS.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows2022RDS.json)
* [User.Windows2022Server.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows2022Server.json)
* [User.Windows2025RDS.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows2025RDS.json)
* [User.Windows2025Server.json](https://github.com/aaronparker/defaults/blob/main/src/configs/User.Windows2025Server.json)

## Applicability

The applicability of the configurations is determined based on properties of the local Windows instance. The following keywords, used in the file names, ensure that the right JSON files are selected:

* `client` - Windows 10 or Windows 11
* `server` - Windows Server (e.g. Windows Server 2022, 2025)
* `rds-server` - Windows Server Remote Desktop Services hosts
* `multisession` - Not currently used. Intended for Windows multi-session in the future

Each JSON file includes a `MinimumBuild` and `MaximumBuild` properties that are used to ensure configurations only apply to a specific versions of Windows. For example, the property might ensure that configurations only apply to Windows 10 version `10.0.19041` and above.

All JSON files the `config` directory are read and then filtered based on these properties to create a list of configurations to apply to the current system.

## Configuration Schema And Property Requirements

Configuration files are validated with [`schema/configuration.schema.json`](https://github.com/aaronparker/defaults/blob/main/schema/configuration.schema.json).

To enable editor IntelliSense and validation, include this schema reference in each config file:

```json
"$schema": "https://raw.githubusercontent.com/aaronparker/defaults/refs/heads/main/schema/configuration.schema.json"
```

### Requirements and empty values

* Required means the property must exist.
* For array properties, an empty array (`[]`) is valid and should be used when no values are needed.
* Do not use `null` for properties that are defined as `string`, `object`, or `array`.
* The template in `src/configs/_Configuration.Template.json` shows the preferred authoring pattern with empty arrays for non-used sections.

### Top-level properties

| Property | Type | Required | Notes |
| --- | --- | --- | --- |
| `$schema` | `string` (URI) | No | Optional schema reference for editors. |
| `Description` | `string` | Yes | Human-readable profile description. |
| `MinimumBuild` | `string` | Yes | Build floor. Supports values like `19041` or `10.0.14393.0`. |
| `MaximumBuild` | `string` | Yes | Build ceiling. Supports values like `99999` or `10.0.99999.0`. |
| `Targets` | `object` | Yes | Requires `Platforms` and `Models`. |
| `MachineRegistry` | `object` | Yes | Requires `ChangeOwner` and `Set`. |
| `UserRegistry` | `object` | Yes | Requires `Set`. |
| `Features` | `object` | No | If included, requires `Disable`. |
| `Capabilities` | `object` | No | If included, requires `Remove` and `Others`. |
| `Packages` | `object` | No | If included, requires `Remove`. |
| `Paths` | `object` | No | If included, requires `Remove`. |
| `Shortcuts` | `object` | No | If included, requires `Edit`. |
| `Services` | `object` | No | Optional service operations. |
| `Files` | `object` | No | If included, requires `Copy`. |

### Property requirements by section

#### `Targets` (required)

* `Platforms` (required): array of `client`, `multisession`, `rds-server`, `server`.
* `Models` (required): array of `physical`, `virtual`.

Both arrays can be empty in schema terms, but should include applicable values for profile targeting.

#### `MachineRegistry` (required)

* `ChangeOwner` (required): array of objects with required `Root`, `Key`, `Sid`, `note`.
* `Set` (required): array of objects with required `name`, `note`, `path`, `protected`, `type`, `value`.
* `Remove` (optional): array of objects with required `path`, `note`.

`MachineRegistry.Set.type` supports `String`, `DWord`, `Dword`.

#### `UserRegistry` (required)

* `Set` (required): array of objects with required `name`, `note`, `path`, `protected`, `value`, and either `type` or `Type`.
* `Others` (optional): array of objects with required `name`, `note`, `path`, `protected`, `type`, `value`.
* `Source` (optional): string.

For consistency with existing configs and script logic, use lowercase `type`.

`UserRegistry.Set.type` supports `Binary`, `String`, `DWord`, `Dword`.

#### `Features` (optional)

* `Disable` (required when section exists): array of feature names.

#### `Capabilities` (optional)

* `Remove` (required when section exists): array of capability names.
* `Others` (required when section exists): array of capability names.

#### `Packages` (optional)

* `Remove` (required when section exists): array of package names.

#### `Paths` (optional)

* `Remove` (required when section exists): array of file system paths.

#### `Shortcuts` (optional)

* `Edit` (required when section exists): array of objects with required `Path` and `Arguments`.

#### `Services` (optional)

* `Stop` (optional): array of service names.
* `Start` (optional): array of service names.
* `Restart` (optional): array of service names.
* `Enable` (optional): array of service names.
* `Feature` (optional): string gate for role/feature-specific service operations.

#### `Files` (optional)

* `Copy` (required when section exists): array of objects with required `Source` and `Destination`.

### Complete authoring skeleton

Use this structure when creating new configuration files so all expected properties are present, even when values are empty:

```json
{
	"$schema": "https://raw.githubusercontent.com/aaronparker/defaults/refs/heads/main/schema/configuration.schema.json",
	"Description": "Configuration settings template file",
	"MinimumBuild": "10.0.14393.0",
	"MaximumBuild": "10.0.99999.0",
	"Targets": {
		"Platforms": [
			"client",
			"multisession",
			"rds-server",
			"server"
		],
		"Models": [
			"physical",
			"virtual"
		]
	},
	"MachineRegistry": {
		"ChangeOwner": [],
		"Set": [],
		"Remove": []
	},
	"UserRegistry": {
		"Set": [],
		"Others": [],
		"Source": ""
	},
	"Paths": {
		"Remove": []
	},
	"Features": {
		"Disable": []
	},
	"Capabilities": {
		"Remove": [],
		"Others": []
	},
	"Packages": {
		"Remove": []
	},
	"Shortcuts": {
		"Edit": []
	},
	"Services": {
		"Enable": [],
		"Feature": "",
		"Restart": [],
		"Stop": [],
		"Start": []
	},
	"Files": {
		"Copy": []
	}
}
```

### Validation

Validate a configuration file against the schema with PowerShell:

```powershell
$schemaPath = ".\schema\configuration.schema.json"
$configPath = ".\src\configs\User.Windows11.json"

Get-Content -Path $configPath -Raw |
	Test-Json -SchemaFile $schemaPath
```

Validate all configuration files in `src/configs` in one command:

```powershell
Get-ChildItem .\src\configs -Filter *.json -File | Where-Object { $_.Name -ne '_Configuration.Template.json' } | ForEach-Object { [pscustomobject]@{ File = $_.Name; Valid = (Get-Content $_.FullName -Raw | Test-Json -SchemaFile .\schema\configuration.schema.json) } }
```

Expected behavior for authors:

* Pass: returns `True`; the file is structurally valid for the schema.
* Fail: returns `False` (or throws if JSON is malformed); fix missing required properties, invalid enum values, or incorrect value types.
* Empty arrays: still pass where allowed and are preferred for sections with no active items.

## Configuration Viewer

The repository includes a read-only WPF viewer script to inspect configuration files:

```powershell
.\src\Start-DefaultsViewer.ps1
```

The viewer reads JSON files from `src\configs`, shows all available profiles in a list, and renders each section with a user-friendly detail panel. Item-level descriptions are shown from `note` fields where available and from the configuration schema where possible.

The viewer opens using the current Windows light or dark app theme, and includes a ☀/🌙 toggle button in the header to switch between the two Fluent UI for Windows 11 themes at any time.

![](/img/configviewer.png)

## Other Configurations

`Install-Defaults.ps1` performs additional tasks not defined in the JSON configuration files:

* Removes inbox Universal Windows Platform (AppX) apps - see [Remove UWP apps](https://stealthpuppy.com/defaults/appxapps/)
* Copies the solution as a [Run custom actions during feature update](https://learn.microsoft.com/en-gb/windows-hardware/manufacture/desktop/windows-setup-enable-custom-actions?view=windows-11). This enables the Custom Defaults to be re-run during an in-place upgrade

## Script Process Visualisation

Here's an visualisation of how the `Install-Defaults.ps1` works:

![Script Process Visualisation](/img/install-defaults-process.svg)
