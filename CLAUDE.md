# CSweet.Isolation — Claude guide

> This repo provides shared isolation primitives, not a complete isolation
> boundary. See `docs/security-model.md` for the threat model and non-goals.

## Orientation

Start with `docs/README.md` (doc index), then `docs/architecture.md` and
`docs/getting-started.md`.

- `src/CSweet.Isolation.Security` — purpose-separated authorization encoding
  (`docs/security-primitives.md`).
- `src/CSweet.Isolation.Artifacts` — deterministic single-file ISO media
  (`docs/artifact-media.md`).
- `src/CSweet.Isolation.HyperV` — bounded VM commands + host/guest socket
  transports (`docs/hyperv.md`).
- `tools/LinuxImage` — installer-owned Ubuntu image module, versioned
  separately (`docs/linux-image.md`).
- `tests/` — Pester 3.4 suites under Windows PowerShell 5.1, all externals
  mocked (`docs/testing.md`).
- Releases via `.github/workflows/publish.yml` trusted publishing
  (`docs/build-test-release.md`).

## Rules for this repo

- Preserve byte-compatibility: authorization encoding, ISO sector layout
  (`ARTIFACT.CSAB;1` at sector 21), socket service-GUID derivation, and
  service purposes. Flag any change to these as breaking.
- `Version` lives only in `Directory.Build.props`. `.csproj` files carry just
  `PackageId` + `Description`. `TreatWarningsAsErrors` is on — fix, don't
  suppress.
- PowerShell must stay 5.1-compatible (`Set-StrictMode Latest`,
  `$ErrorActionPreference = 'Stop'`, Pester 3.4 assertions).
- Profiles and `PreparePayload` callbacks are trusted installer code; never
  source them from agent/user input.
- Never overwrite VHDXs, bypass checksum checks, commit `artifacts/`, or
  publish from a dev machine.

## How to verify

```powershell
dotnet build CSweet.Isolation.slnx -c Release
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit"
```

A mocked green run proves logic, not a bootable VM. Real builds need an
elevated Hyper-V host.
