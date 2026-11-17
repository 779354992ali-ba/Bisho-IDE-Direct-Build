# Bisho IDE — Package 82

Package 82 hardens the in-app local build pipeline and defines the exact engine archive contract required to complete it.

See:
- `PACKAGE82_CHANGELOG.md` for implemented changes and validation limits.
- `PACKAGE82_RUNTIME_BUNDLE_SPEC.md` for the required ARM64 runtime bundle structure and acceptance test.
- `engine-manifest.example.json` as the schema-1 manifest template for the runtime bundle publisher.
- `engine-executables.example.txt` as the template for restoring executable permissions after safe ZIP extraction.

**Important:** this source package does not contain the multi-gigabyte runtime archive or a trusted archive URL/hash. Local building is not yet certified until a compatible runtime bundle is installed and a real APK is produced on the target Android device.
