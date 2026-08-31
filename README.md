# Medx-elite iOS Native Application

A native iOS application built in **pure Swift and SwiftUI**, targeting **iOS 17+**, connected directly to the **Medx-elite Firebase backend** (`medx-e9acd`) and Arise CDNs. It is the same backend the `Medx elite pwa` sibling runs on, and it now carries the same feature set: two question banks, the Marrow FMGE test series, the two-player Faceoff, shared custom modules and the raw VOD bucket.

Designed to Apple's Human Interface Guidelines — native navigation and toolbars, Dynamic Type throughout, full VoiceOver labelling, system materials reserved for chrome that actually floats — with the PWA's visual identity layered on top: a per-destination candy accent, the eyebrow / title / lead page header, and pill chips. **Icons are SF Symbols**; the 62 Fluent Emoji stickers are kept for the places where the picture is the content rather than the label — a profile mark, an empty state, the trophy at the end of a duel. Materials appear in exactly one place, `medxBar`, and nowhere in content. Where the running OS is iOS 26 the app takes the platform's own Liquid Glass chrome — a minimising tab bar, soft scroll edges, glass button styles — each behind an `#available` check, because the deployment target is iOS 17. The one deliberate exception to the flat-surface rule is the brand itself: the app icon and the launch screen get a layered glass treatment, because an icon is chrome *about* the app rather than content *within* it.

Five top-level destinations: **Home · QBank · Tests · Classes · Library**. Cards live in Library, which is a grid of eleven doors rather than a list. Two targets ship from this project: the app, and a `MedxWidgets` extension carrying two Home Screen widgets, three Lock Screen accessories and **three** Live Activities.

---

## Design language

| Rule | Where it lives |
|---|---|
| Content sits on flat, semantic, grouped backgrounds | `MedxSurface`, `medxCard()`, `medxTile()` |
| Materials only for chrome that floats over content | `medxBar()` — bottom action bars |
| Glass is allowed on the **app icon and the splash screen only** | `MedxLogoMark`, `.agents/make_app_icon.py` |
| Never put an interactive glass effect inside a button label | it swallows the tap on iOS 26; this is what broke the flashcard close button |
| Fonts are native text styles at the point of use | `.headline`, `.subheadline.weight(.semibold)`, `.caption.monospacedDigit()` |
| **Semantic** colour names *meaning*, never brand | `MedxTheme` — all system colours, so Dark Mode and Increase Contrast work for free |
| **Wayfinding** colour is assigned per destination, never decorative | `MedxCandy` + `MedxSection` — eight dynamic hue pairs from the PWA's `tokens.css`, each with a soft companion |
| A glyph on a candy soft wash is mixed 52% toward the label colour | `MedxCandy.onSoft` — measured, not guessed: butter-on-butter was 1.25:1 |
| A label on a **solid** candy fill is a fixed near-black, never `.systemBackground` | `MedxCandy.onSolid`, `MedxFilledButtonStyle` — every hue is light in *both* appearances |
| One accent for interactive chrome, chosen in Settings | `MedxTheme.accent` — **not** `Color.accentColor`, which reads the asset catalogue and does not follow `.tint()` |
| Scrolling is plain scrolling — no per-card entry transition | there is no `scrollTransition` anywhere; the reveal that used to fade and lift each card was removed because it read as content popping in |
| An icon is an SF Symbol in the section's hue, in the system's rounded square | `MedxSymbolMark` — Settings, Shortcuts and Mail all draw a list this way |
| A sticker is an illustration, never an icon, and is always hidden from VoiceOver | `MedxSticker` — `NSDataAsset`-backed WebP, `.accessibilityHidden(true)`, no tilt under Reduce Motion |
| iOS 26 chrome degrades to the iOS 17 equivalent, never to a stub | `medxTabBarMinimize()`, `medxScrollEdge()`, `medxBorderedButton()`, `medxFilledButton()` in `Theme/GlassModifier.swift` |

---

## Features

