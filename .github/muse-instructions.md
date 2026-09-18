# Copilot instructions — CSweet.Isolation

Read `AGENTS.md` and `docs/README.md` before changing code.

## What this repo is

Shared .NET 10 primitives (`src/`, one shared `Version` in
`Directory.Build.props`) + installer-owned Linux image module
(`tools/LinuxImage`, own `.psd1` version). Owning products (Office, WebHost,
compute) live elsewhere.

## Apply to all files (`**/*`)

- Preserve wire compatibility: auth encoding bytes, ISO sector layout,
  Hyper-V socket GUID derivation, service purposes/protocols. Treat changes as
  breaking.
- Never commit `artifacts/`, `bin/`, `obj/`, temp keys.
- Update `docs/` with behavior changes.

## C# (`src/**/*.cs`)

- `net10.0` / nullable / latest lang version inherited — don't restate.
- `TreatWarningsAsErrors`: fix warnings; keep `///` summaries accurate.
- `WorkloadAuthorizationEnvelope`: validate purpose/provider non-blank,
  digest canonical, `expiresAt > issuedAt`. Purposes are per-service constants.
- `SingleFileIso9660`: keep `ARTIFACT.CSAB;1` at sector 21, PVD ids
  `CSWEET` / `CSWEET_AGENT_ARTIFACT`; verify with fixed-time compare,
  return `false` (don't throw) on bad media.
- `PowerShellHyperV`: parameters via `CSWEET_*` env vars, Base64-encoded
  `powershell.exe` only, honor timeouts, `Sanitize` errors before logging,
  surface `HyperVCommandException.ErrorCode`.
- Guest VSOCK uses libc P/Invoke (AF_VSOCK unsupported in managed sockets) —
  do not refactor to `System.Net.Sockets.Socket`.

## PowerShell (`tools/**/*.ps1`, `tools/**/*.psm1`, `tests/**/*.ps1`)

- Must run on Windows PowerShell 5.1. No `??`/`?.`, mind empty-native-arg
  quoting (`'""'` on 5.1), `Set-StrictMode -Version Latest`.
- Pester 3.4 syntax only (`Should Be`, `Assert-MockCalled`).
- Never let agent/user input become a profile path, payload callback, switch
  name, or service name.

## Do not

- Bump `Version`/`.psd1` version in a feature change; releases trigger on
  `main` pushes/tags (`docs/build-test-release.md`).
- Present a build receipt (`Sha256`) as certification.
