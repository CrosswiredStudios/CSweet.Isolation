# Linux image module (`CSweet.LinuxImage`)

Version 1.0.2, manifest: `tools/LinuxImage/CSweet.LinuxImage.psd1`.
Distribute the whole `tools/LinuxImage` directory together — the `.psm1`
depends on `linux-guest.pkr.hcl`, `seal-guest.sh`, and
`New-CSweetNoCloudSeedIso.ps1` by sibling path.

> Installer-owned provisioning. Profiles and `PreparePayload` callbacks are
> trusted installer code — never accept them from an agent request.

## Exported function

`New-CSweetLinuxHyperVImage` (only export):

```powershell
New-CSweetLinuxHyperVImage -ProfileDirectory <dir> -PreparePayload { param($payload) … } `
  -GuestServiceName 'csweet-compute-guest.service' -ArtifactDirectory <dir> `
  -OutputPath <path.vhdx> [-SwitchName 'Default Switch'] `
  [-UbuntuVersion '24.04.4'] [-PackerVersion '1.15.4'] [-ReportProgress { param($phase,$message) … }]
```

| Parameter | Rules |
|---|---|
| `ProfileDirectory` | must contain `user-data.pkrtpl` (with `${ssh_public_key}` placeholder) and `provision-guest.sh` |
| `PreparePayload` | scriptblock invoked as `& $PreparePayload $payload`; must leave ≥ 1 file under `$payload` |
| `GuestServiceName` | must match `^[a-z0-9-]+\.service$`; must exist as a unit inside the image (checked by `seal-guest.sh`) |
| `ArtifactDirectory` | tool/cache/build root (both consumers default to `CSweet.Isolation/artifacts/linux-images`); created if missing |
| `OutputPath` | must end `.vhdx`; must not already exist (never overwritten, including Office templates) |
| `UbuntuVersion` / `PackerVersion` | `X.Y.Z` pattern; defaults `24.04.4` / `1.15.4` |
| `ReportProgress` | `($phase, $message)` callback; phases: `install-openssh`, `download-packer`, `publish-guest`, `resolve-ubuntu`, `download-ubuntu`, `prepare-packer`, `build-guest`, `guest-complete` |

Returns `@{ ImagePath; Sha256; UbuntuVersion; GuestService }` — a build
receipt (bytes record), not certification.

## Pipeline (in order)

1. **Validate output + profile first** — extension, existence, and both
   profile files are checked before touching the host or payload.
2. **Assert host** (`Assert-ImageHost`) — Administrator role, `Hyper-V`
   module import, `Microsoft-Hyper-V` feature enabled, `Get-VMSwitch
   $SwitchName` exists.
3. **Exclusive lock** — `image-build.lock` opened `OpenOrCreate` with
   `FileShare.None`. A concurrent build fails immediately without running its
   payload. Lock is held until `finally`.
4. **Run directory** — `image-<guid>/` with `payload/`, `seed/`,
   `packer_ed25519[.pub]`, `cidata.iso`, `out/`. VM name `csw-<12 hex>`.
   Export path length is pre-checked (< 240 chars) for the nested Hyper-V
   `Virtual Hard Disks` path.
5. **SSH client** — `%SystemRoot%\System32\OpenSSH\ssh-keygen.exe`; if absent,
   installs `OpenSSH.Client~~~~0.0.1.0` capability (restart required → throw).
6. **Packer tool** — `tools/packer-<ver>/packer.exe`; if absent, downloads
   `packer_<ver>_windows_amd64.zip` + `…_SHA256SUMS` from
   `releases.hashicorp.com`, extracts the filename line via `Get-ImageChecksum`
   regex, verifies before and after download, `Expand-Archive`s it.
7. **Payload** — invokes `PreparePayload`; empty output → throw.
8. **Temp keys** — `ssh-keygen -t ed25519 -N <empty>` (PowerShell 5 needs the
   literal `'""'` for the empty passphrase; v7 passes `''`). Public key must
   match `^ssh-ed25519\s+`. Keys are deleted in `finally` even on failure.
9. **Seed ISO** — renders `user-data` (key substitution), writes `meta-data`
   (`instance-id` / `local-hostname`), calls `New-CSweetNoCloudSeedIso.ps1`.
10. **Ubuntu ISO** — resolves `ubuntu-<ver>-live-server-amd64.iso` against
    `https://releases.ubuntu.com/<ver>/SHA256SUMS` via `Get-ImageChecksum`,
    downloads to `cache/` if missing or mismatched, re-verifies (mismatch →
    throw). Downloaded by the module (not Packer) for progress + retries.
