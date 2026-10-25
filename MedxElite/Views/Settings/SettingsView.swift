import SwiftUI
import PhotosUI

/// The Profile page: who is signed in and how it is going, then the handful of things that are
/// set once — the exam, the goal, reminders, appearance, storage — and the way out. A grouped
/// list, the way the system's own Settings is laid out, reached from the profile button only.
///
/// The figures in the hero are `MedxStudyStatsStore`'s, the same ones Home and the widgets
/// draw, so this page cannot disagree with them.
public struct SettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var reminders = MedxNotificationManager.shared

    @State private var photoItem: PhotosPickerItem?
    @State private var showSignOutConfirm = false
    @State private var showForgetConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var cacheBytes: Int64 = 0
    @State private var imageBytes: Int64 = 0
    @State private var isManualSyncing = false
    @State private var cacheCleared = false

    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                List {
                    heroSection

                    examSection

                    remindersSection
                        .id("settings.mid")

                    appearanceSection

                    storageSection

                    advancedSection

                    accountSection

                    aboutSection
                        .id("settings.end")
                }
                .listStyle(.insetGrouped)
                #if DEBUG
                .task {
                    // Screenshot runs only: `-medxScroll 1|2` scrolls to the middle or the end.
                    let target = UserDefaults.standard.integer(forKey: "medxScroll")
                    guard target > 0 else { return }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let id = target == 1 ? "settings.mid" : "settings.end"
                    // Twice: the list is lazy, and the first scroll only brings the far section
                    // into existence; the second lands on it.
                    scroller.scrollTo(id, anchor: .top)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    scroller.scrollTo(id, anchor: target == 1 ? .top : .bottom)
                }
                #endif
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Sign out", role: .destructive) {
                    HapticManager.light()
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("Your saved password stays on this device, so signing back in is one tap.")
            }
            .confirmationDialog("Forget the saved password?", isPresented: $showForgetConfirm) {
                Button("Forget and sign out", role: .destructive) {
                    if let id = authService.currentProfile?.id {
                        authService.forgetPassword(for: id)
                    }
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("Removes the password from this device's Keychain. You will type it next time.")
            }
            .confirmationDialog("Clear the cache?", isPresented: $showClearCacheConfirm) {
                Button("Clear \(MedxFormat.bytes(cacheBytes + imageBytes))", role: .destructive) {
                    Task { await clearCaches() }
                }
            } message: {
                Text("Modules, papers and images are downloaded again as you open them. Downloads, bookmarks and history are kept.")
            }
            .confirmationDialog("Delete every download?", isPresented: $showDeleteDownloadsConfirm) {
                Button("Delete \(downloads.allItems.count) downloads", role: .destructive) {
                    HapticManager.warning()
                    downloads.removeAll()
                }
            } message: {
                Text("Frees \(MedxFormat.bytes(downloads.totalBytes)). Watch progress is kept and any class can be saved again.")
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
                await refreshStorage()
                await reminders.refreshAuthorization()
                await loadFiguresIfNeeded()
            }
        }
    }

    // MARK: - Hero

    /// The email under the name. Demo runs (simulator screenshots, published publicly) show a
    /// placeholder rather than a real address.
    private func shownEmail(_ profile: Profile) -> String {
        #if DEBUG
        if MedxDemoMode.isOn { return "sri@example.com" }
        #endif
        return profile.email
    }

    private var heroSection: some View {
        Section {
            if let profile = authService.currentProfile {
                VStack(spacing: MedxSpace.m) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(profile: profile, size: 88, showsRing: true)

                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(MedxTheme.accent, in: Circle())
                                .overlay(Circle().strokeBorder(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(avatars.hasImage(for: profile.id) ? "Change profile photo" : "Add profile photo")
                    }

                    VStack(spacing: 2) {
                        Text(profile.displayName)
                            .font(.title2.weight(.bold))
                        Text("@\(profile.handle) · \(shownEmail(profile))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    MedxStatRow {
                        MedxStatTile("\(stats.streakDays)", label: "day streak", symbol: MedxFeature.streak.symbol, hue: MedxFeature.streak.color)
                        MedxStatTile(stats.overallAccuracy.map { "\($0)%" } ?? "–", label: "accuracy", symbol: MedxFeature.goal.symbol, hue: MedxOutcome.correct)
                        MedxStatTile("\(stats.sittings)", label: "sittings", symbol: "checklist", hue: MedxTheme.accent)
                    }
                    .padding(.top, MedxSpace.xs)

                    if avatars.hasImage(for: profile.id) {
                        Button("Remove photo", role: .destructive) {
                            HapticManager.medium()
                            avatars.removeImage(for: profile.id)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MedxSpace.s)
            }
        }
    }

    // MARK: - Exam & goal

    private var examSection: some View {
        Section {
            HStack {
                MedxTileLabel("Exam", symbol: "graduationcap.fill", hue: MedxTheme.accent)
                Spacer()
                TextField("Name", text: $stats.examName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 160)
            }

            DatePicker(selection: $stats.examDate, in: Date()..., displayedComponents: .date) {
                MedxTileLabel("Exam date", symbol: "calendar", hue: MedxFeature.syllabus.color)
            }

            LabeledContent {
                Text(MedxFormat.days(MedxDates.daysUntil(stats.examDate)))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } label: {
                MedxTileLabel("Days left", symbol: "hourglass", hue: MedxFeature.tests.color)
            }

            // The stepper's own label slot stacks a tiled label under its icon once the control
            // takes its width, so the row is laid out by hand and the control's label hidden.
            HStack(spacing: MedxSpace.m) {
                MedxTileLabel("Daily goal", detail: "questions a day", symbol: MedxFeature.goal.symbol, hue: MedxFeature.goal.color)
                Spacer(minLength: MedxSpace.s)
                Text("\(stats.dailyGoal)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
                Stepper("Daily goal", value: $stats.dailyGoal, in: 10...300, step: 10)
                    .labelsHidden()
            }
        } header: {
            Text("Exam & goal")
        } footer: {
            Text("The Home Screen and Lock Screen widgets use these too.")
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            if reminders.isAuthorized {
                ForEach(MedxNotificationManager.Kind.allCases) { kind in
                    Toggle(isOn: reminderBinding(kind)) {
                        MedxTileLabel(kind.title, detail: kind.detail, symbol: kind.icon, hue: MedxFeature.vod.color)
                    }
                }

                Picker(selection: $reminders.reminderHour) {
                    ForEach(Array(6...23), id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                } label: {
                    MedxTileLabel("Reminder time", symbol: "clock.fill", hue: MedxFeature.vod.color)
                }
                .disabled(!reminders.enabled.contains(.dailyQuestions))
            } else if reminders.authorization == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    MedxTileLabel(
                        "Allow notifications in Settings",
                        detail: "They were turned off for this app.",
                        symbol: "bell.slash.fill",
                        hue: MedxOutcome.flagged
                    )
                }
            } else {
                Button {
                    Task {
                        let granted = await reminders.requestAuthorization()
                        if granted { HapticManager.success() } else { HapticManager.warning() }
                    }
                } label: {
                    MedxTileLabel(
                        "Turn on notifications",
                        detail: "A daily nudge, streak protection, revision due and new recordings.",
                        symbol: "bell.badge.fill",
                        hue: MedxOutcome.flagged
                    )
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(reminders.isAuthorized
                 ? "\(reminders.pendingCount) scheduled. The wording is rebuilt each time the app opens, so the numbers are current."
                 : "Reminders stay off until notifications are allowed.")
        }
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

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: MedxSpace.m)], spacing: MedxSpace.m) {
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
                                    .strokeBorder(medxTheme.accent == accent ? Color.primary.opacity(0.45) : Color.clear, lineWidth: 2)
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
            .padding(.vertical, MedxSpace.xs)

            Picker("Appearance", selection: $medxTheme.appearance) {
                ForEach(MedxAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("\(medxTheme.accent.label) is the accent across the app, its widgets and the Lock Screen activities.")
        }
    }

    // MARK: - Sync & storage

    private var storageSection: some View {
        Section {
            HStack {
                MedxTileLabel(
                    "Cloud sync",
                    detail: "Last synced \(MedxFormat.relative(activityStore.lastSyncedAt).lowercased())",
                    symbol: "icloud.fill",
                    hue: MedxFeature.vod.color
                )
                Spacer()
                if isManualSyncing || activityStore.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Sync now") {
                        guard let uid = authService.currentSession?.uid else { return }
                        isManualSyncing = true
                        HapticManager.selection()
                        Task {
                            await activityStore.syncWithCloud(uid: uid)
                            await loadFigures()
                            isManualSyncing = false
                            HapticManager.success()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }

            LabeledContent {
                Text(MedxFormat.bytes(downloads.totalBytes))
            } label: {
                MedxTileLabel("Videos", detail: downloads.completedItems.isEmpty ? "Nothing saved" : "\(downloads.completedItems.count) saved", symbol: "film.stack.fill", hue: MedxFeature.downloads.color)
            }

            LabeledContent {
                Text(MedxFormat.bytes(imageBytes))
            } label: {
                MedxTileLabel("Images", symbol: "photo.fill", hue: MedxFeature.classes.color)
            }

            LabeledContent {
                Text(MedxFormat.bytes(cacheBytes))
            } label: {
                MedxTileLabel("Questions", symbol: "doc.text.fill", hue: MedxFeature.qbank.color)
            }

            Button {
                showClearCacheConfirm = true
            } label: {
                MedxTileLabel(cacheCleared ? "Cache cleared" : "Clear cache", symbol: cacheCleared ? "checkmark.circle.fill" : "arrow.counterclockwise", hue: cacheCleared ? MedxOutcome.correct : MedxOutcome.flagged)
            }
            .disabled(cacheCleared)

            if !downloads.allItems.isEmpty {
                Button(role: .destructive) {
                    showDeleteDownloadsConfirm = true
                } label: {
                    MedxTileLabel("Delete all downloads", symbol: "trash.fill", hue: MedxOutcome.wrong)
                }
            }
        } header: {
            Text("Sync & storage")
        } footer: {
            Text("New modules, papers and classes appear on their own when you open the app or pull down. Clearing the cache keeps your downloads, bookmarks and history.")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            NavigationLink {
                AdvancedSettingsView()
            } label: {
                MedxTileLabel("Advanced", detail: "Offline search · Siri · diagnostics", symbol: MedxFeature.settings.symbol, hue: MedxFeature.settings.color)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            Button("Sign out", role: .destructive) {
                showSignOutConfirm = true
            }
            .frame(maxWidth: .infinity)

            if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                Button("Sign out and forget the saved password", role: .destructive) {
                    showForgetConfirm = true
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(spacing: MedxSpace.xs) {
                MedxWordmark(size: 17)
                    .padding(.top, MedxSpace.s)
                Text("App designed by Srihari")
                    .font(.footnote.weight(.semibold))
                Text("Built in Swift and SwiftUI · Version \(Self.appVersion)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("MedX Elite, app designed by Srihari, version \(Self.appVersion)")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    // MARK: - Data

    /// The hero's figures come from the stats store; it is normally full by the time this sheet
    /// opens, and filled here if Home has not run yet.
    private func loadFiguresIfNeeded() async {
        guard !stats.hasIngested else { return }
        await loadFigures()
    }

    private func loadFigures() async {
        guard let uid = authService.currentSession?.uid,
              let token = try? await authService.getValidIdToken(),
              let attempts = try? await FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
        else { return }
        stats.ingest(attempts: attempts)
    }

    @MainActor
    private func refreshStorage() async {
        cacheBytes = await CacheManager.shared.diskSize()
        imageBytes = MedxImageLoader.shared.diskSize()
    }

    /// Clears the two re-downloadable caches. Saved videos, bookmarks and history are untouched,
    /// which is what the footer promises.
    @MainActor
    private func clearCaches() async {
        await CacheManager.shared.clearAll()
        MedxImageLoader.shared.clear()
        HapticManager.success()
        withAnimation { cacheCleared = true }
        await refreshStorage()
    }
}

// MARK: - Advanced

/// The rarely-touched machinery, one push away instead of in the middle of the page: the
/// offline question index, Spotlight and Siri, and the diagnostics a sideloaded build cannot
/// otherwise show.
struct AdvancedSettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var spotlight = MedxSpotlightIndexer.shared
    @ObservedObject private var playback = MedxPlaybackDiagnostics.shared
    @ObservedObject private var vod = MedxVodWatcher.shared
    @ObservedObject private var proxy = HLSProxyServer.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var showWipeIndexConfirm = false

    var body: some View {
        List {
            questionIndexSection

            siriSection

            diagnosticsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete the question index?", isPresented: $showWipeIndexConfirm) {
            Button("Remove \(index.indexedCount.formatted()) downloaded questions", role: .destructive) {
                HapticManager.warning()
                index.wipe()
            }
        } message: {
            Text("Search will only cover your bookmarks until it is rebuilt. Nothing else is affected.")
        }
        .task { await loadSubjects() }
    }

    // MARK: Question index

    private var questionIndexSection: some View {
        Section {
            HStack {
                MedxTileLabel("Searchable questions", detail: index.coverageSummary, symbol: "text.magnifyingglass", hue: MedxFeature.search.color)
                Spacer()
                Text(index.formattedSize)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if index.isBuilding {
                VStack(alignment: .leading, spacing: MedxSpace.s) {
                    ProgressView(value: index.coverage)

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
                .padding(.vertical, MedxSpace.xs)
            } else {
                Button {
                    HapticManager.medium()
                    index.build(subjects: subjects)
                } label: {
                    MedxTileLabel(index.isEmpty ? "Download for offline search" : "Finish downloading", symbol: "arrow.down.doc.fill", hue: MedxTheme.accent)
                }
                .disabled(subjects.isEmpty || index.isComplete)
            }

            if !index.isEmpty {
                Button(role: .destructive) {
                    showWipeIndexConfirm = true
                } label: {
                    MedxTileLabel("Remove offline search", symbol: "trash.fill", hue: MedxOutcome.wrong)
                }
            }

            if let error = index.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(MedxOutcome.flagged)
            }
        } header: {
            Text("Question search")
        } footer: {
            Text(index.isComplete
                 ? "All \(index.indexedCount.formatted()) questions are searchable offline, \(index.indexedCount(bank: .arise).formatted()) ARISE and \(index.indexedCount(bank: .marrow).formatted()) Marrow."
                 : "Searching every question needs their text on this device. Downloading them takes a few minutes once, can be paused, and also makes every module playable offline.")
        }
    }

    // MARK: Siri & Spotlight

    private var siriSection: some View {
        Section {
            Toggle(isOn: $spotlight.isEnabled) {
                MedxTileLabel(
                    "Show in Spotlight",
                    detail: spotlight.indexedCount > 0
                        ? "\(spotlight.indexedCount.formatted()) items findable from the Home Screen"
                        : "Modules and bookmarks become findable from the Home Screen",
                    symbol: "magnifyingglass.circle.fill",
                    hue: MedxFeature.search.color
                )
            }

            VStack(alignment: .leading, spacing: MedxSpace.s) {
                MedxTileLabel("Ask Siri", symbol: "mic.fill", hue: MedxFeature.customModules.color)
                ForEach(["“Start today's revision in MedX Elite”",
                         "“How long until my exam in MedX Elite”",
                         "“Search questions in MedX Elite”"], id: \.self) { phrase in
                    Text(phrase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, MedxSpace.xs)
        } header: {
            Text("Siri & Spotlight")
        } footer: {
            Text("Nothing is uploaded. Spotlight keeps this on the device and it is removed when the switch is off.")
        }
    }

    // MARK: Diagnostics

    /// Sideloaded builds cannot be attached to Xcode, so the handful of facts that actually
    /// explain "widgets are empty", "Live Activities don't appear" and "no class will play" are
    /// surfaced here rather than left to guesswork.
    private var diagnosticsSection: some View {
        Section {
            diagnosticRow(title: "Running on", detail: MedxInstallInfo.osVersion, ok: true)

            diagnosticRow(
                title: "Built against",
                detail: MedxInstallInfo.usesLegacyAppearance
                    ? "\(MedxInstallInfo.builtWithSDK), legacy appearance"
                    : MedxInstallInfo.builtWithSDK,
                ok: !MedxInstallInfo.usesLegacyAppearance
            )

            diagnosticRow(
                title: "Widget extension",
                detail: MedxInstallInfo.hasWidgetExtension
                    ? MedxInstallInfo.installedExtensions.joined(separator: ", ")
                    : "Missing, reinstall and keep app extensions",
                ok: MedxInstallInfo.hasWidgetExtension
            )

            diagnosticRow(
                title: "Live Activities",
                detail: MedxLiveActivityController.shared.isAvailable
                    ? "Allowed"
                    : "Off, Settings ▸ MedX Elite ▸ Live Activities",
                ok: MedxLiveActivityController.shared.isAvailable
            )

            diagnosticRow(title: "Widget data", detail: MedxSharedStore.containerDescription, ok: MedxAppGroup.isShared)

            diagnosticRow(title: "Faceoff transport", detail: faceoffTransportDetail, ok: MedxFirebaseBridge.shared.isReady)

            diagnosticRow(title: "VOD drop check", detail: vodDiagnostic, ok: vod.lastCheckedAt != nil)

            proxyDiagnostics

            Button {
                HapticManager.medium()
                vod.resetWatermarks()
                Task { await vod.refreshFromForeground() }
            } label: {
                MedxTileLabel("Forget the VOD watermark", symbol: "bell.badge.fill", hue: MedxFeature.vod.color)
            }
            .accessibilityHint("Checks for new recordings again and shows the notification again")

            if let failure = playback.summary {
                Button {
                    playback.clear()
                } label: {
                    diagnosticRow(title: "Last playback error", detail: failure, ok: false)
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text(MedxInstallInfo.usesLegacyAppearance
                 ? "This copy of the app was built for an older iOS, so it uses the previous look. Install the latest build to get the new design."
                 : "Tap a failed row to clear it. New recordings are checked every time you open the app, and every couple of hours in the background when iOS allows it.")
        }
    }

    /// The stream proxy's state, and a way to rebind it by hand. `revalidate()` probes the bound
    /// port and only rebinds if nothing answers, so pressing this while a class is playing is safe.
    private var proxyDiagnostics: some View {
        Group {
            diagnosticRow(
                title: "Stream proxy",
                detail: proxy.isRunning ? "Bound to port \(proxy.port)" : "Not bound, classes will not stream",
                ok: proxy.isRunning
            )

            Button {
                HapticManager.medium()
                Task { await HLSProxyServer.shared.revalidate() }
            } label: {
                MedxTileLabel("Rebind the stream proxy", symbol: "arrow.triangle.2.circlepath", hue: MedxFeature.downloads.color)
            }
            .accessibilityHint("Checks whether the local proxy still answers and binds a new port if it does not")
        }
    }

    /// What the duel is *actually* using, not what it could use: the name comes from the live
    /// stream where there is one, and falls back to the bridge's own reason where there is not.
    private var faceoffTransportDetail: String {
        guard let name = MedxLobbyWatcher.shared.activeTransportName else {
            return "No stream open, \(MedxFirebaseBridge.shared.status)"
        }
        return "\(name), \(MedxFirebaseBridge.shared.status)"
    }

    private var vodDiagnostic: String {
        guard let checked = vod.lastCheckedAt else {
            return "Not checked yet this launch"
        }
        let when = checked.formatted(date: .omitted, time: .shortened)
        guard let newest = vod.meta?.lastUploadedAt else {
            return "Checked at \(when), no new recordings"
        }
        let drop = newest.formatted(date: .abbreviated, time: .shortened)
        if vod.unseenCount > 0 {
            return "Checked at \(when), \(vod.unseenCount) unseen, newest \(drop)"
        }
        return "Checked at \(when), up to date, newest \(drop)"
    }

    private func diagnosticRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: MedxSpace.m) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? MedxOutcome.correct : MedxOutcome.flagged)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    /// Needed by the index builder, which walks the module list out of the subject tree — both
    /// banks', so the Marrow modules are indexed alongside the ARISE ones.
    private func loadSubjects() async {
        guard subjects.isEmpty else { return }
        guard let token = try? await authService.getValidIdToken() else { return }
        subjects = (try? await FirestoreService.shared.fetchQBankBanks(idToken: token)) ?? []
        index.noteExpectations(subjects: subjects)
    }
}