| Feature | Description |
|---|---|
| **Profiles & Authentication** | Graveyard (Mathu) and QuantumGuy (Sri) profile switching with iOS Keychain saved-password fast unlock. A second, fire-and-forget sign-in to the Firebase iOS SDK backs Faceoff's snapshot listeners; failing it costs the duel its listeners and nothing else. |
| **Home Dashboard** | A live Faceoff invite card above everything else when the other one has dealt a game, exam countdown (editable by long press), today's goal ring and streak, six quick actions, Continue-watching resume, a 7-day roll-up, QBank coverage ring, accuracy chart, and the syllabus checklist. |
| **Syllabus Tracker Matrix** | Live 23-subject checklist (Videos, R1, R2, PYQs, Rev, QBank) with optimistic updates and rollback if the Firestore write fails. |
| **Two question banks** | An Arise / Marrow segmented control, as in the PWA. **Arise**: 17,890 questions across 23 subjects and 1,211 modules. **Marrow FMGE**: 14,577 questions across 20 subjects and 960 modules. Searchable subjects with sticker marks and a bank tag, collapsing chapters, per-module best-score badges, long-press to start a module in either mode. |
| **Marrow FMGE test series** | The Tests tab: 352 keyed papers in three groups (GTs / Mini tests / Subject tests) with counts, month sections newest-first, a per-paper best-score bar, and a mode picker that says what it is about to do. A grand paper over 50 questions is sat in **timed blocks of 50** with a between-blocks summary and no way back. |
| **Batch papers** | The four Arise `medx_tests` papers, moved into Library: scored and practice split, a scope filter, prior-attempt stats and best-score history. |
| **Faceoff** | Two players, one question, one minute. Deal from a custom module or any series paper, 10 / 20 / 30 / all questions, a 3·2·1, a points curve that rewards speed, a versus bar sized by score, a reveal spelling out `40 + 28 = 68`, and a round-by-round scoreboard. Each side files its own `medx_attempts` row, so a duel folds into accuracy, streak and the daily goal. |
| **Saved custom modules** | Papers either of you builds, shared: pick modules across both banks with one toggle primitive at module / chapter / subject / whole-search scope, cap at 20 / 40 / 100 or none, shuffle, then run, edit or delete — from either device. Local-first, so the list is instant and works offline; the Firestore mirror is allowed to fail and the screen says so. |
| **Quick sitting** | The other kind of custom module, kept: filter the question index by subject, scope and length — wrong, unattempted or bookmarked — and go. |
| **Interactive Runner** | **Exam Mode** (overall or per-block timer, bulk submit, scored review, Lock Screen Live Activity) and **Revision Mode** (60s per question, instant reveal). Native toolbar and bottom action bar, swipe left/right between questions, double-tap the stem to bookmark, question navigator. The stem's eyebrow carries the palette of whichever screen the paper was opened from. Sittings auto-saved to `medx_attempts`. |
| **Rich question rendering** | Custom HTML renderer: inline `<img>` figures render and zoom full-screen, authored light-mode colours and highlights are re-mapped for Dark Mode, and parses are cached so a 40-question review scrolls at frame rate. |
| **Flashcard Gallery** | 895 high-yield cards from the Arise CloudFront CDN. Contact-sheet grid, Photos-style pager with pinch zoom, swipe from anywhere on the card, and an artwork override (Auto / Phone / Tablet × Portrait / Landscape) plus a quarter-turn rotate for reading landscape cards on a portrait phone. |
| **Video Classroom** | 67 recorded classes by Batch and Subject. Native HLS `AVPlayer` with background audio, PiP, and silent resume. |
| **The VOD feed** | Every recording in the raw ARISE bucket (~2,900 documents), newest first: a watermark card, day-header sections, a CC filter, `new` pills against the last-seen watermark, and paging 48 at a time — auto-paged three screens deep, then by tap. Every row is **downloadable for offline**: a bucket item is an HLS stream like any class, so `asRecordedVideo` hands it straight to `VideoDownloadStore` and it lands in Downloads beside them, with the same quality menu, the same pause/resume and the same shared watch progress. |
| **New-drop notifications** | One `medx_vod/_meta` read per check, on every foreground and opportunistically every two hours in the background, tells you when something lands: *"4 new recordings in the VOD bucket — Class 7F2A11 and 3 more."* |
| **Offline Downloads** | Per-class HLS downloads with quality choice, pause/resume from **inside the Live Activity**, and playback with no signal through a custom `medxoffline://` scheme rather than a local HTTP server. Watch progress is shared between a download and the streaming copy of the same class, and offline progress is pushed to Firestore on the next sync. |
| **Offline Performance** | Multi-tier caching for documents (`CacheManager`) and images (`MedxImageLoader`, with downsampled decode). |

---

## System integration

