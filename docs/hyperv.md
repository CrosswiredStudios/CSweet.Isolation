# Hyper-V (`CSweet.Isolation.HyperV`)

Package: `CSweet.Isolation.HyperV`. Framework: `net10.0` (shared).
Files: `PowerShellHyperV.cs`, `HyperVSocketTransport.cs`,
`LinuxHyperVSocketGuestTransport.cs`.

## PowerShellHyperV (host, Windows-only)

Bounded wrapper around `powershell.exe`
(`%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe` — Windows PowerShell,
not `pwsh`). Scripts are Base64-encoded (`-EncodedCommand`), parameters flow
through environment variables (`CSWEET_*`), never string interpolation.

| Method | Timeout | Effect |
|---|---|---|
| `RunAsync(script, env?)` | 30 s | ad-hoc script (owner's responsibility to bound it) |
| `CreateShellAsync(vmName, vmPath, memoryMB)` | 1 min | Gen2 VM, fixed memory, **no VHD**, all NICs + DVD drives removed; returns VM GUID |
| `ConfigureAsync(vmName, baseDisk, osDisk, scratchDisk, cpuCount, cpuPercent, memoryMB, scratchMB, artifactIso?, bootstrapIso?)` | 2 min | differencing OS disk + dynamic scratch disk, optional DVD(s), CPU/memory caps, Secure Boot (`MicrosoftUEFICertificateAuthority`), `AutomaticStartAction Nothing` / `TurnOff` / checkpoints disabled; validates 0 NICs, 2 disks, expected DVD count; on failure removes VM + VHDs and rethrows |
| `StartAsync(vmName)` | 1 min | `Start-VM` |
| `StopAsync(vmName)` | 1 min | `TurnOff` if not already `Off`; exit-code 44 → `not-found` |
| `DestroyAsync(vmName)` | 1 min | `TurnOff` if needed, then `Remove-VM` (idempotent) |
| `GetStateAsync(vmName)` | 30 s | returns `$vm.State` string; exit-code 44 → `not-found` |

CPU note: Hyper-V `Maximum` is per-vCPU percent. `ConfigureAsync` converts the
aggregate `cpuPercent` quota: `ceil(cpuPercent / cpuCount)`, clamped to
`[1, 100]`.

Execution details:

- Non-Windows → `HyperVCommandException("unsupported-host", …)`.
- Missing `powershell.exe` / failed start → `powershell-unavailable` /
  `powershell-start-failed`.
- Timeout kills the process tree → `hyperv-timeout`.
- Exit 44 (script's missing-VM sentinel) → `not-found`.
- Other non-zero exit → `hyperv-command-failed` with a sanitized message.
- Stdout/stderr each capped at 64 KiB (`MaximumOutputCharacters`).

`Sanitize` decodes PowerShell CLIXML (`<Objs>` → `XDocument`, `S="Error"`
nodes, `_x000D_`/`_x000A_` escapes), strips `At line:` / `+` / `CategoryInfo` /
`FullyQualifiedErrorId` lines, dedupes, keeps ≤ 4 lines / 1024 chars, drops
control chars. Never logs raw stderr — always pass it through `Sanitize`.

`HyperVCommandException(errorCode, message)` carries `ErrorCode`:

| Code | Meaning |
|---|---|
| `unsupported-host` | called off Windows |
| `powershell-unavailable` / `powershell-start-failed` | host cannot launch PowerShell |
| `hyperv-timeout` | deadline exceeded, tree killed |
| `not-found` | VM absent (exit 44) |
| `hyperv-command-failed` | script error (message sanitized) |

## Host socket transport (Windows)

`HyperVSocketTransportOptions` (defaults: `LinuxVsockPort` 2761,
`ConnectTimeoutSeconds` 60, `RetryDelayMilliseconds` 250):

- `ServiceId` derives the Hyper-V service GUID from the port:
  `Guid.Parse($"{port:x8}-facb-11e6-bd58-64006a7986d3")`.
- `Validate()` requires port ∈ [1024, 65535], timeout ∈ [1, 300] s,
  retry ∈ [25, 5000] ms.

`WindowsHyperVSocketTransport(options).ConnectAsync(vmId, ct)`:

- Non-Windows → `PlatformNotSupportedException`; empty `vmId` →
  `ArgumentException`.
- Opens AF_HYPERV (family 34) raw socket, non-blocking `connect()` to
  `(vmId, serviceId)` via internal `HyperVSocketEndPoint` (SOCKADDR_HV,
  36 bytes), polls writability per retry slice, checks `SO_ERROR`.
- Managed `ConnectAsync`/`ConnectEx` rejects AF_HYPERV with WSAEINVAL — the
  raw poll loop is intentional, not a workaround to "fix".
- Retries until the deadline; guest-still-booting shows up as refused/timeout
  and is retried. On expiry throws `TimeoutException` (inner = last
  `SocketException`/`IOException`). Caller cancellation propagates.

`WindowsHyperVSocketServiceRegistration` helpers build the guest-service
registry paths (`…\GuestCommunicationServices\{guid}` and the legacy braced
form). Creating those keys (service enrollment) is the owning product's job.

## Guest socket transport (Linux)

`LinuxHyperVSocketGuestTransport(port = 2761)` — port must be ∈ [1024, 65535].

`AcceptAsync(ct)`:

- Non-Linux → `PlatformNotSupportedException`.
- Raw `libc` P/Invoke only (`socket`, `bind`, `listen`, `accept4`, `fcntl`,
  `close`) because .NET's Linux `SocketPal` has no AF_VSOCK mapping — do not
  "simplify" to `System.Net.Sockets.Socket`.
- Binds `CID_ANY` (`ContextId = uint.MaxValue`) on the port, backlog 1,
  non-blocking `accept4` loop with 100 ms delay; `EINTR`/`EAGAIN` retried,
  other errnos → `Win32Exception`.
- Returns `GuestStreamConnection(Input, Output)`: two independent sync
  `FileStream`s over a `dup`'d descriptor (CLOEXEC) so reads and writes don't
  serialize on one stream object. `DisposeAsync` disposes both.
- `OpenAcceptedConnection(inputHandle, outputHandle)` is public for tests /
  custom accept loops; on construction failure it disposes what it owns.

## Cross-side contract

Host and guest must agree on the port (default 2761; Office keeps its guest
protocol, WebHost uses a separate protocol/port). The library moves bytes;
framing, authentication, and command dispatch belong to the owning product.
Keep timeouts generous on first boot (guest seals SSH and starts its listener
before accepting work).
