# C-Sweet Isolation

Shared implementation primitives for independent execution services.

- CSweet.Isolation.Security 0.1.0: canonical SHA-256 references and purpose-separated workload authorization encoding (.NET 10).
- CSweet.Isolation.Artifacts 0.1.0: deterministic verified read-only ISO media (.NET 10).
- CSweet.Isolation.HyperV 0.1.0: bounded Windows VM commands, host socket transport, and Linux guest socket listener (.NET 10).

Office retains compatibility adapters, its authorization purpose, media bytes and guest protocol.
WebHost uses separate authorization purposes and a separate guest protocol/port. A captured Office
0.5.0 encoding vector and the Office regression suite verify compatibility.

Windows VM operations and socket transports are shared. Office-specific enrollment, credentials,
workload execution, other platform backends and certification remain outside this library.
These primitives alone do not provide or certify a complete product isolation boundary.

Build: `dotnet build CSweet.Isolation.slnx -c Release`.
Do not sign or publish release artifacts from an ordinary development runner.

Release: bump `Version` in `Directory.Build.props` (shared by all three
packages). Pushing that change to `main` — or pushing a matching `v*.*.*` tag —
runs `publish-nuget`, which builds, packs, pushes all three packages to
NuGet.org via trusted publishing (`NUGET_USER` secret), and creates a GitHub
release. Tags must match the `Version` (`v0.1.0` for `0.1.0`).

- [CSweet.LinuxImage 1.0.2](tools/LinuxImage/README.md): shared installer-owned Ubuntu image provisioning for Office and generic compute, distributed as a PowerShell module independently of the NuGet primitives.

## Documentation

Full docs live in [`docs/`](docs/README.md) — start with
[Getting started](docs/getting-started.md), then
[Architecture](docs/architecture.md):

- [Getting started](docs/getting-started.md) — prerequisites, build, test, first image build
- [Architecture](docs/architecture.md) — solution map, responsibilities, data flow
- [Repository layout](docs/repository-layout.md) — file tree with ownership notes
- [Security primitives](docs/security-primitives.md) — authorization encoding and digests
- [Artifact media](docs/artifact-media.md) — deterministic ISO write/verify contracts
- [Hyper-V](docs/hyperv.md) — VM commands, socket transports, error codes
- [Linux image](docs/linux-image.md) — image module, Packer pipeline, sealing
- [Build, test, release](docs/build-test-release.md) — CI, versioning, trusted publishing
- [Testing](docs/testing.md) — Pester suites and what they do not prove
- [Security model](docs/security-model.md) — threat model, trust boundaries, non-goals
- [Contributing](docs/contributing.md) — conventions and PR expectations
- [Glossary](docs/glossary.md) — terms

Agent entry points: [`AGENTS.md`](AGENTS.md) (all agents),
[`CLAUDE.md`](CLAUDE.md), [`CODEX.md`](CODEX.md), [`GEMINI.md`](GEMINI.md),
[Copilot instructions](.github/muse-instructions.md).

