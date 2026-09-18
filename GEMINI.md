# Gemini — CSweet.Isolation

Read `AGENTS.md` and `docs/README.md` first.

## Context

This repository holds shared isolation primitives for C-Sweet execution
services: authorization encoding, artifact ISO media, Hyper-V lifecycle +
sockets (all .NET 10, one shared NuGet version), plus an installer-owned
Ubuntu image module (own PowerShell module version). Full design in
`docs/architecture.md`; threat model in `docs/security-model.md`.

## Guidelines

- Favor minimal diffs. These libraries ship to every consumer.
- Preserve all wire formats and identifiers (purposes, digests, ISO layout,
  service GUIDs). Call out breaking changes explicitly.
- Follow `docs/contributing.md` (.NET warnings-as-errors, PS 5.1, Pester 3.4).
- Document behavior changes in `docs/`.
- Verify with `dotnet build CSweet.Isolation.slnx -c Release` and the Pester
  command in `docs/testing.md` where the host supports it.

## Safety

- Profiles/payload callbacks stay installer-owned; no untrusted input.
- No overwriting templates, no skipped verification, no dev-runner publishing.
