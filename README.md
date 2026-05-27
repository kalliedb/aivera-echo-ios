# Aivera Echo — iOS

Native iOS app for [Aivera Echo](https://aivera.solutions/echo) — voice-first reminders.
Sister to [`aivera-echo-android`](https://github.com/kalliedb/aivera-echo-android).

## Stack

- **Swift 5.10, SwiftUI** — minimum **iOS 16**
- **Apple Speech (`SFSpeechRecognizer`)** — on-device transcription, free, no model bundle
- **AVFoundation** — single `AVAudioEngine` feeds the recogniser AND a clip file (parity with Android's Vosk pipeline)
- **Supabase Swift SDK** (next) — auth + cloud sync, shared project with Android
- **GRDB + SQLCipher** (next) — encrypted local persistence
- **UserNotifications + BGTaskScheduler** (next) — time alarms and background fires
- **Core Location + CLCircularRegion** (next) — place reminders
- **StoreKit 2** (post-LTD) — annual subscriptions
- **XcodeGen** — `.xcodeproj` is generated, not committed

Bundle id: `solutions.aivera.echo` · same Firebase project (`smartaicrm`) for Crashlytics/Analytics.

## Local dev (on a Mac)

```sh
brew install xcodegen
xcodegen generate
open AiveraEcho.xcodeproj
```

Then ⌘R in Xcode to run on Simulator. First run will prompt for Microphone and Speech Recognition permissions.

## CI

GitHub Actions builds on `macos-14` with Xcode 15.4 — see [`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml). Every push to `main` is verified to compile on Simulator. TestFlight deploy job is added once the Apple Developer Program enrollment finalises (signing certs + ASC API key → GitHub Secrets).

## Project layout

```
Sources/AiveraEcho/
├── AiveraEchoApp.swift     SwiftUI app entry
├── Info.plist              Stub; XcodeGen merges project.yml into the real plist
├── UI/
│   ├── HomeView.swift      List + mic + nav
│   ├── MicButton.swift     The 72pt purple gradient circle
│   ├── RecordingOverlay.swift   Live partial-text + amplitude bar + save/cancel
│   ├── ReviewSheet.swift   Save form: text + datetime + repeat
│   └── ReminderRow.swift   List cell
├── Speech/
│   └── SpeechRecognizer.swift   SFSpeechRecognizer wrapper, on-device only
├── Reminder/
│   └── Reminder.swift      Cross-platform model (mirrors Android Task.kt)
├── Data/
│   └── ReminderStore.swift In-memory store; becomes GRDB-backed in M2
├── Audio/                  (next) AVAudioPlayer wrapper
└── Theme/
    └── Colors.swift        Purple palette (mirrors Android Color.kt §4.3)
```

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| M1 — Compilable skeleton | App scaffold, SwiftUI nav, mic UI, SFSpeechRecognizer wired, theme, CI green | ✅ (this commit) |
| M2 — Persistence + reminders | GRDB+SQLCipher repository, Reminder CRUD, AVPlayer playback | next |
| M3 — Notifications + scheduling | UNUserNotificationCenter + BGTaskScheduler, snooze, "Done" actions | |
| M4 — Place reminders | Core Location, CLCircularRegion, in-app picker | |
| M5 — Cloud sync | supabase-swift, sign-in, mirror Android reminders table | |
| M6 — Settings + onboarding | Theme, retention, delete-account, 3-page onboarding | |
| M7 — LTD entitlement check | Fetch entitlement on sign-in, unlock Pro by email | |
| M8 — Crashlytics + Analytics | firebase-ios-sdk, register in same Firebase project as Android | |
| M9 — StoreKit 2 (post-LTD) | Annual subscription via Apple IAP | |
| M10 — App Store submission | Listing, screenshots, Data Safety, TestFlight → public | |

## Why XcodeGen

- The `.xcodeproj` is a complex generated artefact — checking it in causes constant merge conflicts on a multi-dev team.
- Defining the project in `project.yml` keeps the source of truth human-readable, diffable, and editable from any OS.
- CI generates fresh on every build → no drift between local and CI.
