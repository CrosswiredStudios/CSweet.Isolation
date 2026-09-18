# Build, test, release

## CI (`.github/workflows/ci.yml`)

Triggers: push to `main`, any pull request. Runner: `ubuntu-latest`.
Permissions: `contents: read`.

```text
checkout → setup-dotnet 10.0.x → dotnet build (Release) → dotnet pack (Release, --no-build, → artifacts/packages)
```

No tests run in CI (Pester suites need Windows PowerShell 5.1 mock host —
they run locally / in owning repos). No signing, no pushing.

## Versioning

- NuGet `Version` lives once in `Directory.Build.props` (currently `0.1.0`)
  and applies to all three packages. Never set `Version` in a `.csproj`.
- `CSweet.LinuxImage` version lives in `tools/LinuxImage/CSweet.LinuxImage.psd1`
  (currently `1.0.2`) and moves independently.
- `global.json` pins SDK `10.0.100` with `latestFeature` roll-forward,
  prerelease disallowed.

## Release (`publish-nuget`, `.github/workflows/publish.yml`)

Triggers:

- push to `main` touching `Directory.Build.props` or `src/**/*.csproj`,
- push of a `v*.*.*` tag,
- manual `workflow_dispatch`.

Permissions: `contents: write` (GitHub release), `id-token: write` (NuGet OIDC
trusted publishing). Concurrency group `nuget-publish-${{ github.ref }}`,
no cancellation.

Steps:

1. Checkout with full history (`fetch-depth: 0`).
2. `setup-dotnet` 10.0.x.
3. Read `Version` from `Directory.Build.props`; if triggered by a tag, the tag
   (`v` stripped) must equal `Version` or the job fails. Emits `version=` and
   `tag=v<version>` outputs.
4. `restore` → `build Release --no-restore` → `pack Release --no-build
   --no-restore → artifacts/packages`.
5. `NuGet/login@v1` with `secrets.NUGET_USER` (OIDC → temporary API key).
6. Push every `*.nupkg` to `https://api.nuget.org/v3/index.json` with
   `--skip-duplicate`; any push failure fails the job.
7. `gh release create v<version>` with generated notes, unless the tag already
   has a release (idempotent check via `gh release view`).

## Release checklist (maintainer)

1. Bump `Version` in `Directory.Build.props` (all three packages move together).
2. Verify `dotnet build CSweet.Isolation.slnx -c Release` green locally.
3. Run the Pester suites (see `testing.md`).
4. Push the version bump to `main` — or push a matching `vX.Y.Z` tag
   (`v0.1.0` for `0.1.0`). Mismatched tag/version fails fast in step 3 above.
5. Watch `publish-nuget`; confirm three packages on NuGet.org + GitHub release.
6. If the Linux module changed, bump `CSweet.LinuxImage.psd1` separately and
   rebuild `CSweet.LinuxImage.1.0.2.zip` — it does not ride the NuGet release.

## Rules

- Never sign or publish from a dev runner. Only `publish-nuget` pushes.
- Never commit `artifacts/` (git-ignored for a reason).
- Tags must match `Version` exactly; the workflow enforces it.
