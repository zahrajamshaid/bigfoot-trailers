# iOS → TestFlight via GitHub Actions

One-time setup so every TestFlight build is a single click in the GitHub Actions tab — no Mac required afterwards.

The workflow lives in [.github/workflows/ios-testflight.yml](../../.github/workflows/ios-testflight.yml). It runs on a `macos-14` runner, builds the release IPA with manual signing using a cert + provisioning profile pulled from GitHub Secrets, then uploads via `xcrun altool` using an App Store Connect API key.

---

## What you need before you start

1. **Active Apple Developer Program membership** ($99/yr) at <https://developer.apple.com/account>
2. **App Store Connect record** for the app — bundle ID **`com.bigfoottrailers.bigfootMobile`** (see step 1 in [../ios/README.md](../ios/README.md))
3. **Firebase iOS app** registered with the same bundle ID, so you can download `GoogleService-Info.plist`
4. Windows or any OS with `openssl` and `base64` available (e.g. Git Bash, WSL)

You do **not** need a Mac to do any of this.

---

## Step 1 — Generate the signing certificate (Windows-friendly)

The distribution cert is normally created from Keychain on a Mac. To do it on Windows, generate a CSR with OpenSSL, upload it to Apple, then bundle the issued cert + your private key into a `.p12`:

```sh
# Generate a fresh private key
openssl genrsa -out ios_dist.key 2048

# Generate a CSR (use any email + name)
openssl req -new -key ios_dist.key -out ios_dist.csr \
  -subj "/emailAddress=you@example.com/CN=Bigfoot Trailers iOS Distribution/C=US"
```

Now in the browser:

1. <https://developer.apple.com/account/resources/certificates/list> → **+**
2. **Apple Distribution** (works for both Ad Hoc and App Store) → Continue
3. Upload `ios_dist.csr` → Continue → **Download** the resulting `distribution.cer`

Back on Windows, bundle it into a `.p12`:

```sh
# Convert Apple's DER-encoded .cer to PEM
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM

# Bundle key + cert into a .p12 with a password of your choice
openssl pkcs12 -export \
  -inkey ios_dist.key \
  -in distribution.pem \
  -out ios_dist.p12 \
  -name "Apple Distribution: Bigfoot Trailers" \
  -password pass:CHOOSE_A_PASSWORD
```

Remember `CHOOSE_A_PASSWORD` — it becomes the `IOS_P12_PASSWORD` secret.

---

## Step 2 — Create the provisioning profile

1. <https://developer.apple.com/account/resources/profiles/list> → **+**
2. **App Store** under *Distribution* → Continue
3. App ID → `com.bigfoottrailers.bigfootMobile`
4. Certificate → the distribution cert you just created
5. Name it something memorable, e.g. `Bigfoot Trailers App Store` — **this exact string becomes the `IOS_PROVISIONING_PROFILE_NAME` secret**
6. Download the `.mobileprovision` file

---

## Step 3 — Create an App Store Connect API key

This is what the workflow uses to upload the IPA. It's separate from the signing cert.

1. <https://appstoreconnect.apple.com/access/integrations/api> → **+** (Team Keys section)
2. Name (anything), Access = **App Manager**
3. **Generate** → download `AuthKey_XXXXXXXXXX.p8` *immediately* (Apple shows it only once)
4. Note the **Key ID** (10 chars, e.g. `ABCD1234EF`) and the **Issuer ID** (UUID at the top of the page)

---

## Step 4 — Download Firebase iOS config

