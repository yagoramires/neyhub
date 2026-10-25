import ApplicationServices
import CoreGraphics
import Foundation
import UserNotifications

/// Permissões do sistema que só o NeyHub (um app estável e assinado) pede: o plugin nunca chama `request()`.
public enum Permission: String, Codable, CaseIterable {
    case accessibility, screenRecording, notifications

    public var title: String {
        switch self {
        case .accessibility: "Acessibilidade"
        case .screenRecording: "Gravação de Tela"
        case .notifications: "Notificações"
        }
    }

    public var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
    }

    public func isGranted() async -> Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .notifications:
            let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            return s == .authorized || s == .provisional
        }
    }

    /// Dispara o pedido do sistema (só funciona na primeira vez); a tela abre os Ajustes em seguida.
    public func request() {
        switch self {
        case .accessibility: _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        case .notifications: UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }
}
