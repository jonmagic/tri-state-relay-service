# Perry package

Use the scoped package:

```sh
npm install --save-dev @perryts/perry
```

Do not use the unscoped `perry` package. It is an unrelated query-string
package.

The package provides the `perry` binary and installs the matching
platform package through optional dependencies.

Useful commands:

```sh
perry check src/
perry check src/ --check-deps
perry compile src/cli.ts -o dist/native/voicemail
perry compile src/processor.ts -o dist/native/voicemail-processor
perry doctor
perry --print-api-manifest=json
```
