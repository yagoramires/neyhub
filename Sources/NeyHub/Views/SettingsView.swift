import NeyKit
import SwiftUI

/// Ajustes do próprio NeyHub: onde ele aparece. Os mesmos do menu "NeyHub" e do menu do ícone, à vista.
struct SettingsView: View {
    @ObservedObject var presence: HubPresenceController
    @ObservedObject var awake: AwakeModel

    var body: some View {
        let p = presence.presence
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ajustes").font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                    .accessibilityAddTraits(.isHeader)
                Text("Onde o NeyHub aparece. Dock e barra de menus nunca ficam os dois desligados.")
                    .font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            row("Ícone no Dock", note: "Com a janela fechada, o NeyHub continua no Dock.",
                isOn: Binding(get: { p.dock }, set: { presence.set(presence.presence.setting(dock: $0)) }))
            row("Ícone na barra de menus", note: "Abre o NeyHub e estes mesmos ajustes pela barra.",
                isOn: Binding(get: { p.menuBar }, set: { presence.set(presence.presence.setting(menuBar: $0)) }))
            row("Acordado na barra de menus", note: "Liga e desliga o Acordado sem abrir a janela.", isOn: $awake.showInMenuBar)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        GCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Grafite.strong)
                    Text(note).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                }
                Spacer()
                GSwitch(isOn: isOn, label: title)
            }
        }
    }
}
