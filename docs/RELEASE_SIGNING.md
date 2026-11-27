# Persistent Android release signing

Bisho IDE release APKs must be signed with the same private keystore for every update.
Never commit the keystore or passwords to this repository.

## Create the keystore once

Run this on a trusted computer or in Termux with Java keytool installed:

```sh
keytool -genkeypair -v -keystore bisho-release.jks -alias bisho-release -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 bisho-release.jks
```

Keep `bisho-release.jks`, its store password, key alias, and key password in a secure backup.
Losing the private key prevents signing compatible updates.

## Add repository Actions secrets

In GitHub, open Settings -> Secrets and variables -> Actions -> New repository secret.
Create these four secrets:

- `BISHO_RELEASE_KEYSTORE_BASE64`: the complete one-line Base64 output from the command above.
- `BISHO_RELEASE_STORE_PASSWORD`: the keystore password.
- `BISHO_RELEASE_KEY_ALIAS`: `bisho-release` (or the alias chosen above).
- `BISHO_RELEASE_KEY_PASSWORD`: the key password.

Do not paste these values into issues, commits, chat, or workflow logs.

The APK workflow intentionally stops before release packaging if any secret is missing.
It verifies the APK signature and increments versionCode on every workflow run.

## One-time migration warning

An installed APK can be updated only when the new APK is signed by the same private key
as the installed APK and has a higher versionCode. A private key cannot be recovered
from an APK's public signing certificate. If the old APK was signed with an ephemeral
GitHub runner debug key, a one-time uninstall/reinstall may be required after backing
up app-private projects, engine files, and build data to external storage.
