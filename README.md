# C-Sweet Isolation

Shared implementation primitives for independent execution services.

- CSweet.Isolation.Security 0.1.0: canonical SHA-256 references and purpose-separated workload authorization encoding (.NET 8).
- CSweet.Isolation.Artifacts 0.1.0: deterministic verified read-only ISO media (.NET 10).
- CSweet.Isolation.HyperV 0.1.0: bounded Windows VM commands, host socket transport, and Linux guest socket listener (.NET 10).

Office retains compatibility adapters, its authorization purpose, media bytes and guest protocol.
WebHost uses separate authorization purposes and a separate guest protocol/port. A captured Office
0.5.0 encoding vector and the Office regression suite verify compatibility.

Windows VM operations and socket transports are shared. Office-specific enrollment, credentials,
workload execution, other platform backends and certification remain outside this library.
These primitives alone do not provide or certify a complete product isolation boundary.

Build: `dotnet build CSweet.Isolation.slnx -c Release`.
Do not sign or publish release artifacts from an ordinary development runner.

- [CSweet.LinuxImage 1.0.2](tools/LinuxImage/README.md): shared installer-owned Ubuntu image provisioning for Office and generic compute, distributed as a PowerShell module independently of the NuGet primitives.

