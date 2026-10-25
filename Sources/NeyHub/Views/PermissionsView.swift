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

    /// Ponto na sidebar: alguma permissão não opcional usada por um app instalado foi consultada e está negada.
    var missingPermission: Bool { permissionUsers.contains { !$0.permission.isOptional && granted[$0.permission] == false } }

    @MainActor func refreshPermissions() async {
        for (p, _) in permissionUsers {
            let v = await p.isGranted()
            if granted[p] != v { granted[p] = v } // só publica se mudou: senão o poll re-renderiza tudo a cada 2 s
        }
    }
}

/// Todas as permissões do sistema num lugar só: o NeyHub é o app estável, então concedeu uma vez, vale para sempre.
struct PermissionsView: View {
    @ObservedObject var model: HubModel

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
        // O SwiftUI cancela a task ao sair da tela: só consulta com ela visível.
        .task { while !Task.isCancelled { await model.refreshPermissions(); try? await Task.sleep(for: .seconds(2)) } }
    }

    private func row(_ p: Permission, apps: [String]) -> some View {
        let state = model.granted[p], ok = state == true
        return GCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Grafite.strong)
                        if p.isOptional { Text("opcional").font(.system(size: 10)).foregroundStyle(Grafite.label) }
                    }
                    Text("Usada por " + apps.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                }
                Spacer()
                Text(state == nil ? "Verificando…" : ok ? "Concedida" : "Falta conceder").font(.system(size: 11))
                    .foregroundStyle(ok ? Grafite.accent : Grafite.ghostText)
                if state == false {
                    GPill(title: "Conceder") { p.request(); NSWorkspace.shared.open(p.settingsURL) }
                        .accessibilityLabel("Conceder \(p.title)")
                }
            }
        }
    }
}
