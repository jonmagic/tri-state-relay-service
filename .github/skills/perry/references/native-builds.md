# Native builds

Tri-State Relay Service should keep Node builds and Perry native builds
separate until the native runtime can run the persistence layer.

Recommended package scripts:

```json
{
  "scripts": {
    "perry:check": "perry check src/ --check-deps",
    "build:native": "mkdir -p dist/native && perry compile src/cli.ts -o dist/native/voicemail && perry compile src/processor.ts -o dist/native/voicemail-processor"
  }
}
```

Do not treat a dependency swap as Perry-compatible until compiled binaries
pass a runtime smoke test using an isolated `TSRS_DB_PATH`.
