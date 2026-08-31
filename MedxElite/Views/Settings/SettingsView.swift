import SwiftUI
import PhotosUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var reminders = MedxNotificationManager.shared
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var spotlight = MedxSpotlightIndexer.shared
    @ObservedObject private var playback = MedxPlaybackDiagnostics.shared
    @ObservedObject private var vod = MedxVodWatcher.shared
    @ObservedObject private var proxy = HLSProxyServer.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var subjects: [MedxBankSubject] = []
    @State private var showSignOutConfirm = false
    @State private var showForgetCachedConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var showWipeIndexConfirm = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cacheCleared = false
    @State private var cacheSize: String = "…"
    @State private var imageCacheSize: String = "…"
    @State private var isManualSyncing = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Current Profile
                if let profile = authService.currentProfile {
                    // Read once here, in `body`'s own isolation. `PhotosPicker`'s label
                    // closure is not main-actor isolated, so reaching into the
                    // main-actor `AvatarStore` from inside it is a concurrency error.
                    let hasPhoto = avatars.hasImage(for: profile.id)

                    Section {
                        HStack(spacing: 16) {
                            ProfileAvatarView(profile: profile, size: 64)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.displayName)
                                    .font(.title3.weight(.semibold))
                                Text("@\(profile.handle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(profile.email)
                                    .font(.caption)
                                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)

                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label {
                                Text(hasPhoto ? "Change Profile Photo" : "Add Profile Photo")
                                    .font(.body)
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(MedxTheme.primaryBlue)
                            }
                            .frame(minHeight: 44)
                        }

                        if hasPhoto {
                            Button(role: .destructive) {
                                HapticManager.medium()
                                avatars.removeImage(for: profile.id)
                            } label: {
                                Label {
                                    Text("Remove Photo")
                                        .font(.body)
                                } icon: {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .foregroundColor(MedxDS.wrong)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    } footer: {
                        Text("Your photo is stored only on this device.")
                            .font(.caption)
                    }
                }

                appearanceSection

                examGoalsSection

                // MARK: - Library & Study History
                Section {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        settingsRow(
                            title: "Offline Downloads",
                            icon: "arrow.down.circle.fill",
                            color: MedxDS.correct,
                            value: "\(downloads.completedItems.count)"
                        )
                    }

                    NavigationLink {
                        BookmarkedQuestionsView(uid: authService.currentSession?.uid)
                    } label: {
                        settingsRow(
                            title: "Bookmarked Questions",
                            icon: "bookmark.fill",
                            color: MedxTheme.primaryPurple,
                            value: "\(activityStore.bookmarks(for: authService.currentSession?.uid).count)"
                        )
                    }

                    NavigationLink {
                        WatchHistoryView(uid: authService.currentSession?.uid)
                    } label: {
                        settingsRow(
                            title: "Watch History",
                            icon: "clock.arrow.circlepath",
                            color: MedxTheme.primaryBlue,
                            value: "\(activityStore.watchHistory(for: authService.currentSession?.uid).count)"
                        )
                    }

                    NavigationLink {
                        ActivityLogView(
                            uid: authService.currentSession?.uid,
                            attempts: $attempts
                        )
                    } label: {
                        settingsRow(
                            title: "Activity Log",
                            icon: "list.bullet.rectangle.portrait.fill",
                            color: MedxTheme.cyanAccent,
                            value: "\(activityStore.watchHistory(for: authService.currentSession?.uid).count + attempts.count)"
                        )
                    }
                } header: {
                    MedxSettingsHeader("Library", symbol: "square.grid.2x2.fill", hue: MedxCandy.mint)
                }

                // Grouped because a `List` builder takes at most ten direct children and
                // these three pushed it to eleven. `Group` is transparent to the list, so the
                // sections still render as sections.
                Group {
                    questionIndexSection

                    remindersSection

                    siriSection

                    diagnosticsSection
                }

                // MARK: - Cloud Sync
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firebase Cloud Sync")
                                    .font(.body)
                                if let lastSync = activityStore.lastSyncedAt {
                                    Text("Last synced \(RelativeDateTimeFormatter().localizedString(for: lastSync, relativeTo: Date()))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Automatic sync on changes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(MedxTheme.cyanAccent)
                        }

                        Spacer()

                        Button {
                            guard let uid = authService.currentSession?.uid else { return }
                            isManualSyncing = true
                            HapticManager.selection()
                            Task {
                                await activityStore.syncWithCloud(uid: uid)
                                await loadAttempts()
                                isManualSyncing = false
                                HapticManager.success()
                            }
                        } label: {
                            if isManualSyncing || activityStore.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sync Now")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(MedxTheme.primaryBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(MedxTheme.primaryBlue.opacity(0.12), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isManualSyncing || activityStore.isSyncing)
                    }
                } header: {
                    MedxSettingsHeader("Cloud Synchronization", symbol: "arrow.triangle.2.circlepath", hue: MedxCandy.blue)
                }

                // MARK: - Storage
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Videos")
                                    .font(.body)
                                Text("\(downloads.completedItems.count) classes saved in the app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(MedxDS.correct)
                        }
                        Spacer()
                        Text(downloads.formattedTotalSize)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    if !downloads.allItems.isEmpty {
                        Button(role: .destructive) {
                            showDeleteDownloadsConfirm = true
                        } label: {
                            Label {
                                Text("Delete All Downloads")
                                    .font(.body)
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundColor(MedxDS.wrong)
                            }
                        }
                    }

                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Question & Card Images")
                                    .font(.body)
                                Text("Figures and flashcard artwork kept for offline viewing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundColor(MedxTheme.indigoAccent)
                        }
                        Spacer()
                        Text(imageCacheSize)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Question Cache")
                                    .font(.body)
                                Text("Modules and papers available with no signal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "internaldrive.fill")
                                .foregroundColor(MedxTheme.primaryBlue)
                        }
                        Spacer()
                        Text(cacheSize)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task { await clearCaches() }
                    } label: {
                        HStack {
                            Label {
                                Text("Clear Cached Data")
                                    .font(.body)
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundColor(MedxDS.warn)
                            }
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(MedxDS.correct)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                } header: {
                    MedxSettingsHeader("Storage", symbol: "internaldrive.fill", hue: MedxCandy.violet)
                } footer: {
                    Text("Clearing cached data keeps your downloads, bookmarks and history — only the re-downloadable copies of questions and images are removed.")
                        .font(.caption)
                }

                // MARK: - Account Actions
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label {
                            Text("Sign Out")
                                .font(.body)
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(MedxDS.wrong)
                        }
                    }

                    if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                        Button(role: .destructive) {
                            showForgetCachedConfirm = true
                        } label: {
                            Label {
                                Text("Sign Out & Forget Password")
                                    .font(.body)
                            } icon: {
                                Image(systemName: "key.slash")
                                    .foregroundColor(MedxDS.wrong)
                            }
                        }
                    }
                } header: {
                    MedxSettingsHeader("Account", symbol: "person.crop.circle.fill", hue: MedxCandy.pink)
                }

                // MARK: - App Info
                Section {
                    HStack {
                        Label {
                            Text("Version")
                                .font(.body)
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(MedxTheme.cyanAccent)
                        }
                        Spacer()
                        Text("1.0.0")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Platform")
                                .font(.body)
                        } icon: {
                            Image(systemName: "swift")
                                .foregroundColor(MedxDS.warn)
                        }
                        Spacer()
                        Text("Swift Native iOS 17")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    creditFooter
                }
            }
            // A `List` paints its own `systemGroupedBackground`, which in dark is #1C1C1E — grey,
            // not black. Hiding it and putting the app's page underneath is what makes every
            // `List` in the app agree with every `ScrollView` in it.
            .scrollContentBackground(.hidden)
            .medxPage()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    HapticManager.light()
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("You can sign back in easily using your saved profile.")
            }
            .confirmationDialog("Forget Saved Password?", isPresented: $showForgetCachedConfirm) {
                Button("Forget & Sign Out", role: .destructive) {
                    if let pid = authService.currentProfile?.id {
                        authService.forgetPassword(for: pid)
                    }
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("This will remove your saved password from this device's Keychain.")
            }
            .confirmationDialog("Delete All Downloads?", isPresented: $showDeleteDownloadsConfirm) {
                Button("Delete \(downloads.allItems.count) Downloads", role: .destructive) {
                    HapticManager.warning()
                    downloads.removeAll()
                }
            } message: {
                Text("This frees \(downloads.formattedTotalSize) on this device. Your watch progress is kept and you can download the classes again any time.")
            }
            .confirmationDialog("Delete the question index?", isPresented: $showWipeIndexConfirm) {
                Button("Delete \(index.indexedCount.formatted()) indexed questions", role: .destructive) {
                    HapticManager.warning()
                    index.wipe()
                }
            } message: {
                Text("Search will only cover your bookmarks until it is rebuilt. Nothing else is affected.")
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem, let profileId = authService.currentProfile?.id else { return }
                Task { @MainActor in
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        AvatarStore.shared.setImage(data: data, for: profileId)
                        HapticManager.success()
                    }
                    photoItem = nil
                }
            }
            .task {
                await refreshCacheSize()
                await reminders.refreshAuthorization()
                if let uid = authService.currentSession?.uid {
                    await activityStore.syncWithCloud(uid: uid)
                }
                await loadAttempts()
                await loadSubjects()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            HStack(spacing: 16) {
                MedxLogoMark(size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("MedX Elite")
                        .font(.headline)
                    Text("Accent · \(medxTheme.accent.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(MedxAccent.allCases) { accent in
                    Button {
                        HapticManager.selection()
                        withAnimation(.snappy(duration: 0.25)) {
                            medxTheme.apply(accent: accent)
                        }
                        // The widgets carry the accent in their snapshot.
                        stats.publishSnapshot()
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if medxTheme.accent == accent {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.black))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        medxTheme.accent == accent ? Color.primary.opacity(0.45) : Color.clear,
                                        lineWidth: 2
                                    )
                                    .padding(-4)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.label)
                    .accessibilityAddTraits(medxTheme.accent == accent ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 6)

            Picker(selection: $medxTheme.appearance) {
                ForEach(MedxAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            } label: {
                Label("Appearance", systemImage: medxTheme.appearance.icon)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
        } header: {
            MedxSettingsHeader("Appearance", symbol: "paintpalette.fill", hue: MedxCandy.butter)
        } footer: {
            Text("The accent applies across the app, its widgets and the Lock Screen activities. Colours are system colours, so contrast settings keep working.")
                .font(.caption)
        }
    }

    // MARK: - Exam & goals

    private var examGoalsSection: some View {
        Section {
            DatePicker(
                selection: $stats.examDate,
                in: Date()...,
                displayedComponents: .date
            ) {
                Label("Exam date", systemImage: "calendar.badge.clock")
            }

            HStack {
                Label("Daily goal", systemImage: "target")
                Spacer()
                Text("\(stats.dailyGoal)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Stepper("") {
                    stats.dailyGoal = min(stats.dailyGoal + 10, 300)
                } onDecrement: {
                    stats.dailyGoal = max(stats.dailyGoal - 10, 10)
                }
                .labelsHidden()
            }
            .frame(minHeight: 44)

            HStack {
                Label("Today", systemImage: "flame.fill")
                Spacer()
                Text("\(stats.answeredToday) answered · \(stats.streakDays)-day streak")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        } header: {
            MedxSettingsHeader("Exam & goals", symbol: "target", hue: MedxCandy.tangerine)
        } footer: {
            Text("\(stats.daysToExam) days to \(stats.examName). The countdown card, the widgets and the reminders all read these two values.")
                .font(.caption)
        }
    }

    // MARK: - Question index

    private var questionIndexSection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searchable questions")
                            .font(.body)
                        Text(index.coverageSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                } icon: {
                    Image(systemName: "text.magnifyingglass")
                        .foregroundStyle(MedxTheme.tealAccent)
                }
                Spacer()
                Text(index.formattedSize)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)

            if index.isBuilding {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: index.coverage)
                        .tint(MedxTheme.accent)

                    HStack {
                        Text("\(index.modulesDone) of \(max(index.expectedModules, 1)) modules")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Pause") {
                            HapticManager.light()
                            index.cancelBuild()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    HapticManager.medium()
                    index.build(subjects: subjects)
                } label: {
                    Label {
                        Text(index.isEmpty ? "Build the index" : "Finish the index")
                            .font(.body)
                    } icon: {
                        Image(systemName: "arrow.down.doc")
                            .foregroundStyle(MedxTheme.accent)
                    }
                    .frame(minHeight: 44)
                }
                .disabled(subjects.isEmpty || index.isComplete)
            }

            if !index.isEmpty {
                Button(role: .destructive) {
                    showWipeIndexConfirm = true
                } label: {
                    Label {
                        Text("Delete the index")
                            .font(.body)
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(MedxDS.wrong)
                    }
                    .frame(minHeight: 44)
                }
            }

            if let error = index.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(MedxDS.warn)
            }
        } header: {
            MedxSettingsHeader("Question search", symbol: "magnifyingglass", hue: MedxCandy.lime)
        } footer: {
            // Both banks, so the split is worth naming: "32,467 questions" on its own does not
            // tell you whether the Marrow half actually landed.
            Text(index.isComplete
                 ? "All \(index.indexedCount.formatted()) questions are searchable offline — \(index.indexedCount(bank: .arise).formatted()) ARISE and \(index.indexedCount(bank: .marrow).formatted()) Marrow."
                 : "Searching every question needs their text on this device. Building fetches all \(max(index.expectedModules, 2171)) modules across both banks once — it is resumable, and it also makes those modules playable offline.")
                .font(.caption)
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            if !reminders.isAuthorized {
                Button {
                    Task {
                        let granted = await reminders.requestAuthorization()
                        if granted { HapticManager.success() } else { HapticManager.warning() }
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn on notifications")
                                .font(.body)
                            Text(reminders.authorization == .denied
                                 ? "Denied — enable them in the Settings app"
                                 : "Needed before any reminder can be scheduled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(MedxDS.warn)
                    }
                    .frame(minHeight: 44)
                }
            }

            ForEach(MedxNotificationManager.Kind.allCases) { kind in
                Toggle(isOn: reminderBinding(kind)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.body)
                            Text(kind.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: kind.icon)
                            .foregroundStyle(MedxTheme.accent)
                    }
                }
                .disabled(!reminders.isAuthorized)
            }

            Picker(selection: $reminders.reminderHour) {
                ForEach(Array(6...23), id: \.self) { hour in
                    Text(Self.hourLabel(hour)).tag(hour)
                }
            } label: {
                Label("Reminder time", systemImage: "clock")
            }
            .disabled(!reminders.enabled.contains(.dailyQuestions) || !reminders.isAuthorized)
        } header: {
            MedxSettingsHeader("Reminders", symbol: "bell.badge.fill", hue: MedxCandy.pink)
        } footer: {
            Text(reminders.isAuthorized
                 ? "\(reminders.pendingCount) scheduled. The wording is rebuilt each time the app opens, so the numbers are current."
                 : "Reminders stay off until notifications are allowed.")
                .font(.caption)
        }
        .tint(MedxTheme.accent)
    }

    private func reminderBinding(_ kind: MedxNotificationManager.Kind) -> Binding<Bool> {
        Binding(
            get: { reminders.enabled.contains(kind) },
            set: { isOn in
                var next = reminders.enabled
                if isOn { next.insert(kind) } else { next.remove(kind) }
                reminders.enabled = next
            }
        )
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        return date.formatted(.dateTime.hour().minute())
    }

    // MARK: - Siri & Spotlight

    private var siriSection: some View {
        Section {
            Toggle(isOn: $spotlight.isEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Index in Spotlight")
                            .font(.body)
                        Text(spotlight.indexedCount > 0
                             ? "\(spotlight.indexedCount.formatted()) items findable from the Home Screen"
                             : "Modules and bookmarks become findable from the Home Screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(MedxTheme.indigoAccent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Ask Siri", systemImage: "mic.circle.fill")
                    .font(.body)
                    .foregroundStyle(.primary)

                ForEach(["“Start today's revision in MedX Elite”",
                         "“How long until my exam in MedX Elite”",
                         "“Search questions in MedX Elite”"], id: \.self) { phrase in
                    Text(phrase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            MedxSettingsHeader("Siri, Spotlight & widgets", symbol: "sparkles", hue: MedxCandy.sky)
        } footer: {
            Text("Nothing is uploaded — Spotlight's index lives on this device and is removed when the switch is off.")
                .font(.caption)
        }
        .tint(MedxTheme.accent)
    }

    // MARK: - Credit

    private var creditFooter: some View {
        VStack(spacing: 6) {
            MedxWordmark(size: 17)
                .padding(.top, 10)

            Text("App designed by Srihari")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Built in Swift and SwiftUI to Apple's Human Interface Guidelines · v1.0.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MedX Elite, app designed by Srihari, version 1.0.0")
    }

    /// The stream proxy's state, and a way to rebind it by hand.
    ///
    /// iOS closes the listening socket whenever it suspends the app, which is why the port changes every
    /// time you come back to the foreground — and why "no class will play since I reopened the app" was a
    /// real bug rather than a network problem. `revalidate()` probes the bound port and only rebinds if
    /// nothing answers, so pressing this while a class is playing is safe.
    private var proxyDiagnostics: some View {
        Group {
            diagnosticRow(
                title: "Stream proxy",
                detail: proxy.isRunning
                    ? "Bound to port \(proxy.port)"
                    : "Not bound — classes will not stream",
                ok: proxy.isRunning
            )

            Button {
                HapticManager.medium()
                Task { await HLSProxyServer.shared.revalidate() }
            } label: {
                Label {
                    Text("Rebind the stream proxy")
                        .font(.body)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(MedxCandy.mint)
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("Checks whether the local proxy still answers and binds a new port if it does not")
        }
    }

    /// Sideloaded builds cannot be attached to Xcode, so the handful of facts that actually
    /// explain "widgets are empty", "Live Activities don't appear" and "this looks like the old
    /// iOS" are surfaced here rather than left to guesswork.
    private var diagnosticsSection: some View {
        Section {
            diagnosticRow(
                title: "Running on",
                detail: MedxInstallInfo.osVersion,
                ok: true
            )

            diagnosticRow(
                title: "Built against",
                detail: MedxInstallInfo.usesLegacyAppearance
                    ? "\(MedxInstallInfo.builtWithSDK) — legacy appearance"
                    : MedxInstallInfo.builtWithSDK,
                ok: !MedxInstallInfo.usesLegacyAppearance
            )

            diagnosticRow(
                title: "Widget extension",
                detail: MedxInstallInfo.hasWidgetExtension
                    ? MedxInstallInfo.installedExtensions.joined(separator: ", ")
                    : "Missing — reinstall and keep app extensions",
                ok: MedxInstallInfo.hasWidgetExtension
            )

            diagnosticRow(
                title: "Live Activities",
                detail: MedxLiveActivityController.shared.isAvailable
                    ? "Allowed"
                    : "Off — Settings ▸ MedX Elite ▸ Live Activities",
                ok: MedxLiveActivityController.shared.isAvailable
            )

            diagnosticRow(
                title: "Widget data",
                detail: MedxSharedStore.containerDescription,
                ok: MedxAppGroup.isShared
            )

            // Faceoff is the one feature that does not run on the REST path, so "the duel feels
            // laggy" has a different answer from every other slowness in this app and this is the
            // only place the difference is visible.
            diagnosticRow(
                title: "Faceoff transport",
                detail: faceoffTransportDetail,
                ok: MedxFirebaseBridge.shared.isReady
            )

            diagnosticRow(
                title: "VOD drop check",
                detail: vodDiagnostic,
                ok: vod.lastCheckedAt != nil
            )

            // The local HLS proxy is the only thing that can attach the headers the CDN insists on, so
            // when it is not bound no class will stream — and that used to be indistinguishable from a
            // dead stream. Row and button are one `Group` because a `Section` takes ten children and
            // this is the eleventh thing Diagnostics wants to say.
            proxyDiagnostics

            Button {
                HapticManager.medium()
                vod.resetWatermarks()
                Task { await vod.refreshFromForeground() }
            } label: {
                Label {
                    Text("Forget the VOD watermark")
                        .font(.body)
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(MedxCandy.blue)
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("Re-checks the bucket as though this device had never seen it, which posts the new-drop notification again")

            if let failure = playback.summary {
                Button {
                    playback.clear()
                } label: {
                    diagnosticRow(title: "Last playback error", detail: failure, ok: false)
                }
            }
        } header: {
            MedxSettingsHeader("Diagnostics", symbol: "stethoscope", hue: MedxCandy.violet)
        } footer: {
            Text(MedxInstallInfo.usesLegacyAppearance
                 ? "This build was compiled against an older iOS SDK, which is why the interface uses the previous system style — iOS only applies the current design language to apps linked against the iOS 26 SDK or newer. Rebuild with the updated CI workflow."
                 : "Tap a failed row to clear it. The VOD check runs on every launch and, when iOS agrees to it, roughly every two hours in the background — there is no push, so opening the app is the guarantee.")
                .font(.caption)
        }
    }

    /// What the duel is *actually* using, not what it could use.
    ///
    /// This row used to name the transport from `MedxFirebaseBridge.isReady`, and those are two
    /// different claims — readiness says the SDK is usable, and the open stream says what is being
    /// used. They disagreed for the whole of the transport-latch bug: every duel in the process was
    /// polling while this row was free to say "Live listeners". So the name comes from the live
    /// stream where there is one, and falls back to the bridge's own reason where there is not.
    private var faceoffTransportDetail: String {
        guard let name = MedxLobbyWatcher.shared.activeTransportName else {
            return "No stream open — \(MedxFirebaseBridge.shared.status)"
        }
        return "\(name) — \(MedxFirebaseBridge.shared.status)"
    }

    /// One line for the drop watcher: when it last looked, and what it found there. `count` in
    /// `medx_vod/_meta` is documents added by the sync installation rather than a collection total,
    /// so it is not shown here — the useful facts are the timestamp and whether anything is unseen.
    private var vodDiagnostic: String {        guard let checked = vod.lastCheckedAt else {
            return "Not checked yet this launch"
        }
        let when = checked.formatted(date: .omitted, time: .shortened)
        guard let newest = vod.meta?.lastUploadedAt else {
            return "Checked at \(when) — the bucket reported no uploads"
        }
        let drop = newest.formatted(date: .abbreviated, time: .shortened)
        if vod.unseenCount > 0 {
            return "Checked at \(when) — \(vod.unseenCount) unseen, newest \(drop)"
        }
        return "Checked at \(when) — up to date, newest \(drop)"
    }

    private func diagnosticRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? MedxDS.correct : MedxDS.warn)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    private func settingsRow(title: String, icon: String, color: Color, value: String) -> some View {
        HStack {
            Label {
                Text(title)
                    .font(.body)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    private func loadAttempts() async {
        guard let uid = authService.currentSession?.uid else { return }
        do {
            let token = try await authService.getValidIdToken()
            attempts = try await FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
            MedxStudyStatsStore.shared.ingest(attempts: attempts)
        } catch {
            attempts = []
        }
    }

    /// Needed by the index builder, which walks the module list out of the subject tree — both
    /// banks', so the Marrow modules are indexed alongside the ARISE ones.
    private func loadSubjects() async {
        guard subjects.isEmpty else { return }
        guard let token = try? await authService.getValidIdToken() else { return }
        subjects = (try? await FirestoreService.shared.fetchQBankBanks(idToken: token)) ?? []
        index.noteExpectations(subjects: subjects)
    }

    @MainActor
    private func refreshCacheSize() async {
        let documentBytes = await CacheManager.shared.diskSize()
        cacheSize = ByteCountFormatter.string(fromByteCount: documentBytes, countStyle: .file)

        let imageBytes = MedxImageLoader.shared.diskSize()
        imageCacheSize = ByteCountFormatter.string(fromByteCount: imageBytes, countStyle: .file)
    }

    /// Clears the two re-downloadable caches. Saved videos, bookmarks and history are
    /// untouched, which is what the footer promises.
    @MainActor
    private func clearCaches() async {
        await CacheManager.shared.clearAll()
        MedxImageLoader.shared.clear()
        HapticManager.success()
        withAnimation { cacheCleared = true }
        await refreshCacheSize()
    }
}

// MARK: - Bookmarked Questions View

struct BookmarkedQuestionsView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var searchText = ""
    @State private var selectedSubject: String = "All"
    @State private var showClearAllConfirm = false
    @State private var practicePayload: RunnerPayload?

    init(uid: String?) {
        self.uid = uid
    }

    private var allBookmarks: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid)
    }

    private var availableSubjects: [String] {
        let list = Set(allBookmarks.map { $0.subject }.filter { !$0.isEmpty })
        return ["All"] + list.sorted()
    }

    private var filteredBookmarks: [BookmarkedQuestion] {
        allBookmarks.filter { bookmark in
            let matchesSubject = selectedSubject == "All" || bookmark.subject == selectedSubject
            let matchesSearch = searchText.isEmpty ||
                bookmark.previewText.localizedCaseInsensitiveContains(searchText) ||
                bookmark.sourceName.localizedCaseInsensitiveContains(searchText) ||
                bookmark.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allBookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark MCQs during a sitting session or review to revise them here.")
                )
            } else {
                List {
                    // Subject Filter Chips
                    if availableSubjects.count > 2 {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableSubjects, id: \.self) { subj in
                                        Button {
                                            HapticManager.selection()
                                            selectedSubject = subj
                                        } label: {
                                            Text(subj)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(selectedSubject == subj ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    selectedSubject == subj ? MedxTheme.primaryPurple : MedxDS.sunken,
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section {
                        ForEach(filteredBookmarks) { bookmark in
                            NavigationLink {
                                BookmarkedQuestionDetailView(bookmark: bookmark, uid: uid)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bookmark.previewText)
                                        .font(.body)
                                        .lineLimit(3)

                                    HStack(spacing: 6) {
                                        if !bookmark.subject.isEmpty {
                                            Text(bookmark.subject)
                                                .font(.caption2.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxTheme.primaryPurple)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                                        }

                                        Text(bookmark.sourceName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(bookmark.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticManager.medium()
                                    activityStore.removeBookmark(bookmark, uid: uid)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredBookmarks.count) of \(allBookmarks.count) bookmarked questions")
                            .font(.caption)
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search bookmarks…")
            }
        }
        .medxPage()
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allBookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Label("Clear All Bookmarks", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear All Bookmarks?",
            isPresented: $showClearAllConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllBookmarks(uid: uid)
            }
        } message: {
            Text("This will remove all bookmarked questions locally and from your cloud account.")
        }
    }
}

// MARK: - Bookmarked Question Detail View

private struct BookmarkedQuestionDetailView: View {
    let bookmark: BookmarkedQuestion
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header meta badge
                HStack {
                    if !bookmark.subject.isEmpty {
                        Text(bookmark.subject)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(MedxTheme.primaryPurple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                    }

                    Text(bookmark.sourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(bookmark.formattedDate)
                        .font(.caption)
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }

                // Question HTML display
                HTMLRichTextView(html: bookmark.question.displayText, fontSize: 17, weight: .semibold)

                // Images if any
                if let imgs = bookmark.question.images, !imgs.isEmpty {
                    ForEach(imgs, id: \.self) { imgUrl in
                        CachedAsyncImage(url: URL(string: imgUrl))
                            .frame(maxHeight: 220)
                            .clipShape(MedxDS.shape(MedxDS.control))
                    }
                }

                // Options with Answer Key
                VStack(spacing: 10) {
                    ForEach(Array(bookmark.question.options.enumerated()), id: \.offset) { pair in
                        let option = pair.element
                        let isCorrect = bookmark.question.correctIds.contains(option.id) || option.correct == true

                        HStack(alignment: .center, spacing: 12) {
                            Text(MedxOptionLetter.of(option, at: pair.offset))
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundColor(isCorrect ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(isCorrect ? MedxDS.correct : Color.primary.opacity(0.08))
                                .clipShape(Circle())

                            HTMLRichTextView(html: option.text, fontSize: 14, weight: .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)

                            Spacer(minLength: 0)

                            if isCorrect {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(MedxDS.correct)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                        .background(isCorrect ? MedxDS.correct.opacity(0.12) : MedxDS.sunken, in: MedxDS.shape(MedxDS.control))
                        .overlay(
                            MedxDS.shape(MedxDS.control)
                                .strokeBorder(isCorrect ? MedxDS.correct.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }

                // Explanation
                if let explanation = bookmark.question.explanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Explanation", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MedxDS.warn)
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .medxCard()
                }

                // Remove Bookmark Button
                Button(role: .destructive) {
                    HapticManager.medium()
                    activityStore.removeBookmark(bookmark, uid: uid)
                    dismiss()
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .medxBorderedButton()
                .tint(MedxDS.wrong)
                .padding(.top, 10)
            }
            .padding(20)
        }
        .background(MedxDS.page)
        .navigationTitle("Question Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Watch History View

private struct WatchHistoryView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var showClearConfirm = false

    private var entries: [WatchHistoryEntry] {
        activityStore.watchHistory(for: uid)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you start watching will automatically track your progress and resume position here.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            activeVideo = entry.video
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(MedxTheme.primaryBlue.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(MedxTheme.primaryBlue)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.video.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        Text(entry.video.subject)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let faculty = entry.video.faculty, !faculty.isEmpty {
                                            Text("· \(faculty)")
                                                .font(.caption)
                                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                        }

                                        Spacer()

                                        Text(entry.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }

                                    ProgressView(value: entry.progress)
                                        .tint(entry.isCompleted ? MedxDS.correct : MedxTheme.primaryBlue)

                                    HStack {
                                        if entry.isCompleted {
                                            Label("Completed", systemImage: "checkmark.circle.fill")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxDS.correct)
                                        } else {
                                            Label("Resume at \(entry.formattedResumeTime)", systemImage: "arrow.counterclockwise.circle.fill")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxTheme.cyanAccent)
                                        }
                                        Spacer()
                                        Text("\(Int(entry.progress * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                HapticManager.medium()
                                activityStore.removeWatchHistory(entry, uid: uid)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .medxPage()
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear All Watch History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear Watch History?",
            isPresented: $showClearConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllWatchHistory(uid: uid)
            }
        } message: {
            Text("This will clear your watch progress and resume positions for all videos locally and in the cloud.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }
}

// MARK: - Activity Log View (Unified Watch History & Test Attempts)

struct ActivityLogView: View {
    let uid: String?
    @Binding var attempts: [SittingAttempt]
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""
    @State private var pendingDeletion: ActivityLogItem?
    @State private var showClearOptions = false
    @State private var deletionError = false
    @State private var isDeleting = false

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case qbank = "QBank"
        case tests = "Tests"

        var id: String { rawValue }
    }

    /// Which attempt kinds count as a paper rather than a module. `series` joined `test` when
    /// the Tests tab became the Marrow catalogue; without it, 352 papers' worth of sittings
    /// were filed under QBank.
    private static let paperKinds: Set<String> = ["test", "series"]

    private var allItems: [ActivityLogItem] {
        let videoItems = activityStore.watchHistory(for: uid).map(ActivityLogItem.video)
        let attemptItems = attempts.map(ActivityLogItem.attempt)
        return (videoItems + attemptItems).sorted { $0.date > $1.date }
    }

    private var filteredItems: [ActivityLogItem] {
        allItems.filter { item in
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .videos:
                if case .video = item { matchesCategory = true } else { matchesCategory = false }
            case .qbank:
                if case .attempt(let att) = item, !Self.paperKinds.contains(att.kind) { matchesCategory = true } else { matchesCategory = false }
            case .tests:
                if case .attempt(let att) = item, Self.paperKinds.contains(att.kind) { matchesCategory = true } else { matchesCategory = false }
            }

            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.subtitle.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView(
                    "No Activity Log",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Your video watch history and QBank/test attempts will appear in this unified log.")
                )
            } else {
                List {
                    // Filter picker
                    Section {
                        Picker("Filter Activity", selection: $selectedFilter) {
                            ForEach(LogFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 2)
                    }

                    Section {
                        ForEach(filteredItems) { item in
                            HStack(spacing: 14) {
                                MedxSymbolMark(item.symbol, hue: item.color, size: 34)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(2)

                                    Text(item.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text(item.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(item.title)")
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredItems.count) activity entries")
                            .font(.caption)
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search activity log…")
            }
        }
        .medxPage()
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            activityStore.clearAllWatchHistory(uid: uid)
                        } label: {
                            Label("Clear Watch History", systemImage: "play.slash")
                        }

                        Button(role: .destructive) {
                            Task {
                                await clearAllAttempts()
                            }
                        } label: {
                            Label("Clear All Test Attempts", systemImage: "doc.badge.gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Activity Entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        } message: { item in
            Text(item.deleteMessage)
        }
        .alert("Failed to Delete", isPresented: $deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not delete from cloud. Please check your internet connection and try again.")
        }
    }

    private func deleteItem(_ item: ActivityLogItem) {
        switch item {
        case .video(let entry):
            activityStore.removeWatchHistory(entry, uid: uid)
            HapticManager.success()

        case .attempt(let attempt):
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.deleteAttempt(attempt, idToken: token)
                    withAnimation {
                        attempts.removeAll { $0.id == attempt.id || ($0.sourceId == attempt.sourceId && $0.finishedAt == attempt.finishedAt) }
                    }
                    HapticManager.success()
                } catch {
                    deletionError = true
                }
            }
        }
        pendingDeletion = nil
    }

    private func clearAllAttempts() async {
        guard let token = try? await AuthService.shared.getValidIdToken() else { return }
        for att in attempts {
            try? await FirestoreService.shared.deleteAttempt(att, idToken: token)
        }
        withAnimation {
            attempts.removeAll()
        }
        HapticManager.success()
    }
}

// MARK: - Activity Log Item Wrapper

private enum ActivityLogItem: Identifiable, Hashable {
    case video(WatchHistoryEntry)
    case attempt(SittingAttempt)

    var id: String {
        switch self {
        case .video(let entry): return "video-\(entry.ownerId)-\(entry.id)"
        case .attempt(let attempt): return "attempt-\(attempt.id ?? attempt.sourceId + (attempt.finishedAt ?? ""))"
        }
    }

    var date: Date {
        switch self {
        case .video(let entry): return entry.watchedAt
        case .attempt(let attempt): return attempt.finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
        }
    }

    var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .attempt(let attempt): return MedxAttemptKind.symbol(attempt.kind)
        }
    }

    var color: Color {
        switch self {
        case .video: return MedxCandy.violet
        case .attempt(let attempt): return MedxAttemptKind.hue(attempt.kind)
        }
    }

    var title: String {
        switch self {
        case .video(let entry): return entry.video.title
        case .attempt(let attempt): return attempt.name
        }
    }

    var subtitle: String {
        switch self {
        case .video(let entry):
            let status = entry.isCompleted ? "Watched" : "Resume at \(entry.formattedResumeTime)"
            return "\(entry.video.subject) · \(status) (\(Int(entry.progress * 100))%)"
        case .attempt(let attempt):
            let kind = MedxAttemptKind.label(attempt.kind)
            let mode = attempt.mode == "exam" ? "Exam" : "Revision"
            return "\(kind) (\(mode)) · Score: \(attempt.score)/\(attempt.total) (\(attempt.totalPercentage)%)"
        }
    }

    var formattedDate: String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var deleteMessage: String {
        switch self {
        case .video: return "Deleting this log entry will delete the watch history and clear its resume position both locally and in Firebase."
        case .attempt: return "Deleting this log entry will permanently remove the test/QBank attempt record locally and in Firebase."
        }
    }
}

// MARK: - Section heading

/// A settings section heading with its own symbol.
///
/// Settings is the one screen with nine peer sections and no hierarchy between them, so the marks
/// are doing real work rather than decoration: they are what makes "the one with the reminders"
/// findable by scrolling instead of by reading every heading on the way past.
struct MedxSettingsHeader: View {
    private let title: String
    private let symbol: String
    private let hue: Color

    init(_ title: String, symbol: String, hue: Color) {
        self.title = title
        self.symbol = symbol
        self.hue = hue
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(title)
        }
        .foregroundStyle(MedxCandy.onSoft(hue))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
