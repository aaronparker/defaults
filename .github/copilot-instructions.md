# Windows Enterprise Defaults

PowerShell scripts (Windows PowerShell 5.1 / PowerShell 7 Desktop edition) that customise a Windows
10/11 or Windows Server 2016-2025 image: default user profile settings, in-box app removal, and OS
configuration driven by JSON config files. Docs: https://stealthpuppy.com/defaults/ (built with VitePress
from `docs/`).

## Build, test, lint

Run all commands from the repo root; requires Windows (uses `Win32_Process`, registry, AppX cmdlets).

- **Lint**: `Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\.rules\PSScriptAnalyzerSettings.psd1`
  (CI uses `microsoft/psscriptanalyzer-action` against `./src`, same settings file). Custom rule
  `Measure-LowercaseKeyword` (in `.rules/LowercaseKeyword.psm1`) enforces lowercase PowerShell keywords
  (`if`, `foreach`, etc.) — a repo-specific convention not caught by default rules.
- **Test**: Pester tests live in `tests/*.Tests.ps1`. Many tests key off `$env:GITHUB_WORKSPACE` to locate
  `src/` scripts (falling back to `..\src` relative to the test file when unset), so set that env var
  locally, e.g.:
  ```powershell
  $env:GITHUB_WORKSPACE = (Get-Location).Path
  Invoke-Pester -Path .\tests\Remove-AppxApps.Tests.ps1
  ```
  To run a single test, use `-FullNameFilter` / `Invoke-Pester -Path <file> -TestName "<It block name>"`.
  CI (`.github/workflows/validate-scripts.yml`) runs the whole `tests/` folder with 50% code-coverage
  target over `src/**/*.ps1` (excluding `Start-DefaultsViewer.ps1`), then bumps `src/VERSION.txt` and
  auto-commits on push to `main` — don't hand-edit `VERSION.txt`.
- **Docs**: `npm run docs:dev` / `docs:build` / `docs:preview` (VitePress, config in `.vitepress/`).
- **Packaging**: `ci/New-Package.ps1` builds the `.intunewin` package into `releases/`; `ci/New-Docs.ps1`
  and `ci/Push-Tag.ps1` support release/versioning workflows.

## Architecture

- `src/Install-Defaults.ps1` is the entry point. It self-elevates to a 64-bit process if launched under
  32-bit PowerShell, imports `src/Install-Defaults.psm1` for all helper functions, then:
  1. Detects `Platform` (client/server/rds-server/multisession via `Get-Platform`), `Model`
     (physical/virtual via `Get-Model`), and OS build.
  2. Reads every JSON file in `src/configs/*.json` (except `_Configuration.Template.json`) and filters
     them by matching `Targets.Platforms`, `Targets.Models`, `MinimumBuild`, and `MaximumBuild` against
     the current system.
  3. For each matching config, conditionally applies sections in order: `MachineRegistry`
     (`ChangeOwner`/`Set`/`Remove`), `Shortcuts.Edit`, `Files.Copy`, `Paths.Remove`, `Features.Disable`,
     `Capabilities.Remove`, `Packages.Remove`, `Services.Stop/Start/Restart`, then `UserRegistry.Set`
     (applied to the default user profile hive via `Set-DefaultUserProfile`). Each section is only
     invoked if the corresponding property exists and is non-empty — new config sections must follow
     this same existence/length guard pattern.
  4. On client OS (and only if OOBE isn't already complete), invokes `src/Remove-AppxApps.ps1` to strip
     AppX/UWP apps.
  5. Applies language pack / locale (`Install-SystemLanguage`, `Set-SystemLocale`) and time zone
     (`Set-TimeZoneUsingName`) if parameters were supplied.
  6. Writes an Uninstall registry key (under the `-Guid` param) so the run is detectable as an
     installed application, and copies itself to `%SystemRoot%\System32\update\run\<Guid>` so it
     re-runs during Windows feature updates.
- `src/configs/*.json` are the actual data-driven policy definitions; `src/configs/_Configuration.Template.json`
  is the authoring template and `schema/configuration.schema.json` is the JSON Schema (referenced via
  `$schema` in each config) used for editor IntelliSense/validation — keep both in sync when adding a
  new config section/property.
- `src/apps/initial_preferences.json` and `src/builds/WindowsClient.csv` / `WindowsServer.csv` are
  supporting data files (app defaults, build/version lookups) consumed by the module.
- `src/start/` holds Start Menu/taskbar layout files (XML/JSON/BIN) referenced by config `Files.Copy`
  entries for different Windows versions.
- Locale-specific wrapper scripts (`src/Install-deDE.ps1`, `Install-enAU.ps1`, etc.) call
  `Install-Defaults.ps1` with fixed `-Language`/`-TimeZone` values for that locale.
- `src/Remove-Defaults.ps1` reverses/cleans up applied settings; `src/Remove-AppxApps.ps1` is standalone
  and callable directly (e.g. for gold images where OOBE has completed, since `Install-Defaults.ps1`
  skips AppX removal in that case).
- All logging goes through `Write-LogFile` (in the `.psm1`), which writes to a custom Windows Event Log
  (named from `-Project`) — use it instead of `Write-Host`/`Write-Output` for user-facing status in
  install-time code (`PSAvoidUsingWriteHost` is suppressed in tests for this reason).

## Conventions

- Scripts use `#Requires -RunAsAdministrator` and `#Requires -PSEdition Desktop`, `Set-StrictMode -Version
  Latest`, and `$ErrorActionPreference = "Stop"` — new top-level scripts should match this pattern.
- Functions use full parameter names in splats (`@params`) rather than positional/abbreviated params.
- PowerShell keywords must be lowercase (`if`/`foreach`/`try`, not `If`/`ForEach`) — enforced by the
  custom `Measure-LowercaseKeyword` rule.
- Config JSON files always declare `$schema`, `Description`, `MinimumBuild`, `MaximumBuild`, and
  `Targets.Platforms`/`Targets.Models`, even when a section (e.g. `Capabilities.Remove`) is empty —
  follow `_Configuration.Template.json` as the structural reference for new configs.
