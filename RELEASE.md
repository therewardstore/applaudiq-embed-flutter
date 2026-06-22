# Releasing `applaudiq_embed`

Maintainer guide for publishing the SDK to [pub.dev](https://pub.dev/packages/applaudiq_embed).

## One-time setup

1. **pub.dev account / verified publisher.** Sign in once: `dart pub login` (opens a browser; use the
   Google account tied to the `therewardstore` publisher). Confirm the publisher owns `applaudiq_embed`.
2. **Git remote.** Tags are pushed on release:
   ```sh
   git remote add origin git@github.com:therewardstore/applaudiq-embed-flutter.git
   ```

## Each release

1. **Update the changelog** — add a new `## X.Y.Z` section to [`CHANGELOG.md`](./CHANGELOG.md). pub.dev shows
   it on the package page and dings the score if the top entry doesn't match `pubspec.yaml`'s `version`.
2. **Bump `version:`** in `pubspec.yaml`.
3. **Validate, then publish:**
   ```sh
   flutter pub get
   flutter analyze            # must be clean
   flutter test               # unit tests green
   dart pub publish --dry-run # validates pubspec, LICENSE, CHANGELOG, example, analysis
   flutter pub publish        # the real publish (prompts for confirmation)
   ```
4. **Tag + push:**
   ```sh
   git tag 1.0.0 && git push origin main --tags
   ```

## After publishing

The example app (`applaudiq-sdk-example/native-integration/flutter`) consumes the SDK via a local
`path:` dependency pre-publish. Once it's on pub.dev, switch its `pubspec.yaml`:

```yaml
dependencies:
  applaudiq_embed: ^1.0.0   # was: { path: ../../../applaudiq-embed-flutter }
```

## Notes

- **What ships:** everything not in `.gitignore` / `.pubignore` — `lib/`, `README.md`, `CHANGELOG.md`,
  `LICENSE`, `pubspec.yaml`, `example/`. Verify with `dart pub publish --dry-run` (lists the file set).
- **pub score:** an `example/`, dartdoc on public APIs, and a clean `dart analyze` drive the pub.dev points.
