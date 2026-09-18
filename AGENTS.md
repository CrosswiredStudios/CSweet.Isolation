# CSweet.Isolation — agent guide

Read `docs/README.md` first for the doc index. This file is the agent entry
point: repo facts, guardrails, and per-task pointers.

## Repo facts

- Three NuGet primitives (`CSweet.Isolation.slnx`, shared `Version` in
  `Directory.Build.props`, currently `0.1.0`, .NET 10, `TreatWarningsAsErrors`):
  - `src/CSweet.Isolation.Security/WorkloadAuthorizationEnvelope.cs` — `Digest` /
    `IsDigest` / `Encode` (big-endian, purpose-separated). No signing.
  - `src/CSweet.Isolation.Artifacts/SingleFileIso9660.cs` — fixed-sector ISO
    (`ARTIFACT.CSAB;1` at sector 21); `WriteAsync` / `VerifyArtifactDigestAsync`.
  - `src/CSweet.Isolation.HyperV/` — `PowerShellHyperV.cs` (bounded
    `powershell.exe` VM lifecycle, `HyperVCommandException` codes),
    `HyperVSocketTransport.cs` (host AF_HYPERV dialer, default port 2761),
    `LinuxHyperVSocketGuestTransport.cs` (guest AF_VSOCK listener via libc
    P/Invoke — never "simplify" to `Socket`).
- PowerShell module `tools/LinuxImage` (own version in `.psd1`, currently
  `1.0.2`): `New-CSweetLinuxHyperVImage` + `linux-guest.pkr.hcl` (plugin
  `= 1.1.5`) + `New-CSweetNoCloudSeedIso.ps1` (IMAPI2) + `seal-guest.sh`.
  Distribute the directory together.
- Tests `tests/LinuxImage*.Tests.ps1` need Windows PowerShell 5.1 + Pester 3.4;
  all externals mocked. No .NET tests here.
- `artifacts/` is git-ignored scratch. Never read secrets from it, never commit it.
- `global.json` pins SDK `10.0.100` (`latestFeature`).

## Guardrails (do not violate)

1. Do not change encoding bytes, ISO sector layout, socket GUID derivation
   (`{port:x8}-facb-11e6-bd58-64006a7986d3`), or service purposes without an
   explicit compatibility plan — Office byte-compatibility is a feature.
2. Profiles and `PreparePayload` callbacks are trusted installer code. Never
   wire agent input into them, host paths, switch names, or service names.
3. Never overwrite existing VHDXs; never bypass checksum verification; never
   publish/sign from a dev runner (only `publish-nuget` pushes via OIDC).
4. Keep `Version` in `Directory.Build.props` only; keep `.csproj` files to
   `PackageId` + `Description`; keep PS scripts 5.1-compatible.
5. A build receipt is not certification. Don't present it as such.

## Task pointers

| Task | Read | Do |
|---|---|---|
| Consume auth encoding | `docs/security-primitives.md` | Call `Encode` with the owning service's frozen purpose; validate `expiresAt > issuedAt`, canonical digest |
| Write/verify artifact ISO | `docs/artifact-media.md` | `WriteAsync` then `VerifyArtifactDigestAsync`; keep sector map fixed |
| Drive Hyper-V VMs | `docs/hyperv.md` | Use `PowerShellHyperV` methods; map `HyperVCommandException.ErrorCode`; `Sanitize` before logging |
| Add host↔guest channel | `docs/hyperv.md` | Agree port (default 2761); host `ConnectAsync(vmId)`, guest `AcceptAsync`; framing/auth is owner's |
| Change image pipeline | `docs/linux-image.md`, `docs/testing.md` | Update module + template + seal + tests together; run Pester under 5.1 |
| Cut release | `docs/build-test-release.md` | Bump `Version` (NuGet) or `.psd1` (module) separately; push to `main` / `v*.*.*`; watch `publish-nuget` |
| Threat-model a change | `docs/security-model.md` | Check trust boundaries + non-goals; profiles/callbacks stay installer-owned |

## Verification

- `dotnet build CSweet.Isolation.slnx -c Release` (warning-free required).
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit"`
- Real image builds need an elevated Hyper-V host; mocked green ≠ bootable.
