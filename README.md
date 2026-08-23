# Medx-elite iOS Native Application

A brand-new native iOS application built in **pure Swift and SwiftUI**, targeting **iOS 17/18+**, connected directly to the **Medx-elite Firebase backend** (`medx-e9acd`) and Arise CDNs.

Designed to Apple's Human Interface Guidelines: flat semantic surfaces, native navigation and toolbars, system materials reserved for chrome that actually floats, Dynamic Type throughout, and full VoiceOver labelling. Materials appear in exactly one place — `medxBar` — and nowhere in content. The one deliberate exception is the brand itself: the app icon and the launch screen get a layered glass treatment, because an icon is chrome *about* the app rather than content *within* it.

Two targets ship from this project: the app, and a `MedxWidgets` extension carrying two Home Screen widgets, three Lock Screen accessories and two Live Activities.

---

## Design language

| Rule | Where it lives |
|---|---|
| Content sits on flat, semantic, grouped backgrounds | `MedxSurface`, `medxCard()`, `medxTile()` |
| Materials only for chrome that floats over content | `medxBar()` — bottom action bars |
| Glass is allowed on the **app icon and the splash screen only** | `MedxLogoMark`, `.agents/make_app_icon.py` |
| Never put an interactive glass effect inside a button label | it swallows the tap on iOS 26; this is what broke the flashcard close button |
| Fonts are native text styles at the point of use | `.headline`, `.subheadline.weight(.semibold)`, `.caption.monospacedDigit()` |
| Colour tokens name *meaning*, never brand | `MedxTheme` — all system colours, so Dark Mode and Increase Contrast work for free |
| One accent for interactive chrome, chosen in Settings | `MedxTheme.accent` — **not** `Color.accentColor`, which reads the asset catalogue and does not follow `.tint()` |
| Entry animations are opacity and offset, never scale | `medxScrollReveal()` |

---

## Features

| Feature | Description |
|---|---|
| **Profiles & Authentication** | Graveyard (Mathu) and QuantumGuy (Sri) profile switching with iOS Keychain saved-password fast unlock. |
| **Home Dashboard** | Exam countdown (editable by long press), today's goal ring and streak, a spaced-revision row, six quick actions, Continue-watching resume, a 7-day roll-up, QBank coverage ring, accuracy chart, and the syllabus checklist. |
| **Syllabus Tracker Matrix** | Live 23-subject checklist (Videos, R1, R2, PYQs, Rev, QBank) with optimistic updates and rollback if the Firestore write fails. |
| **Question Bank** | 17,890 questions across 23 subjects and 1,211 modules. Searchable subjects, collapsing chapters, per-module best-score badges, long-press to start a module directly in either mode, and long-press a subject to search it or build a module from it. |
| **Interactive Runner** | **Exam Mode** (overall timer, bulk submit, scored review, Lock Screen Live Activity) and **Revision Mode** (60s per question, instant reveal). Native toolbar and bottom action bar, swipe left/right between questions, double-tap the stem to bookmark, question navigator. Sittings auto-saved to `medx_attempts`. |
| **Rich question rendering** | Custom HTML renderer: inline `<img>` figures render and zoom full-screen, authored light-mode colours and highlights are re-mapped for Dark Mode, and parses are cached so a 40-question review scrolls at frame rate. |
| **Batch Tests** | Scored and practice papers with a scope filter, Arise prior-attempt stats, and best-score history. |
| **Flashcard Gallery** | 895 high-yield cards from the Arise CloudFront CDN. Contact-sheet grid, Photos-style pager with pinch zoom, swipe from anywhere on the card, and an artwork override (Auto / Phone / Tablet × Portrait / Landscape) plus a quarter-turn rotate for reading landscape cards on a portrait phone. |
| **Video Classroom** | 67 recorded classes by Batch and Subject. Native HLS `AVPlayer` with background audio, PiP, and silent resume. |
| **Offline Downloads** | Per-class HLS downloads with quality choice, pause/resume, a Live Activity for progress, and playback with no signal through a custom `medxoffline://` scheme rather than a local HTTP server. Watch progress is shared between a download and the streaming copy of the same class, and offline progress is pushed to Firestore on the next sync. |
| **Offline Performance** | Multi-tier caching for documents (`CacheManager`) and images (`MedxImageLoader`, with downsampled decode). |

---

## System integration

