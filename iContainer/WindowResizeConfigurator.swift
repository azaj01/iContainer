import SwiftUI
import AppKit

/// Bridges an `NSWindow` so SwiftUI sheets can opt in to being resizable
/// and have a minimum size.
///
/// Embed an instance of this view anywhere inside a sheet. On the first
/// pass it walks up to the host window, sets `.resizable`, applies the
/// minimum size and (optionally) centres the window once. Subsequent
/// updates are cheap no-ops as long as nothing else moves the window.
struct WindowResizeConfigurator: NSViewRepresentable {
    let minSize: CGSize
    let shouldCenter: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(from: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(from: nsView, context: context)
    }

    private func configure(from view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = minSize
            if shouldCenter && !context.coordinator.didCenter {
                window.center()
                context.coordinator.didCenter = true
            }
        }
    }

    final class Coordinator {
        var didCenter = false
    }
}
