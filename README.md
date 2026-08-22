# Medx-elite iOS Native Application

A brand-new native iOS application built in **pure Swift and SwiftUI**, targeting **iOS 17/18+**, connected directly to the **Medx-elite Firebase backend** (`medx-e9acd`) and Arise CDNs.

Designed to Apple's Human Interface Guidelines: flat semantic surfaces, native navigation and toolbars, system materials reserved for chrome that actually floats, Dynamic Type throughout, and full VoiceOver labelling. Materials appear in exactly one place — `medxBar` — and nowhere in content.

---

## Design language

| Rule | Where it lives |
|---|---|
| Content sits on flat, semantic, grouped backgrounds | `MedxSurface`, `medxCard()`, `medxTile()` |
| Materials only for chrome that floats over content | `medxBar()` — bottom action bars |
| Never put an interactive glass effect inside a button label | it swallows the tap on iOS 26; this is what broke the flashcard close button |
| Fonts are native text styles at the point of use | `.headline`, `.subheadline.weight(.semibold)`, `.caption.monospacedDigit()` |
| Colour tokens name *meaning*, never brand | `MedxTheme` — all system colours, so Dark Mode and Increase Contrast work for free |
| One accent for interactive chrome | `Color.accentColor` |

---

## Features

| Feature | Description |
|---|---|
| **Profiles & Authentication** | Graveyard (Mathu) and QuantumGuy (Sri) profile switching with iOS Keychain saved-password fast unlock. |
| **Home Dashboard** | Exam countdown widget, four quick-action shortcuts, Continue-watching resume row, a 7-day activity roll-up, QBank coverage ring, accuracy chart, and the syllabus checklist. |
| **Syllabus Tracker Matrix** | Live 23-subject checklist (Videos, R1, R2, PYQs, Rev, QBank) with optimistic updates and rollback if the Firestore write fails. |
| **Question Bank** | 17,890 questions across 23 subjects and 1,211 modules. Searchable subjects, collapsing chapters, per-module best-score badges, and long-press to start a module directly in either mode. |
| **Interactive Runner** | **Exam Mode** (overall timer, bulk submit, scored review) and **Revision Mode** (60s per question, instant reveal). Native toolbar and bottom action bar, swipe left/right between questions, question navigator. Sittings auto-saved to `medx_attempts`. |
| **Rich question rendering** | Custom HTML renderer: inline `<img>` figures render and zoom full-screen, authored light-mode colours and highlights are re-mapped for Dark Mode, and parses are cached so a 40-question review scrolls at frame rate. |
| **Batch Tests** | Scored and practice papers with a scope filter, Arise prior-attempt stats, and best-score history. |
| **Flashcard Gallery** | 895 high-yield cards from the Arise CloudFront CDN. Contact-sheet grid, Photos-style pager with pinch zoom, swipe from anywhere on the card, and an artwork override (Auto / Phone / Tablet × Portrait / Landscape) plus a quarter-turn rotate for reading landscape cards on a portrait phone. |
| **Video Classroom** | 67 recorded classes by Batch and Subject. Native HLS `AVPlayer` with background audio, PiP, and silent resume. |
| **Offline Downloads** | Per-class HLS downloads with quality choice, pause/resume, and playback with no signal. Watch progress is shared between a download and the streaming copy of the same class, and offline progress is pushed to Firestore on the next sync. |
| **Offline Performance** | Multi-tier caching for documents (`CacheManager`) and images (`MedxImageLoader`, with downsampled decode). |

---

## Project Structure