| Feature | Description |
|---|---|
| **Home Screen widgets** | `Exam countdown` (small / medium) and `Daily goal & streak` (small / medium), both reading one shared `MedxStudySnapshot`. |
| **Lock Screen widgets** | The countdown as `accessoryCircular`, `accessoryRectangular` and `accessoryInline`. |
| **Live Activities** | Exam-mode sitting on the Lock Screen and Dynamic Island — the clock is handed over as an end date so the *system* ticks it and the app only pushes the answered count. Download progress gets its own activity. |
| **Local notifications** | Daily question reminder at a chosen hour, a streak-protection nudge at 21:00 only while the streak is actually at risk, and a spaced-revision digest at 08:00 only when something is due. Rebuilt on every foreground so the wording carries live numbers. |
| **Spotlight** | Bookmarks and all 1,211 modules indexed with `CoreSpotlight`; a module result opens its mode picker. One switch in Settings deletes the whole index. |
| **App Intents / Siri** | "Start today's revision", "Exam countdown" (answers without launching) and "Search questions", donated as `AppShortcut`s. |
| **Question search** | Full-text search over the whole bank with filters for image-based, attempted / wrong / unattempted, bookmarked, and subject. Results can be turned straight into a sitting. |
| **Custom modules** | Choose subjects, scope, length and mode; questions are assembled from bookmarks, the index, or random module sampling — whichever can supply them. |
| **iPad** | `NavigationSplitView` two-column layout at regular width, `TabView` on iPhone. |
| **Theming** | Eight system accents and a light/dark/automatic override in Settings, carried through to the widgets and Live Activities. |
| **Spaced revision** | A 1/3/7/21/45-day schedule per module, driving the Home row, the digest notification and the Siri shortcut. |

### Offline video architecture

Downloads are fetched segment by segment (`VideoDownloadStore`) and the media playlist is
rewritten to plain sibling filenames. Playback then goes through a **custom URL scheme**,
`medxoffline:///<folder>/local.m3u8`, served by `MedxOfflineAssetLoader`
(`AVAssetResourceLoaderDelegate`) straight out of the app container:

- AVFoundation refuses to load an HLS playlist from a `file://` URL, which is why the saved
  playlist cannot simply be handed to `AVPlayer`.
- Because the playlist uses relative names, AVFoundation resolves the segments against that
  base URL and asks the same delegate for them — no local HTTP server is involved.
- **`HLSProxyServer` is now only for live streaming**, where it is the only thing that can
  attach the HAR-captured headers the CDN insists on.
- The loader **must** stay retained (`@State` in `VideoPlayerView`): `AVAssetResourceLoader`
  holds its delegate weakly, and a released loader stalls playback with no error.
- `VideoPlayerView.fallBackToOnlinePlayback()` stays — AVFoundation can still reject a locally
  rewritten playlist, and without it the class dead-ends on a black screen.

### The question index

Question bodies live in 1,211 Firestore module documents that are normally only fetched when a
module is opened, so searching all 17,890 questions means having pulled them down once. That is
an **opt-in build** in Settings with a progress bar, resumable across launches, and it also
warms `FirestoreService`'s module cache — so building the index makes those modules playable
offline too. Search works on whatever is indexed so far and says so.


---

## Project Structure

