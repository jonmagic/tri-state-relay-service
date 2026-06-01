# Runtime compatibility

Perry can compile more TypeScript than it can execute when code depends
on unsupported Node APIs.

Current TSRS storage choice:

- `src/storage/store.ts` uses `better-sqlite3`.
- `perry check src/ --check-deps` must pass before native builds are treated as compatible.
- Perry-built binaries must pass a smoke test with an isolated `TSRS_DB_PATH`.

Before claiming native binaries are usable, run a smoke test:

```sh
tmpdir=$(mktemp -d)
TSRS_DB_PATH="$tmpdir/relay.db" ./dist/native/relay --line Brain --message "Native smoke test."
TSRS_DB_PATH="$tmpdir/relay.db" ./dist/native/relay list
```

If this fails, keep native builds documented as blocked and add the
specific unsupported API or dependency to the roadmap.