```
medx-elite-ios/
├── MedxElite.xcodeproj/             # Native Xcode Project
├── Package.swift                    # Swift Package Manifest (iOS 17+)
├── MedxElite/
│   ├── App/
│   │   ├── MedxEliteApp.swift       # App lifecycle & root view router
│   │   └── AppState.swift           # Global reactive app state
│   ├── Models/
│   │   ├── Profile.swift            # Graveyard & QuantumGuy profile definitions
│   │   ├── QBank.swift              # Subjects, chapters, modules, questions, options
│   │   ├── Test.swift               # Batch tests, gradable status, performance stats
│   │   ├── Flashcard.swift          # Flashcard subjects, cards, auto-detected CDN variants
│   │   ├── Video.swift              # Recorded classes, batches, durations, HLS stream URLs
│   │   ├── Attempt.swift            # Exam/revision attempt results & responses
│   │   └── UserTracker.swift        # Syllabus matrix checklist document model
│   ├── Services/
│   │   ├── FirebaseConfig.swift     # Backend API keys, project IDs, and endpoints
│   │   ├── AuthService.swift        # Firebase Auth REST & iOS Keychain store
│   │   ├── FirestoreService.swift   # High-performance Firestore REST client & parser
│   │   ├── HapticManager.swift      # Tactile haptic feedback engine
│   │   └── CacheManager.swift       # On-disk & memory document cache
│   ├── Theme/
│   │   ├── ColorSystem.swift        # Semantic system-colour tokens + rich-text colour map
│   │   ├── GlassModifier.swift      # MedxSurface, medxCard/medxTile/medxBar, shared controls
│   │   └── Typography.swift         # The two named font shapes worth keeping
│   ├── Components/
│   │   ├── HTMLRichTextView.swift   # HTML renderer: inline images, dark-mode colour remap, parse cache
│   │   ├── ProgressRingView.swift   # Circular progress indicator
│   │   ├── CountdownWidgetView.swift# Live countdown to FMGE Jan 9, 2027
│   │   ├── CachedAsyncImage.swift   # Memory + disk image cache with downsampled decode
│   │   ├── VideoPlayerView.swift    # AVPlayer with PiP, silent resume, offline fall-back
│   │   ├── FlashcardDeckView.swift  # Photos-style zoomable flashcard pager
│   │   ├── ModernButton.swift       # Primary action button + BouncyButtonStyle
│   │   └── FloatingTabBar.swift     # TabItem (the five top-level destinations)
│   ├── Views/
│   │   ├── Auth/
│   │   │   ├── ProfileSelectView.swift
│   │   │   └── PasswordPromptView.swift
│   │   ├── Main/
│   │   │   └── MainTabView.swift
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   ├── QBankProgressCard.swift
│   │   │   └── SyllabusTrackerSheet.swift
│   │   ├── QBank/
│   │   │   ├── QBankSubjectListView.swift
│   │   │   ├── QBankChapterView.swift
│   │   │   └── StartSessionSheet.swift
│   │   ├── Runner/
│   │   │   ├── QuizRunnerView.swift
│   │   │   ├── QuestionOptionButton.swift
│   │   │   └── SittingReviewView.swift
│   │   ├── Tests/
│   │   │   ├── TestsListView.swift
│   │   │   └── TestDetailCard.swift
│   │   ├── Flashcards/
│   │   │   ├── FlashcardsSubjectListView.swift
│   │   │   └── FlashcardStudyView.swift
│   │   ├── Videos/
│   │   │   ├── VideosBatchListView.swift
│   │   │   └── VideoSubjectView.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   └── Resources/
│       ├── Info.plist               # App transport security, permissions, orientations
│       └── Assets.xcassets/         # App icon & accent colors
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

Only three differences are expected: `MedxElite.swiftpm/.swiftpm/`,
`MedxElite.swiftpm/Package.swift`, and `MedxElite/Resources/Info.plist`.
`project.pbxproj` lists every file explicitly, so a *new* `.swift` file is not compiled
until the pbxproj is hand-edited — prefer adding types to an existing file in the same
folder.

### Option A: Open in Xcode
1. Open the folder `medx-elite-ios` in Xcode:
   ```bash
   open medx-elite-ios/MedxElite.xcodeproj
   ```
2. Select target device / Simulator (e.g. **iPhone 15/16 Pro** or **iPad Pro**).
3. Press `Cmd + R` to Build & Run.

### Option B: Open as a Swift Package
1. Open `medx-elite-ios/Package.swift` in Xcode or Swift Playgrounds.
2. Build and run directly.

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
