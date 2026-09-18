# Documentation index

Start here. This repo is small by design: three NuGet primitives plus one PowerShell image module.

| Document | Audience | Contents |
|---|---|---|
| `getting-started.md` | Everyone | Prerequisites, build, test, first image build |
| `architecture.md` | Everyone | Solution map, component responsibilities, data flow |
| `repository-layout.md` | Everyone | File tree with ownership notes |
| `security-primitives.md` | .NET consumers | `WorkloadAuthorizationEnvelope` encoding, digests, purposes |
| `artifact-media.md` | .NET consumers | `SingleFileIso9660` layout, write/verify contracts |
| `hyperv.md` | .NET consumers | `PowerShellHyperV`, socket transports, error codes |
| `linux-image.md` | Image operators | `CSweet.LinuxImage` module, Packer pipeline, sealing |
| `build-test-release.md` | Maintainers | CI, versioning, trusted publishing, release checklist |
| `testing.md` | Contributors | Pester suites, mocking strategy, what tests do not prove |
| `security-model.md` | Everyone | Threat model, trust boundaries, explicit non-goals |
| `contributing.md` | Contributors | Conventions, TreatWarningsAsErrors, PR expectations |
| `glossary.md` | Everyone | Terms: purpose, receipt vs certification, seed, seal, etc. |

Conventions used throughout:

- Paths are repo-relative unless stated otherwise.
- `artifacts/` is local, git-ignored build output. Never commit it.
- PowerShell means Windows PowerShell 5.1 unless stated otherwise.
- .NET means .NET 10 SDK (`global.json` pins `10.0.100`, `latestFeature` roll-forward).