| Feature | Description |
|---|---|
| **Home Screen widgets** | `Exam countdown` (small / medium) and `Daily goal & streak` (small / medium), both reading one shared `MedxStudySnapshot`. |
| **Lock Screen widgets** | The countdown as `accessoryCircular`, `accessoryRectangular` and `accessoryInline`. |
| **Live Activities** | Three, sharing one chrome vocabulary (`MedxActivityChrome`: ring, pace bar, versus bar). **Exam sitting** — a ring with the clock in its middle, the block chip, right/wrong when the mode reveals it, and a pace bar showing answered against elapsed. **Download** — ring, segments, derived ETA and **Pause / Resume / Cancel buttons** in the activity itself. **Faceoff** — the versus bar, the round clock and "Question 7 of 20", so the score is glanceable from the Lock Screen mid-duel. Every clock is handed over as an end date, so the *system* ticks it and the app pushes only when a count changes. |
| **Local notifications** | Four kinds: a daily question reminder at a chosen hour, a streak-protection nudge at 21:00 only while the streak is actually at risk, a spaced-revision digest at 08:00 only when something is due, and a new-VOD-drop alert. The first three are rebuilt on every foreground so the wording carries live numbers. |
| **Background refresh** | One `BGAppRefreshTask` (`quest.srihari.medxelite.vodcheck`), re-armed on every background transition with a two-hour floor, costing **one document read** per run. iOS is free to never run it, so the foreground check is the guarantee and Settings says exactly that rather than implying push. |
| **Spotlight** | Bookmarks and all 2,171 modules from both banks indexed with `CoreSpotlight`, the bank named in each description so two same-titled subjects are distinguishable; a module result opens its mode picker. One switch in Settings deletes the whole index. |
| **App Intents / Siri** | "Start today's revision", "Exam countdown" (answers without launching) and "Search questions", donated as `AppShortcut`s. Separately, `MedxSharedIntents` holds the three iOS 17 `LiveActivityIntent`s the download activity's buttons run. |
| **Question search** | Full-text search over the indexed 32,467 questions across both banks, with filters for bank, subject, image-based, attempted / wrong / unattempted and bookmarked. Results can be turned straight into a sitting. |
| **Deep links** | `medxelite://` for home, qbank, tests, cards, library, classes, vod, custom, search, faceoff, and `faceoff/<gameId>` straight into a room. |
| **iPad** | `NavigationSplitView` at regular width with three sidebar sections (Study / Play / Library), `TabView` on iPhone. |
| **Theming** | Eight system accents and a light/dark/automatic override in Settings, carried through to the widgets and Live Activities. The section palette is additive and does not follow the accent. |
| **Spaced revision** | A 1/3/7/21/45-day schedule per module, driving the 08:00 digest notification and the "Start today's revision" Siri shortcut. It has no card on Home — the schedule is a nudge, not a thing to be reminded of on every launch. |

### Faceoff, and why it needs the SDK

A duel is the one feature where both devices must see each other's move inside a second, and
Firestore REST has no equivalent of `onSnapshot`. So this is the only part of the app that touches
the **Firebase iOS SDK** — everything else still runs on the hand-rolled REST client.

That is wired to be optional rather than load-bearing:

- Every SDK symbol sits behind `#if canImport(FirebaseFirestore)`, so both copies of every file
  stay byte-identical and the Swift Playgrounds target — which cannot build firebase-ios-sdk —
  still compiles.
- `MedxDuelTransport` is a protocol with two implementations. `MedxFirestoreDuelTransport` uses
  real `addSnapshotListener` streams; `MedxDuelRestTransport` polls at a rate that follows the
  derived phase (3s in the lobby, 1s once a round is open, immediately after every local write)
  and fetches the game plus both player documents in **one** `documents:batchGet`, which it can do
  because player document ids are deterministic — `gameId__uid`.
- `MedxDuelTransportFactory.make()` picks the SDK when `MedxFirebaseBridge.isReady`, and the poller
  otherwise. A failed `FirebaseApp.configure` or SDK sign-in therefore degrades to a working
  Faceoff rather than to no Faceoff. **Settings ▸ Diagnostics ▸ Faceoff transport** says which one
  is live.

#### The one thing that has to be filled in: `FirebaseConfig.iosAppId`

`FirebaseOptions` is built in code, so there is no `GoogleService-Info.plist` to fall out of step
with `FirebaseConfig.swift`. The catch is that a Firebase app ID names one *registration* inside a
project, not the project, and `+[FIRApp validateAppIDFormat:withVersion:]` requires its platform
segment to be literally `ios`. `FirebaseConfig.appId` is the PWA's `1:…:web:…` one and the SDK
**refuses it by raising an `NSException`** — which Swift cannot catch, so it terminates the app
during launch rather than failing softly.

