import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import UserNotifications

/// Permissões do sistema que só o NeyHub (um app estável e assinado) pede: o plugin nunca chama `request()`.
public enum Permission: String, Codable, CaseIterable {
    case accessibility, screenRecording, notifications, microphone

    public var title: String {
        switch self {
        case .accessibility: "Acessibilidade"
        case .screenRecording: "Gravação de Tela"
        case .notifications: "Notificações"
        case .microphone: "Microfone"
        }
    }

    /// Só alguns usos do app precisam (o Microfone do Capture): tem linha em Permissões, mas não acende o ponto.
    public var isOptional: Bool { self == .microphone }

    public var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
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
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// Dispara o pedido do sistema (só funciona na primeira vez); a tela abre os Ajustes em seguida.
    public func request() {
        switch self {
        case .accessibility: _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        case .notifications: UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in } // os Ajustes quem abre é a tela (abrir aqui abria duas vezes)
        }
    }
}
