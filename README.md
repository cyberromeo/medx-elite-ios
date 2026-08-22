# Medx-elite iOS Native Application

A brand-new native iOS application built in **pure Swift and SwiftUI**, targeting **iOS 17/18+**, connected directly to the **Medx-elite Firebase backend** (`medx-e9acd`) and Arise CDNs.

Designed with a reimagined iOS aesthetic: fluid glassmorphism, dynamic lighting & ambient aura glow, custom haptics, native HLS AVPlayer classroom, an immersive flashcard gallery, and a responsive quiz runner for Exam and Revision modes.

---

## Features

| Feature | Description |
|---|---|
| **Profiles & Authentication** | Graveyard (Mathu) and QuantumGuy (Sri) profile switching with iOS Keychain saved password fast-tap unlock. |
| **Home Dashboard** | Countdown banner to FMGE (9 Jan 2027), performance analytics, QBank coverage ring, and syllabus progress. |
| **Syllabus Tracker Matrix** | Live 23-subject checklist (Videos, R1, R2, PYQs, Rev, QBank) with real-time optimistic updates and Firestore syncing. |
| **Question Bank** | 17,890 questions across 23 subjects and 1,211 modules. Searchable subject list, chapter accordion, and module attempt badges. |
| **Interactive Runner** | **Exam Mode** (overall timer, bulk submit, scored review) and **Revision Mode** (60s timer per question, instant answer feedback & explanations). Sittings auto-saved to `medx_attempts`. |
| **Batch Tests** | Scored tests (Psychiatry Online Dec26) and practice tests with Arise prior attempt stats and scoring breakdown. |
| **Flashcard Gallery** | 895 high-yield cards served from Arise CloudFront CDN. Preview-thumbnail subject grid, searchable contact sheet, and a Photos-style full-screen viewer with pinch-zoom. The Mobile/Tablet × Portrait/Landscape artwork variant is auto-detected from the device and window size — no picker. |
| **Video Classroom** | 67 recorded classes categorized by Batch and Subject. Native HLS `AVPlayer` with background audio, speed controls (0.75x–2.0x), and Picture-in-Picture (PiP). |
| **Offline Performance** | High-performance multi-tier caching (`CacheManager`) for instant offline question module loading. |

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
│   │   ├── ColorSystem.swift        # Medx-elite color tokens & gradients
│   │   ├── GlassModifier.swift      # Liquid glass card & floating capsule modifiers
│   │   └── Typography.swift         # Rounded fonts & tabular numbers
│   ├── Components/
│   │   ├── HTMLRichTextView.swift   # Rich HTML parser for questions & explanations
│   │   ├── ProgressRingView.swift   # Smooth animated circular progress ring
│   │   ├── CountdownWidgetView.swift# Live countdown to FMGE Jan 9, 2027
│   │   ├── CachedAsyncImage.swift   # Async image loader with memory caching
│   │   ├── VideoPlayerView.swift    # AVPlayer controller with PiP & rate controls
│   │   ├── FlashcardDeckView.swift  # Full-screen zoomable flashcard gallery
│   │   ├── ModernButton.swift       # Spring bounce action button with glow
│   │   └── FloatingTabBar.swift     # Matched geometry floating glass tab bar
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
  - `user_tracker/{uid}`
- **Images CDN**: `https://cdn.jsdelivr.net/gh/cyberromeo/img@main/qbank/`
- **Flashcards CDN**: `https://d2vhwjmp3pf4cn.cloudfront.net`