`MedxFirebaseBridge.isAcceptableAppId` therefore checks the format *before* handing it over, and an
unusable value is a Diagnostics line instead of a crash. `iosAppId` ships empty; to fill it, in the
Firebase console for `medx-e9acd` go to Project settings ▸ Your apps ▸ Add app ▸ iOS with bundle id
`quest.srihari.medxelite`, and paste the `1:300960747898:ios:<hex>` it gives back. Nothing else
changes — no plist download, no rules change. Until then Faceoff runs on the REST poller, which is
the same feature at a slightly worse latency, and the rest of the app never touched the SDK anyway.

Three write rules are carried over from the PWA unchanged, because they are what the deployed
rules on `medx-e9acd` actually take (the repo's `firestore.rules` is stale and does not describe
the live backend):

1. **Nobody writes anybody else's document.** The host owns the game document; each player owns
   exactly one player document and that is the only place they may write a move. The guest joining
   *is* the readiness signal; the host is what flips the game to live.
2. **No composite indexes.** Every query is a single equality filter and sorting is in memory;
   `listMyDuels` is two queries merged locally.
3. **No read before auth resolves**, or Firestore reports a permission error that is really a race.

Everything the room draws is *derived* from the three documents — phase, clock, answers, tally and
scores all fall out of them, so the two screens turn over on the same input rather than one waiting
on a referee. Nothing is written to reach a phase. The three writes that do exist each guard a
specific failure: a client whose clock ran out writes its **own** timeout row; only the host opens
the next round, claiming the ref before the write and releasing it if it fails; and the log row
goes in with `arrayUnion`, so a redelivered snapshot is a no-op rather than a duplicate.

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

Question bodies live in 2,171 Firestore module documents — 1,211 Arise and 960 Marrow — that are
normally only fetched when a module is opened, so searching all 32,467 questions means having
pulled them down once. That is an **opt-in build** in Settings with a progress bar, resumable
across launches, and it also warms `FirestoreService`'s module cache — so building the index makes
those modules playable offline too. Search works on whatever is indexed so far and says so.

The index covers **both banks**, keyed on `MedxBankSubject.id` as a string, and so does Spotlight.
Search offers a bank filter alongside the subject one, and every result row carries a bank chip,
because both banks have an Anatomy, a Pathology and a Medicine.

**Why the entries carry a composite key.** Arise question ids run 1…84,505 and Marrow's
39,687…212,931, and **2,405 of them collide**. A `medx_attempts` row records only
`questionId` — `QuestionResponse` has no module field and both clients write that collection, so
one cannot be added retroactively — which means a bare id cannot say which bank an answer belongs
to. `MedxAnswerHistory` therefore holds each fact twice: the plain `Set<Int>`, and a
`moduleId#questionId` set built from attempts whose `sourceId` is a real module (`qb_…` / `mw_…`,
not a synthetic `custom-…` / `search-…`). `MedxQuestionIndexStore.resolve` prefers the composite,
trusts the bare id only where the index shows it is unique to one bank, and otherwise answers no.
Without that, one wrong Arise answer would put a red cross on a Marrow question nobody had opened.

`MedxIndexFile.version` gates the on-disk file. Version 2 is this two-bank layout; a file from the
unversioned Arise-only one is deleted on launch rather than left to fail decoding forever, so the
first run after this change starts the index from empty.

### Two subject models, on purpose

`QBankSubject.subjectId` and `QBankChapter.id` are `Int`, and Marrow's ids are strings
(`mw_618a04d13dcbce9c59c6bb59`). Rather than widen those two types — the batch-paper screens and
several `[Int: …]` tallies read them — `MedxBankSubject` / `MedxBankChapter` were **added**
alongside them: `String` ids, a `bank` tag, and `init(arise:)` to adapt the Arise tree in. Every
new screen reads those, including the question index and Spotlight. `QBankModuleSummary` is reused
as-is — module ids were already strings, and Marrow modules sit in `medx_qbank_modules` in the
identical shape, spillover included.


---

## Project Structure

