# Getting started

## What this repo is

`CSweet.Isolation` provides shared implementation primitives for independent
execution services (Office, WebHost, compute). It does not provide a complete
product isolation boundary, enrollment, credentials, workload execution, or
certification. Those live in the owning products.

Three NuGet packages (all versioned together via `Directory.Build.props`):

- `CSweet.Isolation.Security` — canonical SHA-256 digests and
  purpose-separated workload authorization encoding.
- `CSweet.Isolation.Artifacts` — deterministic single-file ISO-9660 media.
- `CSweet.Isolation.HyperV` — bounded Windows VM commands, host socket
  transport, Linux guest socket listener.

One PowerShell module (versioned independently in its own manifest):

- `CSweet.LinuxImage` (`tools/LinuxImage`, currently 1.0.2) — installer-owned
  Ubuntu 24.04 Hyper-V image provisioning shared by Office and compute.

## Prerequisites

| Task | Requirements |
|---|---|
| Build .NET libraries | .NET 10 SDK (`global.json` requests `10.0.100`, rolls forward to latest feature band) |
| Run Pester tests | Windows PowerShell 5.1 + Pester 3.4 (`Import-Module Pester`) |
| Real image build | Elevated Administrator prompt, Hyper-V enabled, `Default Switch` (or named switch) present, OpenSSH client (auto-installed via Windows capability if missing), internet access to `releases.ubuntu.com` and `releases.hashicorp.com` |

## Build

```powershell
dotnet build CSweet.Isolation.slnx -c Release
```

Pack locally (output goes to the git-ignored `artifacts/` tree):

```powershell
dotnet pack CSweet.Isolation.slnx -c Release --no-build --output artifacts/packages
```

> Do not sign or publish release artifacts from an ordinary development runner.
> Releases go through the `publish-nuget` workflow (see `build-test-release.md`).

## Test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit"
```

The suites mock all external provisioning (Hyper-V, Packer, downloads) with
fixtures. A green run proves pipeline logic, not a bootable VM.

## Build a real Linux image (optional, slow)

Only from an elevated Administrator prompt on a Hyper-V host:

```powershell
Import-Module .\tools\LinuxImage\CSweet.LinuxImage.psd1 -Force
New-CSweetLinuxHyperVImage -ProfileDirectory <path-to-profile> `
  -PreparePayload { param($payload) <# copy guest files into $payload #> } `
  -GuestServiceName 'csweet-compute-guest.service' `
  -ArtifactDirectory .\artifacts\linux-images `
  -OutputPath .\artifacts\linux-images\compute-1.0.2.vhdx
```

Expect 10–30 minutes for the Ubuntu install. See `linux-image.md` for the
profile contract (`user-data.pkrtpl`, `provision-guest.sh`), the exclusive
build lock, checksum verification, and first-boot sealing.

## Next steps

- Understand the design: `architecture.md`, `security-model.md`.
- Consume the .NET APIs: `security-primitives.md`, `artifact-media.md`, `hyperv.md`.
- Operate image builds: `linux-image.md`.
- Cut a release: `build-test-release.md`.
- Unfamiliar term: `glossary.md`.
