# Android → Firebase App Distribution via GitHub Actions

One-time setup so every Android build can be pushed to all employees with a single click in the GitHub Actions tab.

The workflow lives in [.github/workflows/android-distribute.yml](../../.github/workflows/android-distribute.yml). It runs on a `ubuntu-latest` runner (cheap, ~8 min), builds the release APK signed with the upload keystore stored in GitHub Secrets, then uploads to Firebase App Distribution using a service-account key.

Unlike TestFlight, there is **no review process**, **no expiration**, and an effectively unlimited tester count. Once an employee is in the *employees* group in Firebase App Distribution they get every new build automatically.

---

## What you need before you start

1. **A Firebase project** with an Android app already registered for the bundle ID `com.bigfoottrailers.bigfoot_mobile`. (You already have this — project `bigfoot-trailers-a9911`, Android app ID `1:563599327933:android:3c1e17a4ee640492d0add4`.)
2. **Access to Google Cloud Console** for the same project, to create a service account.
3. **The release keystore** — already in this repo at `bigfoot_mobile/android/app/upload-keystore.jks`, gitignored.
4. PowerShell or `base64` available locally for one file conversion.

You do **not** need a Mac, Android Studio, or any Google Play Console account.

---

## Step 1 — Create the tester group in Firebase

1. <https://console.firebase.google.com/project/bigfoot-trailers-a9911/appdistribution/testers>
2. *Testers & Groups* tab → *Add group* → name **`employees`** (lowercase, exact — this is the group the workflow references)
3. Add each employee's email under that group. They'll get an invitation email the first time a build is distributed to the group.

You can keep adding/removing employees from this group at any time without touching the workflow.

---

## Step 2 — Create a service account for CI

1. <https://console.cloud.google.com/iam-admin/serviceaccounts?project=bigfoot-trailers-a9911>
2. *Create service account*:
   - Name: `github-actions-app-distribution` (any name; this one is descriptive)
   - Description: "GitHub Actions — Firebase App Distribution uploader"
   - Continue → *Grant this service account access to project* → add role **Firebase App Distribution Admin** (`roles/firebaseappdistro.admin`)
   - Continue → Done
3. Open the new service account → *Keys* tab → *Add key* → *Create new key* → JSON → Create.
4. A `.json` file downloads. **Save it as `d:\BigFoot\service-account.json`** (or wherever — just tell me where).
5. Tell me "service account JSON is at \<path\>" and I'll base64-encode it for the secret.

---

## Step 3 — Add the GitHub Secrets

<https://github.com/zahrajamshaid/bigfoot-trailers/settings/secrets/actions> → *New repository secret* (one for each row):

| Secret name | Value | Notes |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | *contents of* `d:\BigFoot\android_keystore.b64` | I generated this for you from the existing `upload-keystore.jks`. Paste the entire string as one line. |
| `ANDROID_KEYSTORE_PASSWORD` | the `storePassword=` value from `bigfoot_mobile/android/key.properties` | Sensitive — only the GitHub Secrets UI should ever see it |
| `ANDROID_KEY_PASSWORD` | the `keyPassword=` value from `bigfoot_mobile/android/key.properties` | Often the same as `ANDROID_KEYSTORE_PASSWORD` |
| `ANDROID_KEY_ALIAS` | `upload` | from `key.properties` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | *raw contents* of the service-account JSON (not base64) | `google-github-actions/auth@v2` accepts the JSON directly |

That's only 5 secrets — half the iOS list.

---

## Step 4 — Run the workflow

<https://github.com/zahrajamshaid/bigfoot-trailers/actions/workflows/android-distribute.yml> → **Run workflow** → Branch = `main` → optional release notes → **Run**.

End-to-end is ~10 min:
- ~3 min Flutter setup + `pub get`
- ~5 min Gradle build (smaller than iOS because no Xcode, no CocoaPods)
- ~1 min Firebase upload

When the workflow finishes:
- Every employee in the *employees* group gets an email from Firebase: *"A new build is available."*
- They tap the link → if they haven't installed the **Firebase App Tester** app yet, they're guided to the Play Store to grab it → then the new build is one tap.
- For subsequent builds, the App Tester app already on their phone notifies them — same way TestFlight notifies iOS testers.

---

## How is this different from TestFlight?

| | iOS — TestFlight | Android — Firebase App Distribution |
|---|---|---|
| Review process | Yes, ~24 h on first build per version | **None** |
| Build expires | After 90 days | **Never** |
| Tester limit | 10,000 | **Effectively unlimited** |
| Tester install path | Install TestFlight from App Store → tap link | Install Firebase App Tester from Play Store → tap link. *Or* tap a direct APK link, no tester app needed |
| Cost | $99/yr Apple Dev | **Free** (uses your existing Firebase project) |
| CI runner | `macos-14` (~$0.08/min) | `ubuntu-latest` (~$0.008/min, usually free quota) |

---

## Optional — auto-distribute on every push to main

The workflow is manual-trigger only by default. If you want every commit to `main` to auto-push a build to employees (handy for active development, noisy for stable releases), uncomment the `push:` block at the top of [.github/workflows/android-distribute.yml](../../.github/workflows/android-distribute.yml).

---

## Troubleshooting

- **`Failed to authenticate, have you run firebase login?`** — `FIREBASE_SERVICE_ACCOUNT_JSON` secret is empty, malformed, or the service account doesn't have *Firebase App Distribution Admin* role. Recheck the role assignment in Google Cloud IAM.
- **`Could not find application with id …`** — `FIREBASE_APP_ID` in the workflow doesn't match the Firebase Android app. Confirm at <https://console.firebase.google.com/project/bigfoot-trailers-a9911/settings/general>.
- **`Could not find group employees`** — you haven't created the `employees` group in Firebase App Distribution (step 1). The group name in `TESTER_GROUPS` and the Firebase Console must match exactly, case-sensitive.
- **Gradle: `Keystore was tampered with, or password was incorrect`** — `ANDROID_KEYSTORE_BASE64` was uploaded with line wrapping, or the wrong password is in the secret. Regenerate base64 with `[Convert]::ToBase64String(...)` (PowerShell — single continuous string) and verify the password matches what's in the local `key.properties`.
- **`Execution failed for task ':app:lintVitalAnalyzeProductionRelease'`** — happens when Android lint catches issues. Usually a false positive on a dependency. Quick fix: add `lint { abortOnError false }` inside the `android {}` block of `bigfoot_mobile/android/app/build.gradle.kts`. Don't disable lint permanently — fix the lint warnings instead.

---

## What this does NOT cover

- **Google Play Store listing.** This pipeline does *not* publish to Google Play. Employees install via Firebase App Distribution, period. If you ever want a Play Store presence (for public discoverability), that's a separate one-time $25 Play Console setup.
- **Per-flavor distribution to different groups** — the workflow builds the `production` flavor only and pushes to one group. If you want dev/staging/prod builds going to separate Firebase Apps or tester groups, the workflow needs duplicating per flavor.
- **App icons.** Unlike iOS, Android has no Apple-review gate, so placeholder icons technically work for employees. But replace them with proper icons via `flutter_launcher_icons` before shipping anywhere public.
