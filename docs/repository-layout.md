# Repository layout

```text
CSweet.Isolation/
├── CSweet.Isolation.slnx            # solution: the 3 src projects (not the PS module)
├── Directory.Build.props            # shared MSBuild: net10.0, Nullable, WarningsAsErrors,
│                                    #   Version 0.1.0, SourceLink, README packing
├── global.json                      # SDK pin: 10.0.100, latestFeature roll-forward
├── README.md                        # repo landing page (links into docs/)
├── .github/workflows/
│   ├── ci.yml                       # build + pack on push/PR (ubuntu-latest, .NET 10)
│   └── publish.yml                  # trusted-publishing release on main push touching
│                                    #   props/csproj, on v*.*.* tags, or manual dispatch
├── src/
│   ├── CSweet.Isolation.Security/
│   │   ├── CSweet.Isolation.Security.csproj   # PackageId, Description only
│   │   └── WorkloadAuthorizationEnvelope.cs   # Digest / IsDigest / Encode
│   ├── CSweet.Isolation.Artifacts/
│   │   ├── CSweet.Isolation.Artifacts.csproj
│   │   └── SingleFileIso9660.cs               # WriteAsync / VerifyArtifactDigestAsync
│   └── CSweet.Isolation.HyperV/
│       ├── CSweet.Isolation.HyperV.csproj
│       ├── PowerShellHyperV.cs                # VM lifecycle via powershell.exe
│       ├── HyperVSocketTransport.cs           # host AF_HYPERV connector + options
│       └── LinuxHyperVSocketGuestTransport.cs # guest AF_VSOCK listener (libc P/Invoke)
├── tools/LinuxImage/                # distribute this directory TOGETHER
│   ├── CSweet.LinuxImage.psd1       # module manifest, version 1.0.2 (independent)
│   ├── CSweet.LinuxImage.psm1       # New-CSweetLinuxHyperVImage + helpers
│   ├── linux-guest.pkr.hcl          # Packer hyperv-iso template (plugin 1.1.5)
│   ├── New-CSweetNoCloudSeedIso.ps1 # IMAPI2 NoCloud CIDATA seed ISO builder
│   ├── seal-guest.sh                # first-boot SSH-removal + service gating
│   └── README.md                    # module-level readme
├── tests/
│   ├── LinuxImage.Tests.ps1         # pipeline logic with mocked externals (Pester 3.4)
│   └── LinuxImageAdapters.Tests.ps1 # Office/compute adapter contract tests
├── docs/                            # you are here
└── artifacts/                       # git-ignored local output (packages, linux-images, tools)
```

## Ownership notes

- `src/**` — shared primitives. Changes affect every consumer; keep the
  surface minimal and deterministic. `TreatWarningsAsErrors` is on.
- `tools/LinuxImage/**` — installer-owned provisioning. The manifest version
  moves independently of the NuGet `Version`. Always distribute the whole
  directory (template + seal script + seed builder travel with the module).
- `tests/**` — Windows PowerShell 5.1 / Pester 3.4. Fixtures replace Hyper-V,
  Packer, and downloads; they never touch the network or hypervisor.
- `artifacts/**` — never commit. Contains `packages/` (nupkg/snupkg),
  `linux-images/` (tool/cache/build roots, `image-<guid>/` run dirs), and
  `tools/`. Failed builds intentionally leave their run directory for
  inspection.
- `.github/workflows/**` — `ci.yml` is read-only verification; `publish.yml`
  is the only path that pushes to NuGet.org (OIDC trusted publishing).
