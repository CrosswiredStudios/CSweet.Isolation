# Artifact media (`CSweet.Isolation.Artifacts`)

Package: `CSweet.Isolation.Artifacts`. Framework: `net10.0` (shared).
Single type: `CSweet.Isolation.Artifacts.SingleFileIso9660` (static).

Purpose: deterministic, verified, read-only ISO media carrying exactly one
agent bundle. The virtual DVD is a hypervisor-enforced read-only transport —
not a general ISO tool.

## Fixed layout

| Item | Value |
|---|---|
| Sector size | 2048 (`SectorSize`) |
| Artifact file name | `ARTIFACT.CSAB;1` (`ArtifactFileName`) |
| Sectors 0–15 | zeros (system area) |
| Sector 16 | Primary Volume Descriptor (volume id `CSWEET`, set id `CSWEET_AGENT_ARTIFACT`) |
| Sector 17 | terminator (`CD001`, type 255) |
| Sector 18 / 19 | root path tables (LE / BE) |
| Sector 20 | root directory (`.`, `..`, artifact record) |
| Sector 21+ | artifact bytes, zero-padded to sector boundary (`ArtifactSector`) |

Total sectors = `21 + ceil(artifactLength / 2048)`.

## Write

```csharp
await using var artifact = File.OpenRead("agent.csab");
await using var output = File.Create("artifact.iso");
await SingleFileIso9660.WriteAsync(artifact, artifact.Length, output);
```

Contract:

- `artifact` must be readable, `output` writable — else `ArgumentException`.
- `artifactLength` must be in `[1, uint.MaxValue]` — else
  `ArgumentOutOfRangeException`.
- Streams artifact in 64 KiB chunks; throws `EndOfStreamException` if the
  stream ends before `artifactLength`.
- Deterministic: same bytes in → same ISO out (fixed PVD timestamps/fields,
  fixed sector map, no embedded paths or clock reads).

## Verify

```csharp
bool trusted = await SingleFileIso9660.VerifyArtifactDigestAsync(
    isoPath: @"C:\images\artifact.iso",
    expectedDigest: "sha256:<64 hex>");
```

Checks, in order (any failure → `false`, no exception for bad media):

1. `expectedDigest` passes digest rules; `isoPath` is non-empty and fully
   qualified.
2. File is at least 22 sectors; sector 16 parses as PVD type 1 / `CD001` /
   version 1.
3. PVD root extent == sector 20.
4. Root directory contains `ARTIFACT.CSAB;1` at extent 21 with length ≥ 1 and
   within file bounds.
5. Streams exactly that extent through SHA-256 and compares with
   `CryptographicOperations.FixedTimeEquals` (ASCII bytes).

Only `IOException`, `UnauthorizedAccessException`, `InvalidDataException` from
I/O are swallowed; anything else propagates. `OperationCanceledException` from
a cancelled token propagates (does not become `false`).

## Guidance

- Office owns its media bytes; keep them byte-compatible. Do not add files,
  change the volume id, or move the artifact extent — guests parse fixed
  sectors.
- Always verify on receipt (`VerifyArtifactDigestAsync`) even if you wrote the
  ISO yourself; the DVD path crosses a trust boundary.
- For digest rules see `security-primitives.md`.
