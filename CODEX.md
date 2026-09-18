# Codex — CSweet.Isolation

Start: `AGENTS.md`, then `docs/README.md` → `docs/architecture.md`.

## Scope

- `src/`: 3 minimal NuGet libs, .NET 10, shared version
  (`Directory.Build.props`). Keep the API surface tiny and deterministic.
- `tools/LinuxImage`: image builder module + Packer template + seal script.
  Ship as a unit; version in `.psd1` is independent.
- `tests/`: mocked Pester suites (PS 5.1). No live Hyper-V/network.

## Instructions

1. Match existing style: file-scoped logic, explicit validation with
   `ArgumentException`/`ArgumentOutOfRangeException`, `Win32Exception` for
   native failures, `HyperVCommandException(errorCode, …)` for host commands.
2. Keep scripts 5.1-safe and strict-mode clean; keep Pester 3.4 style.
3. Don't alter wire formats (auth bytes, ISO sectors, socket GUIDs, purposes)
   unless the task explicitly demands a breaking change with a migration plan.
4. Update the relevant `docs/*.md` page with every behavior change.
5. Verify: `dotnet build CSweet.Isolation.slnx -c Release` must be
   warning-free; note when Pester can't run (non-Windows host).

## Never

- Overwrite images, skip checksum verification, commit build output, or add
  network adapters to the restricted VM topology.
- Accept profiles/payload callbacks/paths from untrusted input.
- Sign or publish packages outside `publish-nuget`.
