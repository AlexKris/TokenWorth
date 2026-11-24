# Contributing to TokenWorth

Thank you for contributing to TokenWorth!

## Development Requirements

- macOS 14+ (Sonoma or newer)
- Swift 6.0+ (works with **Apple Command Line Tools alone** — full Xcode is optional)

> **Important SwiftUI Note:** To keep builds working on machines that only have Apple Command Line Tools installed (where `SwiftUIMacros` is unavailable), do not use `@State`, `@Entry`, `@Animatable`, or `#Preview` in `Sources/TokenWorthApp/`. Use `@Observable` models with `@Bindable` instead.

## Local Workflow

```bash
# Run Swift Testing suites (with Xcode)
swift test

# Run Swift Testing suites (with Apple Command Line Tools alone)
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

# Build app and CLI
swift build

# Run CLI in demo mode
swift run tokenworth-cli summary --demo

# Build signed local .app bundle
./scripts/build-app.sh
```

## Adding a New Model Pricing Entry or Provider

1. **Pricing**: Add or update entries in `Sources/TokenWorthCore/Pricing/PricingCatalog.swift` (`defaultModels`) and verify resolution in `Tests/TokenWorthCoreTests/PricingCatalogTests.swift`.
2. **Log Parser**: Implement `UsageLogParser`, deduplicate streaming or repeated snapshots cleanly, register it in `IncrementalLogCache.defaultParsers()`, and add unit tests with synthetic fixtures.
3. **Quota Provider**: Implement `QuotaProvider` using `HTTPTransport` (for mockable tests), keep all external state strictly read-only, and never read macOS Keychain without checking `settings.allowKeychainReads`.

## Commit & License Rules

- Use concise [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- All contributions are licensed under the **GNU General Public License v3.0** (`GPL-3.0`). See [LICENSE](LICENSE).
