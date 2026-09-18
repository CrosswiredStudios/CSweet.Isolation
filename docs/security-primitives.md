# Security primitives (`CSweet.Isolation.Security`)

Package: `CSweet.Isolation.Security`. Framework: `net10.0` (shared).
Single type: `CSweet.Isolation.Security.WorkloadAuthorizationEnvelope` (static).

## Digest format

Canonical reference: `sha256:` + 64 lowercase hex characters (71 chars total).

```csharp
string digest = WorkloadAuthorizationEnvelope.Digest("anything");
bool ok = WorkloadAuthorizationEnvelope.IsDigest(digest); // true
bool bad = WorkloadAuthorizationEnvelope.IsDigest("SHA256:ABC…"); // false
```

Rules enforced by `IsDigest` (also used internally by `Encode` and by
`SingleFileIso9660.VerifyArtifactDigestAsync`):

- exact length 71, ordinal `sha256:` prefix, `[0-9a-f]` alphabet only;
- uppercase, truncated, or prefixed/suffixed values are rejected.

## Encoding

```csharp
byte[] token = WorkloadAuthorizationEnvelope.Encode(
    purpose: "csweet-office-0.5",   // each service defines its own, immutable
    version: 1,
    hostId: hostGuid,
    assignmentId: assignmentGuid,
    workloadId: workloadGuid,
    epoch: 7L,
    providerId: "hyperv",
    digest: "sha256:<64 hex>",
    issuedAt: DateTimeOffset.UtcNow,
    expiresAt: DateTimeOffset.UtcNow.AddHours(1));
```

Wire layout (all integers big-endian):

| Field | Encoding |
|---|---|
| `purpose` | `int32 BE length` + UTF-8 bytes |
| `version` | 1 byte |
| `hostId`, `assignmentId`, `workloadId` | 16 bytes each, `Guid.TryWriteBytes(bigEndian: true)` |
| `epoch` | `int64 BE` |
| `providerId` | `int32 BE length` + UTF-8 bytes |
| `digest` | `int32 BE length` + UTF-8 bytes (must pass `IsDigest`) |
| `issuedAt`, `expiresAt` | `int64 BE` Unix seconds each |

Validation inside `Encode` (throws, never returns partial bytes):

- `purpose` / `providerId`: non-null, non-whitespace (`ArgumentException`).
- `digest`: must pass `IsDigest` (`ArgumentException`).
- `expiresAt > issuedAt` required (`ArgumentOutOfRangeException`).

## Purpose separation

The `purpose` string is the domain separator. Office retains its authorization
purpose; WebHost uses a separate purpose. Tokens encoded for one service must
never validate in another, even if every other field is identical. Purposes are
immutable once deployed — changing one invalidates all outstanding tokens for
that service.

Guidance for owning services:

- Choose a purpose like `<service>-<protocol-generation>` and freeze it.
- Keep the captured encoding vector (Office 0.5.0) passing in the owning
  repo's regression suite; any change here that breaks that vector is a
  breaking change.
- This library does not sign, encrypt, store, or check revocation. Signing and
  transport are the owner's job.

## What this package does NOT do

No signatures, no certificates, no key management, no clock-skew policy, no
persistence. It guarantees deterministic bytes and strict input validation —
nothing more.