```
medx-elite-ios/
├── MedxElite.xcodeproj/             # Native Xcode project: MedxElite + MedxWidgets targets
│                                    #   + the firebase-ios-sdk package reference
├── Package.swift                    # Swift Package Manifest (iOS 17+) — no Firebase package
├── Config/
│   ├── MedxElite.entitlements       # App Group, shared with the widget extension
│   └── MedxWidgets.entitlements
├── MedxWidgets/                     # Widget extension — Xcode target only, not mirrored
│   ├── MedxWidgetsBundle.swift      # 2 Home Screen + 3 Lock Screen widgets + 3 Live Activities
│   └── Info.plist
├── MedxElite/
│   ├── App/
│   │   ├── MedxEliteApp.swift       # Lifecycle, deep links, BG task registration, splash
│   │   ├── AppState.swift           # Global state + `MedxRoute`, the one external-entry map
│   │   └── MedxSplashView.swift     # Launch animation over the live root
│   ├── Models/
│   │   ├── Profile.swift            # Graveyard & QuantumGuy profile definitions
│   │   ├── QBank.swift              # Arise tree + `MedxBank`/`MedxBankSubject` for both banks
│   │   ├── Test.swift               # Arise batch papers, gradable status, performance stats
│   │   ├── Series.swift             # Marrow FMGE series index + `MedxSeriesRules` (blocks, months)
│   │   ├── CustomModule.swift       # Shared saved modules + the reconcile rules
│   │   ├── Duel.swift               # Faceoff game, players, rounds, deck, log rows
│   │   ├── Vod.swift                # Raw bucket items, `rec<hex>` display rules, `_meta`
│   │   ├── Flashcard.swift          # Flashcard subjects, cards, auto-detected CDN variants
│   │   ├── Video.swift              # Recorded classes, batches, durations, HLS stream URLs
│   │   ├── Attempt.swift            # Attempts, responses, sections, `RunnerPayload`, kinds
│   │   └── UserTracker.swift        # Syllabus matrix checklist document model
│   ├── Services/
│   │   ├── FirebaseConfig.swift     # Backend API keys, project IDs, and endpoints
│   │   ├── AuthService.swift        # Firebase Auth REST & Keychain (+ the SDK sign-in)
│   │   ├── MedxFirebaseBridge.swift # `FirebaseApp.configure` from code; `isReady`, `status`
│   │   ├── FirestoreService.swift   # High-performance Firestore REST client & parser
│   │   ├── MedxDuelRules.swift      # Pure port of `duelRules.js` — Foundation only
│   │   ├── MedxDuelTransport.swift  # The protocol, paths and codec
│   │   ├── MedxDuelRestTransport.swift    # Phase-driven poller (Playgrounds, SDK fallback)
│   │   ├── MedxFirestoreDuelTransport.swift # Real snapshot listeners, behind `canImport`
│   │   ├── MedxDuelRoom.swift       # The room + `MedxLobbyWatcher` + the transport factory
│   │   ├── MedxCustomModuleStore.swift    # Local-first store, mirror, reconcile, run assembly
│   │   ├── MedxVodWatcher.swift     # `_meta` watermark check, foreground + `BGAppRefreshTask`
│   │   ├── HapticManager.swift      # Tactile haptic feedback engine
│   │   ├── CacheManager.swift       # On-disk & memory document cache
│   │   ├── HLSProxyServer.swift     # Live-stream header proxy + `VideoDownloadStore`
│   │   ├── MedxSharedState.swift    # App Group snapshot + ActivityAttributes (both targets)
│   │   ├── MedxActivityChrome.swift # Ring, pace bar, versus bar (both targets)
│   │   ├── MedxSharedIntents.swift  # The three download `LiveActivityIntent`s (both targets)
│   │   ├── MedxStudyStatsStore.swift# Streak, goal, spaced revision + `MedxLiveActivityController`
│   │   ├── MedxNotificationManager.swift # The four reminder kinds
│   │   ├── MedxSpotlightIndexer.swift    # CoreSpotlight index for bookmarks and modules
│   │   ├── MedxAppIntents.swift     # Siri shortcuts (app target only)
│   │   └── MedxQuestionIndexStore.swift  # The opt-in full-text index
│   ├── Theme/
│   │   ├── ColorSystem.swift        # Semantic system-colour tokens + rich-text colour map
│   │   ├── MedxSections.swift       # `MedxCandy`, `MedxSection`, duel colours, kind hues
│   │   ├── AccentTheme.swift        # `MedxAccent`, appearance override, `MedxTheme.accent`
│   │   ├── GlassModifier.swift      # MedxSurface, medxCard/medxTile/medxBar, shared controls
│   │   └── Typography.swift         # The two named font shapes worth keeping
│   ├── Components/
│   │   ├── MedxSticker.swift        # WebP sticker loader + the 23 subject-art rules
│   │   ├── MedxPageHeader.swift     # Page header, `MedxSegmented`, `MedxPill`, `MedxRuleHeader`
│   │   ├── HTMLRichTextView.swift   # HTML renderer: inline images, dark-mode remap, parse cache
│   │   ├── ProgressRingView.swift   # Circular progress indicator
│   │   ├── CountdownWidgetView.swift# Live countdown; long press to edit the exam date
│   │   ├── CachedAsyncImage.swift   # Memory + disk image cache with downsampled decode
│   │   ├── VideoPlayerView.swift    # AVPlayer with PiP, silent resume, offline-first
│   │   ├── MedxOfflineAssetLoader.swift # `medxoffline://` resource loader for downloads
│   │   ├── MedxLogoMark.swift       # The vector mark — splash and icon share its coordinates
│   │   ├── FlashcardDeckView.swift  # Photos-style zoomable flashcard pager
│   │   ├── ModernButton.swift       # Primary button, BouncyButtonStyle, MedxFilledButtonStyle
│   │   └── FloatingTabBar.swift     # TabItem — Home · QBank · Tests · Classes · Library
│   ├── Views/
│   │   ├── Auth/                    # ProfileSelectView, PasswordPromptView
│   │   ├── Main/MainTabView.swift   # Tab bar / split view + every external presentation
│   │   ├── Home/                    # HomeView, QBankProgressCard, SyllabusTrackerSheet
│   │   ├── QBank/                   # Subject list (both banks), chapters, StartSessionSheet,
│   │   │                            # MedxQuestionSearchView, MedxCustomModuleSheet
│   │   ├── Runner/                  # QuizRunnerView (+ blocks), QuestionOptionButton,
│   │   │                            # SittingReviewView
│   │   ├── Tests/                   # TestsListView (Marrow series), BatchPapersView,
│   │   │                            # TestDetailCard
│   │   ├── Faceoff/                 # FaceoffLobbyView, DuelRoomView, DuelResultView
│   │   ├── Custom/                  # CustomModulesView, ModuleBuilderSheet
│   │   ├── Library/LibraryView.swift# The hub: an eleven-tile grid, two up / four on iPad
│   │   ├── Flashcards/              # FlashcardsSubjectListView, FlashcardStudyView
│   │   ├── Videos/                  # VideosBatchListView, VideoSubjectView, VodFeedView
│   │   └── Settings/SettingsView.swift
│   └── Resources/
│       ├── Info.plist               # ATS, background modes + BG task ids, Live Activities, scheme
│       └── Assets.xcassets/         # App icon (3 appearances), accent, launch background,
│                                    #   Stickers/ — 62 WebP `NSDataAsset` data sets
└── README.md
```

---

## Opening and Running the Project

The sources exist twice on purpose — `MedxElite/` is the Xcode target and
`MedxElite.swiftpm/` is the Swift Playgrounds target. **They must stay byte-identical.**
After any edit, mirror and verify:

```bash
python .agents/mirror.py && python .agents/mirror.py --check && diff -rq MedxElite MedxElite.swiftpm
```

Only three differences are expected: `MedxElite.swiftpm/.swiftpm`,
`MedxElite.swiftpm/Package.swift`, and `MedxElite/Resources/Info.plist`.
`project.pbxproj` lists every file explicitly, so a *new* `.swift` file is not compiled until it is
registered — use `.agents/add_sources.py` rather than editing four places by hand:

```bash
python .agents/add_sources.py MedxElite/Views/Faceoff/DuelRoomView.swift
python .agents/add_sources.py MedxElite/Services/MedxActivityChrome.swift --targets MedxElite,MedxWidgets
```

`MedxWidgets/` and `Config/` sit outside the mirror; Swift Playgrounds cannot build an app
extension, so the Playgrounds app has the whole app but no widgets — **and no Firebase**, which is
why every SDK touch is behind `#if canImport(FirebaseFirestore)` and Faceoff falls back to its REST
poller there.

