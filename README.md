# flutter-fastlane

One Fastfile + GitLab CI template that builds, tests and ships any Flutter app to Google Play and
App Store Connect. Apps contribute only a few lines of config; secrets live in CI.

## Adopting it in an app

1. Copy `templates/Fastfile` → `<app>/fastlane/Fastfile`
2. Copy `templates/env.default` → `<app>/fastlane/.env.default` and fill in package/bundle ids
3. Nothing to install: the CI template runs `gem install fastlane` (version pinned by `FASTLANE_VERSION`), so no Gemfile
4. Android: make `android/app/build.gradle.kts` read signing config from env (see the rotat-flutter example)
5. Include the CI template in `.gitlab-ci.yml` (see header of `ci/flutter-fastlane.gitlab-ci.yml`)
6. Set `FASTLANE_SHARED_URL` and the secrets below in GitLab
7. Integration tests / screenshots: copy `templates/integration_test/*` (`test_driver_integration_test.dart` → `test_driver/integration_test.dart`), add `integration_test: {sdk: flutter}` to `dev_dependencies`

Local run against an unpushed checkout of this repo:
`FASTLANE_SHARED_PATH=../flutter-fastlane fastlane test` (needs `gem install fastlane`)

## Pipeline flow

| Branch | Jobs |
|---|---|
| MR, `test/*`, `main`, `main/*` | `fastlane test` |
| `test/*` | `android beta` (Play internal) + `ios beta` (TestFlight) |
| `main`, `main/*` | `android release` (Play production) + `ios release` (App Store) — upload is automatic, **submit for review is manual** unless `SUBMIT_FOR_REVIEW=true` |

Version/build from the branch name: `test/2.1.0` or `main/2.1.0` sets the version name, `test/2.1.0+215`
also forces the build number. Without it the pubspec version is used with an auto-incremented build number
(`BUILD_NUMBER` env beats both). Stores reject reused/lower build numbers, so prefer leaving the build number to auto.

## What is tracked in git

Everything fastlane produces lives under the app's `fastlane/` and is committed back by CI
(`[skip ci]`, needs `CI_PUSH_TOKEN` = project access token with `write_repository`, allowed to push to the branch):

* `fastlane/changelogs/<versionName>.txt` — **hand-written** source of truth
* `fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt` — copy per build in Play's layout (a hand-written `default.txt` there is Play's fallback)
* `fastlane/metadata/ios/<locale>/release_notes.txt`
* `fastlane/metadata/android/<locale>/images/<kind>/` and `fastlane/screenshots/ios/<locale>/` — store screenshots
* `fastlane/reports/<platform>-<version>+<build>.md` — version, track, commit, pipeline, changelog

`git log -- fastlane/` is the release history.

## Lanes

| Lane | What it does |
|---|---|
| `test` | `flutter pub get`, `flutter analyze`, `flutter test` (skipped when no `test/`) |
| `android beta` | AAB → Play `internal` (completed) + changelog |
| `android release` | AAB → Play `production`, uploaded automatically; stays a draft until you send it for review (or `SUBMIT_FOR_REVIEW=true`) |
| `ios beta` | IPA → TestFlight + changelog |
| `ios release` | IPA → App Store Connect + release notes (+ screenshots), optional submit for review |
| `android/ios screenshots` | Only capture screenshots to `build/screenshots` |

Every deploy lane posts ✅/❌ to Slack (version, build, track, changelog, job link) when `SLACK_URL` is set.
Failures re-raise, so the CI job still goes red.

Build numbers: `max(pubspec build number, latest on store + 1)`; override with `BUILD_NUMBER`.
Changelog: written by hand, never generated from commits. Put the text in
`fastlane/changelogs/<versionName>.txt` (e.g. `2.1.0.txt`) in the same branch as the version bump. Release lanes
(`main`) **fail before building** if the file is missing or empty; beta lanes (`test/*`) fall back to
`BETA_CHANGELOG_FALLBACK` (default "Test build"). Over the store limit (500 chars Play / 4000 Apple) also fails —
nothing is truncated silently. `CHANGELOG` env var overrides the file for a one-off run.

## Screenshots

Guarded by `SCREENSHOTS_ENABLED=true` (set as a CI variable per project). When it is not `true` nothing
is booted, driven or uploaded. Screenshots run in the `release` lanes only (store listing is a release concern)
and via the standalone `screenshots` lanes.

The app owns the flow: `integration_test/screenshots_test.dart` drives the real UI with `AppDriver`
(login, tap, scroll, `screenshot('01_home')`); `test_driver/integration_test.dart` writes PNGs. Nothing about
login is standardised: the Fastfile only forwards every `E2E_*` CI variable as `--dart-define`, and each app's
own test code decides which names it reads (this repo's example uses `E2E_EMAIL`/`E2E_PASSWORD`). Devices: `SCREENSHOT_IOS_DEVICES` (simulator names, booted
via `simctl`, status bar set to 9:41) and `SCREENSHOT_ANDROID_DEVICES` (`adb-serial:playFolder`, emulators
must be running — needs a runner with KVM).

## Variable reference

Non-secret (commit in `fastlane/.env.default`): `APP_NAME`, `ANDROID_PACKAGE_NAME`, `FASTLANE_TEAM_ID`,
`IOS_TARGETS` (`Target:bundle.id,...`), `IOS_SCHEME`, plus the optional ones listed in `templates/env.default`.

## Secrets

Principles: nothing secret in git, ever; CI variables are **Protected** (only available on protected
branches/tags — protect `v*` tags) and **Masked** or **File** type; one least-privilege credential per purpose;
everything is rotatable.

