# Package80 — Bisho IDE

Package80 adds a streaming, checksum-verified local build engine installer. Open the local build panel and choose **تثبيت محرك البناء من حزمة موثوقة**. Provide a direct HTTPS ZIP URL and the publisher's SHA-256 value.

The package intentionally does not ship a runtime bundle or invent a download endpoint. Installing files does not activate local builds: Bisho IDE still requires a successful real APK build on the same device before reporting the runtime as verified.

See `PACKAGE80_ENGINE_INSTALLER.md` for the archive layout, safeguards, and validation limitations.