### Structural checks

There is no Swift toolchain on the maintenance machine, so `.agents/` holds stand-ins for the
compiler diagnostics that matter most. Run them all after any change:

```bash
python .agents/pbxproj_audit.py && python .agents/symbol_audit.py . && python .agents/return_audit.py MedxElite && python .agents/availability_audit.py && python .agents/label_audit.py && python .agents/viewbuilder_audit.py && python .agents/balance.py $(find MedxElite MedxWidgets -name '*.swift')
```

| Script | Stands in for |
|---|---|
| `pbxproj_audit.py` | "Build input file cannot be found" and "no such module" — resolves every file reference, checks each source is compiled exactly once per target, and checks each Swift package product resolves to a declared package and is linked exactly once from the Frameworks phase |
| `symbol_audit.py` | "cannot find X in scope" — skips code inside `#if canImport(...)`, since those symbols cannot resolve on a machine without the package |
| `return_audit.py` | a multi-statement `some View` missing its `return` |
| `availability_audit.py` | API newer than the iOS 17.0 deployment target — `LiveActivityIntent` and `Button(intent:)` sit exactly on it |
| `label_audit.py` | wrong or missing argument labels |
| `viewbuilder_audit.py` | an eleventh child in a `@ViewBuilder` container ("extra argument in call") |
| `balance.py` | unbalanced braces, parens or quotes — takes **file paths**, not a directory |
| `mirror.py` | keeps `MedxElite.swiftpm/` identical to `MedxElite/`; `--check` only reports |
| `add_sources.py` | registers a source in `project.pbxproj` (build file, file reference, group, sources phase); idempotent |
| `make_app_icon.py` | regenerates the app icon from `MedxLogoMark`'s coordinates (`--preview` for a contact sheet) |

