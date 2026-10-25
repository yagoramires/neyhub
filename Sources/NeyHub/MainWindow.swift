import AppKit
import SwiftUI

enum MainWindow {
    static func make(model: HubModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x12 / 255, green: 0x13 / 255, blue: 0x15 / 255, alpha: 1)
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        window.setFrameAutosaveName("NeyHubMain")
        return window
    }
}
