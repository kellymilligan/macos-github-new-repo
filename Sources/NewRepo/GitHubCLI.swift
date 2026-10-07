import Foundation

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var errorMessage: String {
        if !stderr.isEmpty { return stderr }
        if !stdout.isEmpty { return stdout }
        return "Command failed with exit status \(status)"
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Apps launched from Finder don't inherit your shell's PATH, so look in the usual places.
enum Shell {
    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        NSHomeDirectory() + "/.local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func environment(extraPaths: [String] = []) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        env["PATH"] = (extraPaths + searchPaths + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }

    static func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment(extraPaths: [executable.deletingLastPathComponent().path])
                if let directory { process.currentDirectoryURL = directory }

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain both pipes concurrently so a full buffer on one can't block the process.
                let outBox = DataBox()
                let errBox = DataBox()
                let group = DispatchGroup()
                for (pipe, box) in [(stdout, outBox), (stderr, errBox)] {
                    group.enter()
                    DispatchQueue.global().async {
                        box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                }
                group.wait()
                process.waitUntilExit()

                func text(_ data: Data) -> String {
                    String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: text(outBox.data),
                    stderr: text(errBox.data)
                ))
            }
        }
    }
}

/// Thin wrapper around the `gh` CLI, which already holds your GitHub credentials.
struct GitHubCLI {
    let executable: URL

    static func locate() async -> GitHubCLI? {
        let fileManager = FileManager.default
        for directory in Shell.searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("gh")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return GitHubCLI(executable: candidate)
            }
        }

        // Fall back to asking the user's login shell, which knows about custom PATH setups.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let result = try? await Shell.run(URL(fileURLWithPath: shell), ["-l", "-c", "command -v gh"]),
           result.status == 0,
           let path = result.stdout.split(separator: "\n").last.map(String.init),
           fileManager.isExecutableFile(atPath: path) {
            return GitHubCLI(executable: URL(fileURLWithPath: path))
        }
        return nil
    }

    func currentUser() async throws -> String {
        let result = try await Shell.run(executable, ["api", "user", "--jq", ".login"])
        guard result.status == 0, !result.stdout.isEmpty else { throw CLIError(message: result.errorMessage) }
        return result.stdout
    }

    func repositoryExists(owner: String, name: String) async throws -> Bool {
        let result = try await Shell.run(executable, ["api", "repos/\(owner)/\(name)", "--jq", ".full_name"])
        if result.status == 0 {
            // A renamed repo redirects to its new name; the old name is free to reuse.
            return result.stdout.lowercased() == "\(owner)/\(name)".lowercased()
        }
        if result.stderr.contains("HTTP 404") { return false }
        throw CLIError(message: result.errorMessage)
    }

    /// Creates the repo on GitHub with a README on a `main` branch, then clones it into `directory/name`.
    func createRepository(owner: String, name: String, isPublic: Bool, in directory: URL) async throws {
        let create = try await Shell.run(
            executable,
            ["repo", "create", name, isPublic ? "--public" : "--private", "--add-readme"]
        )
        guard create.status == 0 else { throw CLIError(message: create.errorMessage) }

        // GitHub names the first branch from your account settings, so make sure it's `main`.
        let repo = "repos/\(owner)/\(name)"
        let defaultBranch = try await Shell.run(executable, ["api", repo, "--jq", ".default_branch"])
        guard defaultBranch.status == 0 else {
            throw CLIError(message: "Created \(name) but couldn’t read its default branch: \(defaultBranch.errorMessage)")
        }
        if defaultBranch.stdout != "main" {
            let rename = try await Shell.run(
                executable,
                ["api", "-X", "POST", "\(repo)/branches/\(defaultBranch.stdout)/rename", "-f", "new_name=main", "--silent"]
            )
            guard rename.status == 0 else {
                throw CLIError(message: "Created \(name) but couldn’t rename “\(defaultBranch.stdout)” to main: \(rename.errorMessage)")
            }
        }

        let clone = try await Shell.run(executable, ["repo", "clone", "\(owner)/\(name)"], in: directory)
        guard clone.status == 0 else {
            throw CLIError(message: "Created \(name) on GitHub but couldn’t clone it: \(clone.errorMessage)")
        }
    }
}