None of this is a compiler. The only real build is Option C below.

### Option A: Open in Xcode
1. Open the folder `medx-elite-ios` in Xcode:
   ```bash
   open medx-elite-ios/MedxElite.xcodeproj
   ```
2. Let it resolve **firebase-ios-sdk** on first open — `File ▸ Packages ▸ Resolve Package Versions`
   if it does not start on its own. This is the one dependency in the project; Firestore's C++ core
   builds from source, so the first build is slow and later ones are cached.
3. Select target device / Simulator (e.g. **iPhone 15/16 Pro** or **iPad Pro**).
4. Press `Cmd + R` to Build & Run. The `MedxWidgets` extension is embedded automatically;
   pick its scheme to preview a widget in isolation.
5. The App Group `group.quest.srihari.medxelite` must exist on the signing team — without it
   the app still runs, but the widgets fall back to empty placeholder data.

### Option B: Open as a Swift Package
1. Open `medx-elite-ios/Package.swift` in Xcode or Swift Playgrounds.
2. Build and run directly. Widgets and Live Activities are absent in this target, and so is the
   Firebase SDK — Faceoff runs on its REST poller instead of snapshot listeners.

### Option C: GitHub Actions → SideStore / AltStore

`.github/workflows/build-unsigned-ipa.yml` builds an **unsigned** `MedxElite-unsigned.ipa` on a
macOS runner and uploads it as an artifact (and attaches it to the release on a `v*` tag).
Signing is off on purpose — the sideloader re-signs with your own Apple ID on install. The
workflow uses `-target` rather than `-scheme` because the project ships no shared `.xcscheme`,
and it **fails the build** if `PlugIns/MedxWidgets.appex` is missing, so a broken embed phase
cannot ship quietly.

It is also **the only real compiler in this pipeline**, and the step most likely to break is
`Resolve Swift package dependencies`: it is split out from the build for exactly that reason, so a
firebase-ios-sdk problem reads as a resolution failure rather than as a compile error 200 lines
deep. `Package.resolved` is deliberately not committed — it would need exact commit hashes for
firebase-ios-sdk and its transitive dependencies, and a hand-written one with wrong hashes breaks
the build rather than pinning it. The `upToNextMajorVersion` requirement in `project.pbxproj` is the
pin; the runner's cache is what keeps resolution stable between runs.

What works when sideloaded with a **free** Apple ID:

| Feature | Sideloaded with a free account |
|---|---|
| The whole app, offline downloads, search, custom modules | ✅ no entitlement needed |
| Local notifications, including the VOD-drop alert | ✅ no entitlement needed |
| Background refresh for the VOD check | ✅ `UIBackgroundModes: fetch` + `BGTaskSchedulerPermittedIdentifiers` are `Info.plist` keys, not entitlements |
| Faceoff | ✅ the Firebase SDK needs no entitlement; if its sign-in fails the duel polls instead |
| Live Activities (exam timer, download progress, Faceoff score) | ✅ `NSSupportsLiveActivities` is an `Info.plist` key, not an entitlement |
| Live Activity buttons (pause / resume / cancel a download) | ✅ `LiveActivityIntent`, iOS 17+ |
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
- **Firebase Project**: `medx-e9acd`, reached over the Firestore REST API everywhere except
  Faceoff, which uses the Firebase iOS SDK for snapshot listeners.
