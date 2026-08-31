import SwiftUI

// MARK: - Backdrop (deprecated shim)
//
// There is no backdrop any more. This file is a forwarder, kept for exactly as long as it takes to
// drop the arguments at the 36 `medxPage(_:intensity:)` call sites; the real page treatment is
// `medxPage()` in `Theme/MedxDS.swift`, which is one fill.
//
// What was here, and why it went:
//
//   * **A radial gradient of the section's hue behind every screen.** Its job was to give glass
//     something to refract, and then to hint at which tab you were on. The app no longer puts glass on
//     content, and the tab bar already says which tab you are on in the same colour — so it was a
//     full-screen gradient composited under every scroll, encoding something already on screen.
//   * **`scrollEdgeEffectStyle(.soft, for: .all)`**, applied to all 36 screens through `medxPage`.
//     That is a live blur along all four scroll edges, recomputed every frame of every scroll. It was
//     the single most expensive thing in the app and it was invisible on a black page. It is not
//     disabled behind a flag — the helper that applied it is gone.
//
// `MedxAurora` itself is no longer a view. Nothing constructs it.

public extension View {
    /// Forwards to `medxPage()`. The section and the intensity are both ignored: there is nothing
    /// left on the page for either of them to change.
    ///
    /// Deliberately not marked `@available(*, deprecated:)` — a deprecation warning on 36 call sites
    /// is noise in a build log that has to stay readable, and the call sites are being rewritten in
    /// the same pass that deletes this file.
    func medxPage(_ section: MedxSection, intensity: Double = 1) -> some View {
        medxPage()
    }
}