11. **Packer** — sets `PACKER_PLUGIN_PATH` (`tools/packer-plugins`) and
    `PACKER_CACHE_DIR` (`cache/packer`), restores both in `finally`; `packer
    init`, then `packer validate` (failure stops before `build`), then `packer
    build -color=false`. All invocations stream to host; non-zero exit →
    throw.
12. **Export** — exactly one `*.vhdx` must exist under `out/`; copied (never
    moved) to `OutputPath`; SHA-256 receipt computed and reported.

Build directories and caches are retained for inspection, never auto-deleted.
Failed builds keep their run directory diagnostics.

## Packer template (`linux-guest.pkr.hcl`)

- Source `hyperv-iso` (plugin `github.com/hashicorp/hyperv` pinned `= 1.1.5`):
  Gen2, 2 CPUs, 4096 MB fixed, 16384 MB disk (1 MB blocks), Secure Boot
  `MicrosoftUEFICertificateAuthority`, no virtualization extensions, headless,
  first boot device DVD, `secondary_iso_images = [seed]`, SSH communicator as
  `csweet-image` with the temp key, 35 min SSH timeout, `shutdown_command`
  `sudo -n shutdown -P now`.
- Boot command drops to GRUB CLI and launches
  `linux /casper/vmlinuz autoinstall ---` + `initrd /casper/initrd` + `boot`.
- Provisioners: `mkdir /tmp/csweet-image-payload` → upload `payload/` →
  run `provision-guest.sh` via `sudo -n bash` → run `seal-guest.sh` with
  `CSWEET_GUEST_SERVICE` via `sudo -n`.

## Seed ISO (`New-CSweetNoCloudSeedIso.ps1`)

Builds a NoCloud `CIDATA` ISO with IMAPI2 (`IMAPI2FS.MsftFileSystemImage`,
no ADK/xorriso dependency):

- Requires `meta-data` + `user-data` in the source dir; output must be a
  non-root `.iso` path.
- Filesystems `3` = ISO9660 (discoverable label) + Joliet (preserves lowercase
  NoCloud names); volume label upper-cased (default `CIDATA`).
- Streams the COM `IStream` to disk via an inline `ComIsoStreamWriter` C#
  helper; releases all COM objects; throws if output is missing/empty.

## Sealing (`seal-guest.sh`)

Runs inside the image during `packer build`; effects land on first boot:

- Validates `CSWEET_GUEST_SERVICE` matches `^[a-z0-9-]+\.service$` (exit 2)
  and that its unit file exists (exit 3).
- Installs `/usr/lib/csweet/seal-image.sh`: disables+masks `ssh.service` /
  `ssh.socket`, deletes `authorized_keys` + `90-csweet-image` sudoers entry,
  locks `csweet-image` (`passwd -l`), touches `/var/lib/csweet/image-sealed`.
- Installs `csweet-image-first-boot.service` (oneshot, conditioned on the
  marker being absent, ordered after `csweet-first-runtime-boot.service`).
- Drops `<guest>.d/image-seal.conf` so the workload service
  `Requires=`/`After=` the seal unit — no workload runs on an unsealed image.
- Disables cloud-init, `apt-get clean`, removes `/tmp/csweet-image-payload`
  and `/var/lib/cloud/instances/*`.

First guest boot: seal runs → SSH gone, account locked → workload service
starts. A receipt is not certification; release signing, protected-template
installation, and workload grants remain with the owning products.

## Consumers (outside this repo)

- Office: `CSweet.Office/scripts/windows/New-CSweetHyperVTestGuest.ps1` —
  stages all three guest binaries (`RuntimeGuest`, `BuilderGuest`,
  `ToolchainGuest`), service `csweet-agent-guest.service`.
- Compute: `csweet/scripts/New-ComputeLinuxImage.ps1` — publishes one guest
  + `Install-ComputeGuestLinux.sh`, service `csweet-compute-guest.service`,
  writes `<image>.build.json` receipt.
- Both default `IsolationRoot` to the sibling `CSweet.Isolation` checkout and
  share `artifacts/linux-images`. Adapter contracts are pinned by
  `tests/LinuxImageAdapters.Tests.ps1` (see `testing.md`).
