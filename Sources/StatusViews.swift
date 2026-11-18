import SwiftUI

/// Show every top-level component up to this count; beyond it only the affected ones.
private let maxComponentsShown = 8

struct StatusMenuView: View {
    @ObservedObject var model: StatusModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.enabledServices.isEmpty {
                Divider()
                Text("No services enabled. Add one in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.enabledServices) { service in
                Divider()
                ServiceSection(model: model, service: service, state: model.states[service.id] ?? ServiceState())
            }

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.iconName)
                .foregroundStyle(model.iconColor)
                .opacity(model.iconOpacity)
                .font(.system(size: 14, weight: .semibold))
            Text(model.label(for: model.indicator))
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let updated = model.states.values.compactMap(\.lastUpdated).max() {
                Text("Updated \(relative(updated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle("Notify on status changes", isOn: $model.notificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Refresh") {
                    Task { await model.poll() }
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ServiceSection: View {
    @ObservedObject var model: StatusModel
    let service: Service
    let state: ServiceState

    private var visibleComponents: [SummaryResponse.Component] {
        let shown = state.components.filter { $0.only_show_if_degraded != true || $0.status != "operational" }
        if shown.count <= maxComponentsShown { return shown }
        return shown.filter { $0.status != "operational" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                open(service.baseURL)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: service.symbol)
                        .foregroundStyle(model.color(for: state.indicator))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                    Text(service.name)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(state.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(service.id)")

            if let error = state.error {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            ForEach(state.incidents) { incident in
                Button {
                    open(incident.shortlink ?? service.baseURL)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(model.color(for: incident.impact ?? "minor"))
                            .font(.system(size: 9))
                        Text(incident.name)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Text(humanise(incident.status))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ForEach(visibleComponents) { component in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(model.colorForComponentStatus(component.status))
                        .font(.system(size: 7))
                    Text(component.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Text(humanise(component.status))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: StatusModel
    @State private var newURL = ""
    @State private var adding = false
    @State private var addError: String?

    var body: some View {
        Form {
            Section("Status pages") {
                ForEach($model.services) { $service in
                    HStack(spacing: 8) {
                        Toggle(isOn: $service.enabled) {
                            HStack(spacing: 8) {
                                Image(systemName: service.symbol).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(service.name)
                                    Text(service.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        if !service.isPreset {
                            Button {
                                model.remove(service)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("https://status.example.com", text: $newURL)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newURL.isEmpty || adding)
                    if adding { ProgressView().controlSize(.small) }
                }
                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Add a status page")
            } footer: {
                Text("Any page powered by Atlassian Statuspage (exposes /api/v2/summary.json).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify on status changes", isOn: $model.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func add() {
        guard !newURL.isEmpty, !adding else { return }
        adding = true
        addError = nil
        Task {
            do {
                try await model.addCustomService(newURL)
                newURL = ""
            } catch {
                addError = error.localizedDescription
            }
            adding = false
        }
    }
}

private func humanise(_ status: String) -> String {
    status.replacingOccurrences(of: "_", with: " ").capitalized
}
