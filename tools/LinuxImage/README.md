# Shared Linux image service 1.0.2

`CSweet.LinuxImage` is an installer-owned PowerShell module used by both Office and generic compute. It builds Ubuntu 24.04 x64 Generation 2 Hyper-V VHDX templates through one Packer pipeline. It is not an agent capability or a new Windows service.

The module owns Hyper-V prerequisites, verified Ubuntu/Packer downloads, temporary SSH keys, NoCloud seed media, Secure Boot configuration, Packer validation/build, immutable image export, and the returned SHA-256 build receipt. A profile supplies its unattended-install packages, a guest provisioning script, a payload preparation callback, and its guest systemd service name. Profiles and callbacks are trusted installer code; never accept them from an agent request.

Consumers:

- Office: `CSweet.Office/scripts/windows/New-CSweetHyperVTestGuest.ps1`. Its three guest executables, scratch-disk behavior, guest protocol, existing setup progress, enrollment and certification remain Office-owned.
- Compute: `csweet/scripts/New-ComputeLinuxImage.ps1`. Its profile installs the self-contained compute guest plus Python 3, without Office guest software. The runtime starts on first boot after build-access cleanup.

Both source adapters default to the sibling `CSweet.Isolation` repository, with an explicit `IsolationRoot` override. Both use `CSweet.Isolation/artifacts/linux-images` for the shared tool/cache/build root. Distribute the entire `tools/LinuxImage` directory together; its manifest version is independent of the unchanged Isolation NuGet libraries. The local distributable is `CSweet.LinuxImage.1.0.2.zip`.

An exclusive build lock prevents concurrent cache changes/builds. Existing output images are never overwritten; choose a new output name when rebuilding. Failed builds retain diagnostics in their unique build directory; temporary private/public SSH key files are removed in `finally`. Build directories and caches are retained for operator inspection, not automatically deleted. First guest boot disables SSH, removes the temporary authorized key and sudoers entry, and locks the build account before the selected workload service starts.

A build receipt is not image certification. Release signing, runtime certification, protected-template installation and workload grants remain in their owning products. Existing Office VHDXs are not modified or accepted automatically as compute templates.

Tests (Windows PowerShell 5.1 / Pester 3.4):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\tests\LinuxImage*.Tests.ps1 -EnableExit"
```

The tests replace external provisioning operations with fixtures. A real image build requires an elevated Hyper-V host and download access. Packer validation and unit tests do not certify a running VM.
