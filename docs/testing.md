# Testing

## Suites

| File | What it covers |
|---|---|
| `tests/LinuxImage.Tests.ps1` | `New-CSweetLinuxHyperVImage` pipeline logic with all externals mocked |
| `tests/LinuxImageAdapters.Tests.ps1` | Office + compute adapter scripts' contract against the shared module |

Run (Windows PowerShell 5.1, Pester 3.4):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit"
```

There are no .NET unit tests in this repo — the C# surface is covered by the
owning products' regression suites (including the captured Office 0.5.0
encoding vector).

## Mocking strategy (`LinuxImage.Tests.ps1`)

The suite imports the module `.psd1` and runs `InModuleScope` so it can mock
module-internal helpers:

- `Assert-ImageHost {}` — no admin/Hyper-V requirement.
- `New-ImageSeed` — writes a `seed fixture` file instead of IMAPI2.
- `Invoke-CSweetDownload` — file writes become `verified iso fixture`; checksum
  listings are synthesized from its SHA-256 so verification passes.
- `Invoke-ImageTool` — records `$Arguments`; `ssh-keygen` calls materialize
  fixture key files; `build` materializes one `guest.vhdx` under the passed
  `output_directory`.

Cases:

1. **Both workload profiles** — loops `csweet-agent-guest.service` /
   `csweet-compute-guest.service` through the full pipeline; asserts the
   receipt's `GuestService` + `Sha256` match the file, the `guest_service=`
   var reaches Packer, `validate` precedes `build`, temp keys are gone.
2. **Export path length** — asserts VM name ≤ 20 chars and the nested
   `…\Virtual Hard Disks\….vhdx` path < 240 chars.
3. **No overwrite** — pre-existing output aborts with `already exists` before
   host checks or payload run; file bytes untouched; `Assert-ImageHost` never
   called.
4. **Malformed profile** — missing `provision-guest.sh` throws `Missing image
   profile` before host checks.
5. **Validation failure** — `validate` throwing skips `build`, leaves no
   output, restores `PACKER_PLUGIN_PATH` / `PACKER_CACHE_DIR`, removes temp
   keys, releases the lock (re-openable).
6. **Concurrent build** — pre-held `image-build.lock` fails fast; payload and
   tools never run.
7. **Checksum mismatch** — listing without the expected filename throws
   `checksum` before `build`.

## Adapter strategy (`LinuxImageAdapters.Tests.ps1`)

Resolves the sibling-checkout layout (`$sharedRoot/tools/LinuxImage/…`,
`$repositories/CSweet.Office/…`, `$repositories/csweet/…`), mocks
`Import-Module` + `New-CSweetLinuxHyperVImage` (captures service/profile,
runs the payload into a stage dir, returns a fixture receipt), and stubs the
`dotnet` CLI as a function that materializes published files.

- **Office**: invokes `New-CSweetHyperVTestGuest.ps1 -IsolationRoot
  $sharedRoot`; asserts the returned path, `csweet-agent-guest.service`, the
  `CSweet.Office\build\windows-hyperv` profile, and all three
  `<Guest>.bin` stage files.
- **Compute**: invokes `New-ComputeLinuxImage.ps1`; asserts
  `csweet-compute-guest.service`, `guest/CSweet.Compute.Guest`,
  `Install-ComputeGuestLinux.sh`, and the `<image>.build.json` receipt
  contents.

These tests pin the adapter contract — if an owning repo renames its profile,
service, or stage layout, this suite fails here first.

> Skipped when the sibling repos are absent (adapter scripts resolved via
> `$repositories`, the parent of the `CSweet.Isolation` root).

## What tests do NOT prove

- No running VM is created; Packer validation + unit logic do not certify a
  bootable image.
- No network, Hyper-V, or real Ubuntu/Packer bytes are touched.
- A green run is necessary but not sufficient for release — real builds still
  require an elevated Hyper-V host and download access.