```
medx-elite-ios/
├── MedxElite.xcodeproj/             # Native Xcode project: MedxElite + MedxWidgets targets
├── Package.swift                    # Swift Package Manifest (iOS 17+)
├── Config/
│   ├── MedxElite.entitlements       # App Group, shared with the widget extension
│   └── MedxWidgets.entitlements
├── MedxWidgets/                     # Widget extension — Xcode target only, not mirrored
│   ├── MedxWidgetsBundle.swift      # Both widgets + both Live Activities
│   └── Info.plist
├── MedxElite/
│   ├── App/
│   │   ├── MedxEliteApp.swift       # Lifecycle, deep links, Spotlight continuation, splash
│   │   ├── AppState.swift           # Global state + `MedxRoute`, the one external-entry map
│   │   └── MedxSplashView.swift     # Launch animation over the live root
│   ├── Models/
│   │   ├── Profile.swift            # Graveyard & QuantumGuy profile definitions
│   │   ├── QBank.swift              # Subjects, chapters, modules, questions, options
│   │   ├── Test.swift               # Batch tests, gradable status, performance stats
│   │   ├── Flashcard.swift          # Flashcard subjects, cards, auto-detected CDN variants
│   │   ├── Video.swift              # Recorded classes, batches, durations, HLS stream URLs
│   │   ├── Attempt.swift            # Attempts, responses, `RunnerPayload` (+ inline questions)
│   │   └── UserTracker.swift        # Syllabus matrix checklist document model
│   ├── Services/
│   │   ├── FirebaseConfig.swift     # Backend API keys, project IDs, and endpoints
│   │   ├── AuthService.swift        # Firebase Auth REST & iOS Keychain store
│   │   ├── FirestoreService.swift   # High-performance Firestore REST client & parser
│   │   ├── HapticManager.swift      # Tactile haptic feedback engine
│   │   ├── CacheManager.swift       # On-disk & memory document cache
│   │   ├── HLSProxyServer.swift     # Live-stream header proxy + `VideoDownloadStore`
│   │   ├── MedxSharedState.swift    # App Group snapshot + ActivityAttributes (shared target)
│   │   ├── MedxStudyStatsStore.swift# Streak, goal, spaced revision + `MedxLiveActivityController`
│   │   ├── MedxNotificationManager.swift # The three reminders
│   │   ├── MedxSpotlightIndexer.swift    # CoreSpotlight index for bookmarks and modules
│   │   ├── MedxAppIntents.swift     # Siri shortcuts
│   │   └── MedxQuestionIndexStore.swift  # The opt-in full-text index
│   ├── Theme/
│   │   ├── ColorSystem.swift        # Semantic system-colour tokens + rich-text colour map
│   │   ├── AccentTheme.swift        # `MedxAccent`, appearance override, `MedxTheme.accent`
│   │   ├── GlassModifier.swift      # MedxSurface, medxCard/medxTile/medxBar, shared controls
│   │   └── Typography.swift         # The two named font shapes worth keeping
│   ├── Components/
│   │   ├── HTMLRichTextView.swift   # HTML renderer: inline images, dark-mode remap, parse cache
│   │   ├── ProgressRingView.swift   # Circular progress indicator
│   │   ├── CountdownWidgetView.swift# Live countdown; long press to edit the exam date
│   │   ├── CachedAsyncImage.swift   # Memory + disk image cache with downsampled decode
│   │   ├── VideoPlayerView.swift    # AVPlayer with PiP, silent resume, offline-first
│   │   ├── MedxOfflineAssetLoader.swift # `medxoffline://` resource loader for downloads
│   │   ├── MedxLogoMark.swift       # The vector mark — splash and icon share its coordinates
│   │   ├── FlashcardDeckView.swift  # Photos-style zoomable flashcard pager
│   │   ├── ModernButton.swift       # Primary action button + BouncyButtonStyle
│   │   └── FloatingTabBar.swift     # TabItem (the five top-level destinations)
│   ├── Views/
│   │   ├── Auth/                    # ProfileSelectView, PasswordPromptView
│   │   ├── Main/MainTabView.swift   # Tab bar / split view + every external presentation
│   │   ├── Home/                    # HomeView, QBankProgressCard, SyllabusTrackerSheet
│   │   ├── QBank/                   # Subject list, chapters, StartSessionSheet,
│   │   │                            # MedxQuestionSearchView, MedxCustomModuleSheet
│   │   ├── Runner/                  # QuizRunnerView, QuestionOptionButton, SittingReviewView
│   │   ├── Tests/                   # TestsListView, TestDetailCard
│   │   ├── Flashcards/              # FlashcardsSubjectListView, FlashcardStudyView
│   │   ├── Videos/                  # VideosBatchListView, VideoSubjectView
│   │   └── Settings/SettingsView.swift
│   └── Resources/
│       ├── Info.plist               # ATS, background modes, Live Activities, URL scheme
│       └── Assets.xcassets/         # App icon (3 appearances), accent, launch background
└── README.md
```

---

## Opening and Running the Project

The sources exist twice on purpose — `MedxElite/` is the Xcode target and
`MedxElite.swiftpm/` is the Swift Playgrounds target. **They must stay byte-identical.**
After any edit, copy the file to its twin and verify:

```bash
diff -rq MedxElite MedxElite.swiftpm
```

Only three differences are expected: `MedxElite.swiftpm/.swiftpm`,
`MedxElite.swiftpm/Package.swift`, and `MedxElite/Resources/Info.plist`.
`project.pbxproj` lists every file explicitly, so a *new* `.swift` file is not compiled
until the pbxproj is hand-edited — prefer adding types to an existing file in the same
folder. `MedxWidgets/` and `Config/` sit outside the mirror; Swift Playgrounds cannot build
an app extension, so the Playgrounds app has the whole app but no widgets.

### Structural checks

There is no Swift toolchain on the maintenance machine, so `.agents/` holds stand-ins for the
compiler diagnostics that matter most. Run them all after any change:

```bash
python .agents/pbxproj_audit.py && python .agents/symbol_audit.py . && python .agents/return_audit.py MedxElite && python .agents/availability_audit.py && python .agents/label_audit.py && python .agents/viewbuilder_audit.py
```

| Script | Stands in for |
|---|---|
| `pbxproj_audit.py` | "Build input file cannot be found" — resolves every file reference and checks each source is compiled exactly once per target |
| `symbol_audit.py` | "cannot find X in scope" |
| `return_audit.py` | a multi-statement `some View` missing its `return` |
| `availability_audit.py` | API newer than the iOS 17.0 deployment target |
| `label_audit.py` | wrong or missing argument labels |
| `viewbuilder_audit.py` | an eleventh child in a `@ViewBuilder` container ("extra argument in call") |
| `balance.py` | unbalanced braces, parens or quotes |
| `make_app_icon.py` | regenerates the app icon from `MedxLogoMark`'s coordinates (`--preview` for a contact sheet) |

### Option A: Open in Xcode
1. Open the folder `medx-elite-ios` in Xcode:
   ```bash
   open medx-elite-ios/MedxElite.xcodeproj
   ```
2. Select target device / Simulator (e.g. **iPhone 15/16 Pro** or **iPad Pro**).
3. Press `Cmd + R` to Build & Run. The `MedxWidgets` extension is embedded automatically;
   pick its scheme to preview a widget in isolation.
4. The App Group `group.quest.srihari.medxelite` must exist on the signing team — without it
   the app still runs, but the widgets fall back to empty placeholder data.

### Option B: Open as a Swift Package
1. Open `medx-elite-ios/Package.swift` in Xcode or Swift Playgrounds.
2. Build and run directly. Widgets and Live Activities are absent in this target.

### Option C: GitHub Actions → SideStore / AltStore

`.github/workflows/build-unsigned-ipa.yml` builds an **unsigned** `MedxElite-unsigned.ipa` on a
macOS runner and uploads it as an artifact (and attaches it to the release on a `v*` tag).
Signing is off on purpose — the sideloader re-signs with your own Apple ID on install. The
workflow uses `-target` rather than `-scheme` because the project ships no shared `.xcscheme`,
and it **fails the build** if `PlugIns/MedxWidgets.appex` is missing, so a broken embed phase
cannot ship quietly.

What works when sideloaded with a **free** Apple ID:

| Feature | Sideloaded with a free account |
|---|---|
| The whole app, offline downloads, search, custom modules | ✅ no entitlement needed |
| Local notifications | ✅ no entitlement needed |
| Live Activities (exam timer, download progress) | ✅ `NSSupportsLiveActivities` is an `Info.plist` key, not an entitlement |
| Spotlight indexing, Siri shortcuts | ✅ no entitlement needed |
| Widgets appear and show the **exam countdown** | ✅ the extension installs; the countdown needs only a date |
| Widgets show **goal / streak / due** | ⚠️ needs the App Group — see below |

App Groups are the one capability the widgets want and a free profile may not grant. Rather than
assume, the app resolves it at runtime: `MedxAppGroup` tries the declared
`group.quest.srihari.medxelite`, then reads the app groups actually listed in the embedded
provisioning profile (a sideloader may rewrite the identifier), and confirms each by asking for a
real container URL — `UserDefaults(suiteName:)` returns a usable-looking object even for a suite
the sandbox will never share, so it proves nothing. If nothing is reachable:

- the app itself is unaffected (it falls back to its own `UserDefaults`),
- the widgets still render a correct countdown and say **"Open MedX Elite to sync your goal and
  streak"** instead of showing zeroes that look like a bad day,
- **Settings ▸ Siri, Spotlight & widgets ▸ Widget data** tells you which state you are in.

Also worth knowing: a free account gives 7-day app expiry (SideStore refreshes it), a limit of 3
sideloaded apps, and 10 App IDs per week — the widget extension is a **second** App ID, so
installing this app consumes two.

---

## Backend Connectivity
- **Firebase Project**: `medx-e9acd`
- **Firestore Collections**:
  - `medx_qbank_subjects`
  - `medx_qbank_modules`
  - `medx_qbank_module_parts`
  - `medx_tests`
  - `medx_test_questions`
  - `medx_flashcard_subjects`
  - `medx_videos`
  - `medx_attempts`
  - `medx_bookmarks`
  - `medx_watch_history`
  - `user_tracker/{uid}`
- **Images CDN**: `https://cdn.jsdelivr.net/gh/cyberromeo/img@main/qbank/`
- **Flashcards CDN**: `https://d2vhwjmp3pf4cn.cloudfront.net`

### Decoding contract

Firestore's REST shape is normalised in `FirestoreService.normalizeFirestoreValue`.
Anything it cannot map — `nullValue`, an unknown value type — becomes `NSNull`, never `""`:
a `String` where a model expects an object is a `typeMismatch`, and because the decode is
wrapped in `try?` that silently dropped the whole document. That is what made the Tests tab
render empty. For the same reason, models decode leniently (`try?` per field,
`decodeLenientArray` for element-wise arrays) and empty collections are never cached.