1. <https://console.firebase.google.com> → your project → ⚙️ → *Project settings* → *Your apps*
2. *Add app* → iOS → bundle ID `com.bigfoottrailers.bigfootMobile`
3. Download `GoogleService-Info.plist`
4. *Cloud Messaging* tab in the same project → upload your **APNs Authentication Key** (a separate `.p8` from Apple — generate at <https://developer.apple.com/account/resources/authkeys/list>, scope = Apple Push Notifications service). Without this, push doesn't deliver to iOS — even though the build itself will succeed.

---

## Step 5 — Base64-encode the files

GitHub Secrets store strings, so binary files need to be base64'd first. Run these in the same directory as the files:

```sh
# Linux / macOS / WSL / Git Bash
base64 -w 0 ios_dist.p12                                > ios_dist.p12.b64
base64 -w 0 BigfootTrailersAppStore.mobileprovision     > profile.b64
base64 -w 0 AuthKey_ABCD1234EF.p8                       > authkey.b64
base64 -w 0 GoogleService-Info.plist                    > gsi.b64
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("ios_dist.p12"))                            | Set-Content ios_dist.p12.b64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("BigfootTrailersAppStore.mobileprovision"))   | Set-Content profile.b64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_ABCD1234EF.p8"))                   | Set-Content authkey.b64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("GoogleService-Info.plist"))                | Set-Content gsi.b64
```

You'll paste the contents of each `.b64` file into the corresponding GitHub Secret.

---

## Step 6 — Add the GitHub Secrets

<https://github.com/zahrajamshaid/bigfoot-trailers/settings/secrets/actions> → *New repository secret* (one for each row):

| Secret name | What goes in it | Where to get it |
|---|---|---|
| `APPLE_TEAM_ID` | 10-char team ID, e.g. `ABCDE12345` | <https://developer.apple.com/account> → Membership |
| `IOS_BUILD_CERTIFICATE_BASE64` | contents of `ios_dist.p12.b64` | step 5 |
| `IOS_P12_PASSWORD` | the password you chose in step 1 | step 1 |
| `IOS_PROVISIONING_PROFILE_BASE64` | contents of `profile.b64` | step 5 |
| `IOS_PROVISIONING_PROFILE_NAME` | exact name string from step 2, e.g. `Bigfoot Trailers App Store` | step 2 |
| `IOS_KEYCHAIN_PASSWORD` | any random string — used only for the runner's temp keychain | invent one |
| `APPSTORE_API_KEY_ID` | 10-char key ID | step 3 |
| `APPSTORE_API_ISSUER_ID` | UUID | step 3 |
| `APPSTORE_API_KEY_BASE64` | contents of `authkey.b64` | step 5 |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | contents of `gsi.b64` | step 5 |

Once all 10 are set, **delete the local files** (`.p12`, `.p8`, `.mobileprovision`, `.b64`) from your machine — GitHub now has the only copies, and that's the point.

---

## Step 7 — Run the workflow

<https://github.com/zahrajamshaid/bigfoot-trailers/actions/workflows/ios-testflight.yml> → **Run workflow** → Branch = `main` → optional release notes → **Run**.

Watch the steps in the Actions UI. End-to-end is ~25 min (Xcode + CocoaPods + Flutter build + upload). The build number auto-bumps to `github.run_number`, so each run is uniquely versioned.

When the workflow finishes:

- Apple processes the build for ~5–15 min ("Processing" in TestFlight)
- Once green, add internal testers in App Store Connect → TestFlight → *Internal Testing*
- External testing needs Apple's one-time beta review (~24 h) per app version

---

## Troubleshooting

- **`No certificate matching ...`** — wrong cert in `IOS_BUILD_CERTIFICATE_BASE64`, or the cert in the .p12 doesn't include the private key (re-do step 1; both `-inkey` and `-in` must be present in the `openssl pkcs12 -export` command).
- **`Provisioning profile … doesn't include the currently selected device`** — you uploaded a development profile, not an App Store distribution one. Redo step 2 picking *App Store* under Distribution.
- **`No suitable application records …`** — the App Store Connect app record doesn't exist yet; create it (see [../ios/README.md](../ios/README.md) step 1) before running the workflow.
- **`Invalid Bundle ID … doesn't match the provisioning profile`** — your provisioning profile is for a different bundle ID. Apps and profiles are bound to one ID; recreate the profile against `com.bigfoottrailers.bigfootMobile`.
- **`Authentication credentials are missing`** on the upload step — `APPSTORE_API_KEY_BASE64` was set with the file contents *unbase64'd*, or with line wrapping. Re-encode with `base64 -w 0` (Linux/macOS) or PowerShell's `ToBase64String` (one continuous string, no wrap).
- **Runner runs out of disk space** — uncommon, but if it happens add `df -h` to a debug step. The pod cache occasionally bloats.

If the upload step succeeds but the build never appears in TestFlight, check email — Apple often emails the developer when a build is rejected for missing icons or metadata before it gets to the visible "Processing" stage.

---

## What this does NOT cover

- **App icons.** The Flutter scaffold ships placeholder icons; Apple will reject distribution builds without a proper 1024×1024 marketing icon. Generate icons with [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) before your first external-testing build.
- **Per-flavor schemes** on iOS (development / staging / production) — the workflow builds one IPA pointed at production via `--dart-define`. If you ever need three separately-installable iOS apps, add flavor schemes in Xcode (see [../ios/README.md](../ios/README.md) step 5) and parameterise the workflow.
- **Auto-incrementing marketing version.** Only the build number bumps automatically (from `github.run_number`). The `1.0.0` in `pubspec.yaml` stays put until you change it by hand.
