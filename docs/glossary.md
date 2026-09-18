# Glossary

| Term | Meaning |
|---|---|
| **Purpose** | Immutable per-service string passed to `WorkloadAuthorizationEnvelope.Encode`. Domain-separates tokens so Office and WebHost encodings never validate in each other's context. |
| **Digest** | Canonical artifact reference: `sha256:` + 64 lowercase hex chars. Validated by `IsDigest` everywhere it appears. |
| **Encoding vector** | A captured (purpose, fields → bytes) test fixture. Office keeps a 0.5.0 vector in its regression suite to prove byte-compatibility. |
| **Artifact media** | Deterministic single-file ISO-9660 image (`SingleFileIso9660`) carrying `ARTIFACT.CSAB;1` at fixed sector 21, attached as a read-only virtual DVD. |
| **Bootstrap ISO** | Optional second DVD (SCSI 0:3) attached by `ConfigureAsync` alongside the artifact ISO. Owner-defined contents. |
| **NoCloud seed** | `CIDATA` ISO (`meta-data` + `user-data`) consumed by cloud-init during the Packer Ubuntu install. Built by `New-CSweetNoCloudSeedIso.ps1` via IMAPI2. |
| **Profile** | Trusted installer inputs for an image: `user-data.pkrtpl` + `provision-guest.sh` in a directory, plus a `PreparePayload` callback and a guest service name. |
| **Payload** | Guest files staged by the `PreparePayload` callback into the Packer `payload/` dir and uploaded to `/tmp/csweet-image-payload` in the image. |
| **Seal / sealing** | `seal-guest.sh` + first-boot `csweet-image-first-boot.service`: removes SSH, sudoers entry, locks the build account before the workload service starts. |
| **Build receipt** | `@{ ImagePath; Sha256; UbuntuVersion; GuestService }` returned by `New-CSweetLinuxHyperVImage`. Records bytes produced — not certification, not execution authority. |
| **Certification** | Owning-product process (release signing, protected-template installation, workload grants) that promotes a built VHDX to a runnable template. Outside this repo. |
| **Service GUID** | Hyper-V socket service id derived from the VSOCK port: `{port:x8}-facb-11e6-bd58-64006a7986d3`. Host dials `(vmId, serviceId)`; guest binds the port. |
| **VSOCK** | Hyper-V host↔guest socket channel (AF_HYPERV 34 on Windows, AF_VSOCK 40 on Linux). Carries the owning product's protocol — this repo only moves bytes. |
| **Scratch disk** | Dynamic VHD attached at SCSI 0:1 for ephemeral workload I/O. Distinct from the differencing OS disk (0:0). |
| **Differencing disk** | OS disk created with `New-VHD -ParentPath $baseDisk -Differencing` so the base template is never modified. |
| **IsolationRoot** | Override parameter on consumer adapter scripts pointing at the sibling `CSweet.Isolation` checkout (default: adjacent directory). |
