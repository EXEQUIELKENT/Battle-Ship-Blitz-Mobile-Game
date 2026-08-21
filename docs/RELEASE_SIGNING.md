# Release signing — why updates used to need an uninstall

Android will only install an APK over an existing one when **both** are
signed by the same key. Until now nothing in this project provided one,
so every release build silently fell back to the *debug* keystore — and a
debug keystore is generated per machine. The dev laptop had one, the
GitHub Actions runner made itself a different one, so the two builds were,
as far as Android was concerned, two unrelated apps claiming the same
package name. Installing either over the other failed with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, and the only way through was an
uninstall — which wipes the saved profile, RP and everything bought in the
shipyard.

There is now a real, permanent release key. Builds signed with it install
straight over each other, keeping all saved data.

## What is already set up

| File | Purpose | In git? |
| --- | --- | --- |
| `android/app/release-key.jks` | The signing key. Valid to **2056**. | **No** — gitignored |
| `android/app/key.properties` | Its passwords and alias. | **No** — gitignored |
| `android/app/build.gradle.kts` | Already reads both, and falls back to the debug key if they are missing. | Yes |

Local `flutter build apk --release` picks this up with no extra flags.

> **Back both files up somewhere off this machine.** They are deliberately
> not in git, and they cannot be regenerated: lose them and the *only* way
> to install a future build is an uninstall, taking the save with it.
> A copy in a password manager or a private cloud folder is enough.

## Making GitHub Actions builds match

CI builds are still signed with a throwaway debug key until you add the
key as repository secrets — the workflow prints a warning when it does.

1. Open the repo on GitHub → **Settings → Secrets and variables → Actions**.
2. Add four **repository secrets**:

   | Name | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | the entire contents of `docs/.keystore-base64.txt` |
   | `ANDROID_STORE_PASSWORD` | `storePassword` from `android/app/key.properties` |
   | `ANDROID_KEY_PASSWORD` | `keyPassword` from the same file |
   | `ANDROID_KEY_ALIAS` | `battleshipblitz` |

3. Delete `docs/.keystore-base64.txt` once pasted. It is gitignored, but
   it is a plain-text copy of the private key sitting in the working tree
   and it has no further use — the `.jks` is the real one to keep.

## Every time you ship a build

Bump the build number in `pubspec.yaml`:

```yaml
version: 1.1.0+2      # ← the +N
```

Android compares that `+N` (`versionCode`). A **higher** number is an
update; the **same** number reinstalls in place; a **lower** number is
refused outright. Bump it on every build you intend to hand to a device
that already has the game.

## Checking a build before you hand it over

```bash
# Which key signed it — the SHA-256 must match on both builds
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk

# What versionCode it carries
aapt dump badging build/app/outputs/flutter-apk/app-release.apk | head -1
```

`apksigner` and `aapt` live in `$ANDROID_HOME/build-tools/<version>/`.
