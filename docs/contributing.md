# Contributing

## Principles

- Keep the shared surface minimal. Every line in `src/` ships to all
  consumers — prefer deleting code over adding it.
- Determinism first: no clocks, no random paths, no ambient environment reads
  in library code (timeouts and paths are caller-supplied).
- Compatibility is a feature: Office's purpose, media bytes, and guest
  protocol must keep working. WebHost diverges by design (separate purpose /
  protocol / port), not by accident.

## .NET conventions

- Target `net10.0`, `ImplicitUsings`, `Nullable`, `LangVersion latest` — all
  inherited from `Directory.Build.props`. Don't repeat them in `.csproj` files.
- `TreatWarningsAsErrors` is on. Fix warnings, don't suppress them
  (`CS1591` missing-doc is already in `NoWarn` — public API should still be
  documented).
- `GenerateDocumentationFile` is on; keep `///` summaries accurate.
- `Microsoft.SourceLink.GitHub` is shared — no per-project package refs needed
  for it.
- New `.csproj` files contain only `PackageId` + `Description`.
- Never set `Version` in a `.csproj` — bump `Directory.Build.props` once.

## PowerShell conventions

- Windows PowerShell 5.1 compatibility is required (`New-CSweetNoCloudSeedIso`
  and the module run under 5.1). Watch for v5 gaps: empty native args need the
  literal `'""'` (see `CSweet.LinuxImage.psm1`), `& $exe @args` splatting, no
  `??`/`?.` in shipped scripts.
- `Set-StrictMode -Version Latest` + `$ErrorActionPreference = 'Stop'` in all
  scripts.
- Pester 3.4 syntax (`Should Be`, `Assert-MockCalled`) — not Pester 5.

## Pull requests

1. `dotnet build CSweet.Isolation.slnx -c Release` must be warning-free.
2. `Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit` must pass
   (needs Windows PowerShell 5.1 + Pester 3.4; note in the PR if you couldn't
   run it and why).
3. Update `docs/` alongside behavior changes — a PR that changes encoding,
   media layout, socket protocol, or the image pipeline without docs updates
   is incomplete.
4. Don't bump versions in a feature PR. Version bumps (`Directory.Build.props`
   for NuGet, `.psd1` for the module) are separate, deliberate commits because
   pushing them to `main` triggers releases.
5. Never commit `artifacts/`, `bin/`, `obj/`, or temp keys.