- **Firestore Collections**:

  | Path | Access | Used by |
  |---|---|---|
  | `medx_qbank_subjects` | read | QBank, the question index, Spotlight |
  | `medx_meta/qbank_fmge` | read | QBank's Marrow tab, the module builder |
  | `medx_qbank_modules` | read | both banks — Marrow modules are the same shape |
  | `medx_qbank_module_parts` | read | module spillover |
  | `medx_meta/series_fmge` | read | Tests, the Faceoff host sheet |
  | `medx_tests` | read | Batch papers |
  | `medx_test_questions` | read | Batch papers **and** Marrow series papers |
  | `medx_custom_modules` | read all, write own, delete any | Custom modules |
  | `medx_duels/{id}` + `/deck/{part}` | host writes, both read | Faceoff |
  | `medx_duel_players/{gameId}__{uid}` | each writes only their own | Faceoff |
  | `medx_vod` (orderBy `uploadedAt`) | read, paged 48 at a time | the VOD feed |
  | `medx_vod/_meta` | read | the drop watcher — one read per check |
  | `medx_flashcard_subjects` | read | Cards |
  | `medx_videos` | read | Classes |
  | `medx_attempts` | read + write | every sitting, including duels |
  | `medx_bookmarks` | read + write | Bookmarks |
  | `medx_watch_history` | read + write | resume, Continue watching |
  | `user_tracker/{uid}` | read + write | the syllabus matrix |

  Nothing here is a collection the PWA is not already using, so no rules change should be needed —
  but the repo's `firestore.rules` is stale and does not describe the deployed backend, so each of
  the Faceoff and custom-module paths is worth confirming on device rather than assuming.
- **Images CDN**: `https://cdn.jsdelivr.net/gh/cyberromeo/img@main/qbank/`
- **Flashcards CDN**: `https://d2vhwjmp3pf4cn.cloudfront.net`

### Decoding contract

Firestore's REST shape is normalised in `FirestoreService.normalizeFirestoreValue`.
Anything it cannot map — `nullValue`, an unknown value type — becomes `NSNull`, never `""`:
a `String` where a model expects an object is a `typeMismatch`, and because the decode is
wrapped in `try?` that silently dropped the whole document. That is what made the Tests tab
render empty. For the same reason, models decode leniently (`try?` per field,
`decodeLenientArray` for element-wise arrays) and empty collections are never cached.

---

## First run on device

Nothing above is a compiler and nothing above talks to the live backend, so the order below matters
— each step depends on the one before it.

1. **Sign in as each profile.** Check **Settings ▸ Diagnostics ▸ Faceoff transport**. With
   `FirebaseConfig.iosAppId` still empty it reads *No iOS app ID in FirebaseConfig — Faceoff polls
   instead*, and everything except the duel's latency should be identical; that is the same state a
   failed SDK sign-in leaves. Once the id is filled in it should read *Signed in as …*.
2. **QBank.** The Marrow tab lists 20 subjects; open an `mw_` module and run a sitting in both modes.
3. **The question index.** Settings ▸ Question search says 2,171 modules, not 1,211. Build it — an
   index from before the two-bank layout is deleted on launch, so this starts from empty — then
   search a stem you know is Marrow's and check the result carries a Marrow chip.
4. **Tests.** Three groups with counts; open a grand paper and confirm it runs as `3 × 50` with
   separate clocks, a between-blocks summary, and no way back.
5. **Custom modules.** Build one on one device, run it on the other, delete it from the second, and
   confirm it does not resurrect on the first. A refused cross-user delete should say so rather than
   pretending.
6. **Faceoff on two devices.** Deal, join, play three questions, background the host mid-round and
   confirm the guest is *told* rather than left hanging, then finish and check both attempt rows
   landed and moved the daily goal.
7. **VOD feed.** Page past three screens and confirm auto-paging stops. Then
   **Settings ▸ Diagnostics ▸ Forget the VOD watermark** and confirm the foreground check posts a
   notification.
8. **Live Activities.** Start an exam sitting and a download; check the Lock Screen and the Dynamic
   Island, press Pause in the download activity, and confirm nothing is left stranded after leaving
   the runner by every route.
