# Release guide

1. Work in the InternetPulse repository only. Preserve `local.routerpulse.app` on macOS so existing preferences/history migrate. The displayed product name is always Internet Pulse.
2. Update VERSION, BUILD_NUMBER, Windows project/manifest/assembly versions, release history, translated documentation and release notes together. Historical dates already present are retained.
3. Run macOS model/update tests, loopback network tests and package script. The finished app depends only on system libraries; end users do not install developer tools.
4. Run Windows core tests, self-contained x64 publish, WPF open/close smoke test and preview capture in Windows CI. A passing server-side Windows runner is not a hands-on Windows 11 UI check.
5. Check all language screenshots visually: branding, version, grouping, units, labels, clipping and private data. Documentation media uses synthetic data and is labeled as a demo.
6. Recheck server URLs with scripts/check-servers.py; use public provider test endpoints only, retain sources, reject HTML/empty files and TLS errors, and label upload support only when tested with the app’s protocol.
7. Publish exact tested archives and SHA256 sums with a version tag. Never overwrite an existing release’s archive with different bytes under the same version. Close older apps before replacing them.
8. Verify public downloads and the in-app manual update checker against the published GitHub release. Update the About text and translated READMEs to match actual availability.

macOS: `./scripts/test.sh`, `./scripts/test-network.sh`, `./scripts/package.sh`.

Windows: `dotnet run --project Windows.Tests -c Release`; `dotnet publish Windows -c Release -r win-x64 --self-contained true -o dist/windows`. Zip the whole output directory.

The CI uses `macos-15-intel` to avoid the previously observed arm64 runner queue issue and cross-compiles the Apple Silicon bundle. This runner will need review before its published retirement. Windows uses the standard `windows-latest` runner, not a paid larger runner. No account/payment changes are required.

Ad hoc macOS signatures do not expire after two weeks. Builds remain unnotarized; Windows archives are unsigned. Do not disable platform protections or invent signing credentials.
