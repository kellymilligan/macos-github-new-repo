import SwiftUI

struct ContentView: View {
    @ObservedObject var model: NewRepoModel
    let close: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New repository")
                .font(.headline)

            if let error = model.setupError {
                setupErrorView(error)
            } else if model.login == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to GitHub…").foregroundStyle(.secondary)
                }
            } else {
                form
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { nameFocused = true }
        .onChange(of: model.openCount) { _ in nameFocused = true }
        .onExitCommand(perform: close)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let login = model.login {
                        Text("\(login) /").foregroundStyle(.secondary)
                    }
                    TextField("repository-name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .disabled(model.isCreating)
                        .onSubmit(model.create)
                    statusIcon
                        .frame(width: 16, height: 16)
                }
                nameHint
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Clone into").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(displayPath(model.cloneDirectory))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(model.cloneDirectory.path)
                    Spacer(minLength: 4)
                    Button("Choose…", action: model.chooseFolder)
                        .disabled(model.isCreating)
                }
            }

            Toggle("Make public", isOn: $model.isPublic)
                .toggleStyle(.checkbox)
                .disabled(model.isCreating)
                .help("New repositories are private unless this is checked")

            Button(action: model.create) {
                HStack(spacing: 6) {
                    if model.isCreating {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.isCreating ? "Creating…" : createLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canCreate)

            result
        }
    }

    private var createLabel: String {
        model.isPublic ? "Create Public Repo & Clone" : "Create Private Repo & Clone"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.nameStatus {
        case .empty:
            Color.clear
        case .checking:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unverified:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .invalid, .taken, .folderExists:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var nameHint: some View {
        switch model.nameStatus {
        case .empty:
            Text("Letters, numbers, hyphens, underscores and periods.")
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking availability…").foregroundStyle(.secondary)
        case .available:
            Text("Available").foregroundStyle(.green)
        case .taken:
            Text("You already have a repository with this name.").foregroundStyle(.red)
        case .folderExists:
            Text("A folder with this name already exists there.").foregroundStyle(.red)
        case .unverified(let message):
            Text("Couldn’t check availability: \(message)").foregroundStyle(.orange)
        case .invalid(let message, let suggestion):
            VStack(alignment: .leading, spacing: 2) {
                Text(message).foregroundStyle(.red)
                if let suggestion {
                    Button("Use “\(suggestion)” instead") { model.name = suggestion }
                        .buttonStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle, .creating:
            EmptyView()
        case .succeeded(let name, let path):
            VStack(alignment: .leading, spacing: 6) {
                Label("Created and cloned to \(displayPath(path))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                HStack {
                    Button("Finder") { model.revealInFinder(path) }
                    Button("Terminal") { model.openInTerminal(path) }
                    Button("GitHub") { model.openOnGitHub(name) }
                }
                .controlSize(.small)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Other sections

    private func setupErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { Task { await model.setUp() } }
                .disabled(model.isSettingUp)
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
