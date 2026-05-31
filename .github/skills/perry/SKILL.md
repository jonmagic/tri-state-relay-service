---
name: perry
description: Use when changing Perry compiler usage, native binary builds, or Perry runtime compatibility in Tri-State Relay Service.
---

# Perry

Perry is a native TypeScript compiler used by Tri-State Relay Service to
check source compatibility and build native binaries.

## Use this skill for

- Adding or changing `perry check`, `perry compile`, `perry run`, or
  `perry doctor` commands.
- Deciding whether a Node API or dependency can run in a Perry-built
  binary.
- Updating package scripts, binary templates, or build validation.

## Required context

Load these references before changing Perry behavior:

1. `references/package.md`
2. `references/native-builds.md`
3. `references/runtime-compatibility.md`

Use scripts and templates from this skill when possible instead of
hand-writing package snippets.

