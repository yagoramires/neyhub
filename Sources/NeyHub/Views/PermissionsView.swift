import AppKit
import Combine
import NeyKit
import SwiftUI

extension HubModel {
    /// Permissão → apps instalados que a pedem no manifest, na ordem de `Permission.allCases`.
    var permissionUsers: [(permission: Permission, apps: [String])] {
        let manifests = installed.values.sorted { $0.name < $1.name }
        return Permission.allCases.compactMap { p in
            let apps = manifests.filter { $0.permissions.contains(p) }.map(\.name)
            return apps.isEmpty ? nil : (p, apps)
        }
    }

    /// Ponto na sidebar: alguma permissão usada por um app instalado foi consultada e está negada.
    var missingPermission: Bool { permissionUsers.contains { granted[$0.permission] == false } }

    func refreshPermissions() async {
        for (p, _) in permissionUsers { granted[p] = await p.isGranted() }
    }
}

/// Todas as permissões do sistema num lugar só: o NeyHub é o app estável, então concedeu uma vez, vale para sempre.
struct PermissionsView: View {
    @ObservedObject var model: HubModel
    // Só existe com a tela visível: sair da rota remove a view e o timer.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissões").font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                    .accessibilityAddTraits(.isHeader)
                Text("Conceda aqui uma vez; os apps do NeyHub usam a mesma permissão.").font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            let users = model.permissionUsers
            if users.isEmpty {
                Text("Nenhum app instalado precisa de permissão.").font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            ForEach(users, id: \.permission) { u in row(u.permission, apps: u.apps) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await model.refreshPermissions() }
        .onReceive(tick) { _ in Task { await model.refreshPermissions() } }
    }

    private func row(_ p: Permission, apps: [String]) -> some View {
        let ok = model.granted[p] == true
        return GCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Grafite.strong)
                    Text("Usada por " + apps.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                }
                Spacer()
                Text(ok ? "Concedida" : "Falta conceder").font(.system(size: 11)).foregroundStyle(ok ? Grafite.accent : Grafite.ghostText)
                if !ok {
                    GPill(title: "Conceder") { p.request(); NSWorkspace.shared.open(p.settingsURL) }
                        .accessibilityLabel("Conceder \(p.title)")
                }
            }
        }
    }
}
