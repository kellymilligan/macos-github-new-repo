import AppKit
import NewRepoCore
import ServiceManagement

@MainActor
final class NewRepoModel: ObservableObject {
    enum NameStatus: Equatable {
        case empty
        case invalid(String, suggestion: String?)
        case checking
        case available
        case taken
        case folderExists
        case unverified(String)
    }

    enum Phase: Equatable {
        case idle
        case creating
        case succeeded(name: String, path: URL)
        case failed(String)
    }

    private static let cloneDirectoryKey = "cloneDirectory"

    @Published var name = "" {
        didSet { if name != oldValue { nameDidChange() } }
    }
    @Published var isPublic = false
    @Published private(set) var cloneDirectory: URL {
        didSet { UserDefaults.standard.set(cloneDirectory.path, forKey: Self.cloneDirectoryKey) }
    }
    @Published private(set) var login: String?
    @Published private(set) var setupError: String?
    @Published private(set) var isSettingUp = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Bumped whenever the popover opens so the view can refocus the name field.
    @Published private(set) var openCount = 0

    private enum Availability: Equatable {
        case unknown, checking, available, taken
        case error(String)
    }

    @Published private var availability: Availability = .unknown
    private var cli: GitHubCLI?
    private var checkTask: Task<Void, Never>?

    init() {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if let saved = UserDefaults.standard.string(forKey: Self.cloneDirectoryKey),
           fileManager.fileExists(atPath: saved, isDirectory: &isDirectory), isDirectory.boolValue {
            cloneDirectory = URL(fileURLWithPath: saved)
        } else {
            let developer = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
            cloneDirectory = fileManager.fileExists(atPath: developer.path)
                ? developer
                : fileManager.homeDirectoryForCurrentUser
        }
        Task { await setUp() }
    }

    // MARK: - Derived state

    var destination: URL? {
        name.isEmpty ? nil : cloneDirectory.appendingPathComponent(name)
    }

    var nameStatus: NameStatus {
        switch RepoNameValidator.validate(name) {
        case .empty:
            return .empty
        case .invalid(let message):
            return .invalid(message, suggestion: RepoNameValidator.suggestion(for: name))
        case .valid:
            if let destination, FileManager.default.fileExists(atPath: destination.path) {
                return .folderExists
            }
            switch availability {
            case .unknown, .checking: return .checking
            case .available: return .available
            case .taken: return .taken
            case .error(let message): return .unverified(message)
            }
        }
    }

    var isCreating: Bool { phase == .creating }

    var canCreate: Bool {
        guard cli != nil, !isCreating else { return false }
        switch nameStatus {
        case .available, .unverified: return true
        default: return false
        }
    }

    // MARK: - Actions

    func popoverDidOpen() {
        openCount += 1
        if setupError != nil { Task { await setUp() } }
        // The destination folder may have appeared or disappeared since last time.
        objectWillChange.send()
    }

    func setUp() async {
        guard !isSettingUp else { return }
        isSettingUp = true
        defer { isSettingUp = false }

        guard let gh = await GitHubCLI.locate() else {
            setupError = "Couldn’t find the GitHub CLI. Install it with “brew install gh”, then try again."
            return
        }
        do {
            login = try await gh.currentUser()
            cli = gh
            setupError = nil
            checkAvailability()
        } catch {
            setupError = "gh couldn’t reach your account. Run “gh auth login” in Terminal, then try again.\n\n\(error.localizedDescription)"
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = cloneDirectory
        panel.prompt = "Choose"
        panel.message = "Choose where new repositories are cloned"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            cloneDirectory = url
        }
    }

    func create() {
        guard canCreate, let cli, let login, let destination else { return }
        let repoName = name
        let directory = cloneDirectory
        let isPublic = isPublic
        phase = .creating

        Task {
            do {
                try await cli.createRepository(owner: login, name: repoName, isPublic: isPublic, in: directory)
                name = ""
                self.isPublic = false
                phase = .succeeded(name: repoName, path: destination)
            } catch {
                phase = .failed(error.localizedDescription)
                // The repo may have been created even if cloning failed.
                checkAvailability()
            }
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func openOnGitHub(_ repoName: String) {
        guard let login, let url = URL(string: "https://github.com/\(login)/\(repoName)") else { return }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            phase = .failed("Couldn’t update login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Availability check

    private func nameDidChange() {
        if case .succeeded = phase, !name.isEmpty { phase = .idle }
        if case .failed = phase, !name.isEmpty { phase = .idle }
        checkAvailability()
    }

    private func checkAvailability() {
        checkTask?.cancel()
        availability = .unknown
        guard RepoNameValidator.validate(name) == .valid, let cli, let login else { return }

        let candidate = name
        availability = .checking
        checkTask = Task {
            // Debounce so we don't hit the API on every keystroke.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let result: Availability
            do {
                result = try await cli.repositoryExists(owner: login, name: candidate) ? .taken : .available
            } catch {
                result = .error(error.localizedDescription)
            }
            guard !Task.isCancelled, candidate == name else { return }
            availability = result
        }
    }
}
