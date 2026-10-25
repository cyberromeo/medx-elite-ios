import SwiftUI

// Gate 0 probe — never instantiated, deleted in Gate 6.
//
// There is no Swift compiler on the maintenance machine, so every iOS 26 API the rebuilt UI
// leans on is referenced once here. The first CI build then settles every name and signature
// in one round trip instead of one failed build per screen. Each uncertain API sits in its own
// property so a failure is attributable from the error list alone.

struct MedxKitProbe: View {
    @Namespace private var glassSpace
    @State private var text = ""
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: 0) { navigationProbe }
            Tab(value: 1, role: .search) { Text("search") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { Text("accessory") }
    }

    // MARK: Navigation bar, toolbar, search

    private var navigationProbe: some View {
        NavigationStack {
            List {
                Section("Study") { Text("row") }
            }
            .listSectionMargins(.horizontal, 16)
            .navigationTitle("Question 3 of 12")
            .navigationSubtitle("Gram-Positive Cocci")
            .scrollEdgeEffectStyle(.soft, for: .top)
            .searchable(text: $text)
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { }
                }
                ToolbarItem(placement: .largeSubtitle) { Text("subtitle view") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm", role: .confirm) { }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Back", systemImage: "chevron.backward") { }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Next", systemImage: "chevron.forward") { }
                        .buttonStyle(.glassProminent)
                }
                ToolbarItem(placement: .bottomBar) { Text("no shared background") }
                    .sharedBackgroundVisibility(.hidden)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
    }

    // MARK: Glass and shapes

    private var glassProbe: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Text("a")
                    .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                    .glassEffectID("a", in: glassSpace)
                Text("b")
                    .glassEffect(.clear, in: ConcentricRectangle())
                Text("c")
                    .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(12)), isUniform: true))
            }
        }
        .buttonStyle(.glass)
        .backgroundExtensionEffect()
        .safeAreaBar(edge: .bottom) { Text("bar") }
    }

    // MARK: Figures, states, sheets (older than 26, listed so the kit's assumptions are explicit)

    private var figuresProbe: some View {
        VStack {
            Gauge(value: 0.4) { Text("goal") }
                .gaugeStyle(.accessoryCircularCapacity)
            Text(timerInterval: Date()...Date().addingTimeInterval(60), countsDown: true)
            ProgressView(timerInterval: Date()...Date().addingTimeInterval(60), countsDown: true)
            ContentUnavailableView("Nothing here", systemImage: "tray")
            Rectangle()
                .fill(.background.secondary)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
            Text("42").contentTransition(.numericText())
        }
        .presentationSizing(.page)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
