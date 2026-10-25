import Foundation

/// Onde o app aparece: janela (tela) e/ou barra de menus.
public struct Presence: Equatable {
    public var screen: Bool, menuBar: Bool

    public static func load(_ d: UserDefaults, hasScreen: Bool) -> Presence {
        Presence(screen: d.object(forKey: "presence.screen") as? Bool ?? hasScreen,
                 menuBar: d.object(forKey: "presence.menuBar") as? Bool ?? true)
    }

    public func save(_ d: UserDefaults) {
        d.set(screen, forKey: "presence.screen")
        d.set(menuBar, forKey: "presence.menuBar")
    }

    public func normalized(hasScreen: Bool) -> Presence {
        var p = self
        if !hasScreen { p.screen = false } else if !p.screen && !p.menuBar { p.menuBar = true }
        return p
    }
}