### Android

| Variable | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the keystore, base64 (GitLab File variables only hold text). PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) \| Set-Clipboard`; bash: `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | keystore secrets |
| `SUPPLY_JSON_KEY` | **File** variable: Google Cloud service-account JSON (or `SUPPLY_JSON_KEY_DATA` raw JSON) |

* Use **Play App Signing** and give CI only the *upload* key. If it leaks you ask Google to reset it;
  the real app-signing key never leaves Google. (Existing apps: Play Console → Setup → App signing.)
* Service account: Google Cloud → create service account + JSON key → Play Console → Users and permissions →
  invite it with only *Release apps to testing tracks / production* for the specific app.

### iOS

| Variable | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect → Users and Access → Integrations |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | `base64 -w0 AuthKey_XXXX.p8` (role: App Manager) |
| `MATCH_GIT_URL` | private repo holding the encrypted certs/profiles |
| `MATCH_PASSWORD` | passphrase that encrypts that repo (store it in a password manager too) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64 "user:read-only-token"` — a deploy/access token with **read** scope |

* [`fastlane match`](https://docs.fastlane.tools/actions/match/) keeps the distribution certificate and
  profiles encrypted (AES) in a private repo. Create them **once on a Mac**: `fastlane match appstore`
  (list every bundle id, including extensions). CI runs it `readonly`, so a compromised pipeline cannot
  mint new certificates.
* The API key avoids Apple ID passwords/2FA on CI. `setup_ci` uses a throw-away keychain per job.
* The iOS job runs on a self-hosted macOS runner (tag `macos`); keep that runner restricted to protected refs.

### Misc

| Variable | Value |
|---|---|
| `DOTENV_FILE` | **File** variable with the app's runtime `.env` (bundled as asset, not in git) |
| `SLACK_URL` | Slack incoming-webhook URL (Masked) |
| `CI_PUSH_TOKEN` | project access token (Developer+, `write_repository`) used to commit fastlane output back |
| `E2E_*` | anything the app's integration tests need (e.g. test credentials); app-defined names, forwarded as `--dart-define` |
| `FASTLANE_SHARED_URL` | only if you fork/mirror this repo (default `https://github.com/sailingbyte/flutter-fastlane.git`) |

Put variables shared by all apps (`SLACK_URL`, `MATCH_*`, `APP_STORE_CONNECT_*`, `FASTLANE_SHARED_URL`) at the
**GitLab group** level and per-app ones (keystore, Play JSON, `DOTENV_FILE`) on the project. For stronger
isolation later, move to GitLab's HashiCorp Vault / OIDC integration instead of static variables.

Never `echo` these variables in jobs, and don't enable `CI_DEBUG_TRACE`.

## Trying it: Android beta (step by step)

Prerequisite: the app already exists on Google Play with at least one release uploaded by hand.

**1. Play service account** (once)
Google Cloud Console → IAM → Service accounts → create → Keys → add JSON key. Play Console → Users and
permissions → invite the service account email → give the app *Release to testing tracks*
(+ *Release to production* for `main`). Enable the *Google Play Android Developer API* in that Cloud project.

**2. Add the GitLab CI/CD variables** (project → Settings → CI/CD → Variables). Never commit these.

| Variable | Type | Flags | Value |
|---|---|---|---|
| `SUPPLY_JSON_KEY` | File | Protected* | contents of the service-account JSON |
| `ANDROID_KEYSTORE_BASE64` | Variable | Masked, Protected* | base64 of the upload keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Variable | Masked, Protected* | keystore password |
| `ANDROID_KEY_ALIAS` | Variable | Protected* | key alias |
| `ANDROID_KEY_PASSWORD` | Variable | Masked, Protected* | key password (omit if same as keystore) |
| `DOTENV_FILE` | File | Protected* | contents of the app's runtime `.env` |
| `FASTLANE_COMMIT_CHANGES` | Variable | | `false` for now |
| `PLAY_VALIDATE_ONLY` | Variable | | `true` for the first run (dry run) |
| `SLACK_URL` | Variable | Masked, Protected* | optional - Slack incoming webhook URL |

\* *Protected* variables are only exposed to protected branches. Either mark `test/*` as a protected branch
(Settings → Repository → Protected branches) or leave Protected off while testing.

**3. Pipeline file** — the app's `.gitlab-ci.yml` includes this repo's template and sets `IOS_ENABLED: "false"`.

**4. Push a `test/*` branch** (e.g. `test/2.0.8`). Jobs: `fastlane:test`, then `fastlane:android:beta`.
It needs a Docker runner that can pull `ghcr.io/cirruslabs/flutter` and run untagged jobs.

**5. Dry run passes → real upload.** Delete `PLAY_VALIDATE_ONLY`; the next push uploads to the internal testing
track and posts to Slack.

**6. Commit-back** (optional, later): create a project access token (role Developer, scope `write_repository`),
store it as `CI_PUSH_TOKEN`, and delete `FASTLANE_COMMIT_CHANGES=false`. Needs `test/*`/`main` to allow pushes by it.

Local dry run (WSL/Mac, `gem install fastlane`): export the same variables, then
`PLAY_VALIDATE_ONLY=true FASTLANE_COMMIT_CHANGES=false fastlane android beta`.

## Using this repo

Nothing in here is secret. Apps pull the Fastfile with `import_from_git` (default
`https://github.com/sailingbyte/flutter-fastlane.git`, branch `master`; pin with `FASTLANE_SHARED_REF`) and
include the CI template via `remote:` (see the header of `ci/flutter-fastlane.gitlab-ci.yml`).
