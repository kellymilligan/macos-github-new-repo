import Foundation

public enum RepoNameValidation: Equatable {
    case empty
    case valid
    case invalid(String)
}

/// Mirrors GitHub's rules for repository names: ASCII letters, digits, `-`, `_` and `.`,
/// at most 100 characters, not `.` or `..`, and no `.git` suffix (GitHub strips it).
public enum RepoNameValidator {
    public static let maxLength = 100

    public static func validate(_ name: String) -> RepoNameValidation {
        if name.isEmpty { return .empty }
        if !name.unicodeScalars.allSatisfy(isAllowed) {
            return .invalid("Only letters, numbers, hyphens, underscores and periods are allowed")
        }
        if name.count > maxLength { return .invalid("Must be \(maxLength) characters or fewer") }
        if name == "." || name == ".." { return .invalid("“\(name)” is a reserved name") }
        if name.lowercased().hasSuffix(".git") { return .invalid("Can’t end with “.git”") }
        return .valid
    }

    /// A cleaned-up version of an invalid name, similar to what GitHub would suggest
    /// (e.g. "My Cool Repo!" -> "My-Cool-Repo"). Returns nil if there's nothing better to offer.
    public static func suggestion(for name: String) -> String? {
        var result = ""
        for scalar in name.unicodeScalars {
            if isAllowed(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty && !result.hasSuffix("-") {
                result.append("-")
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        while result.lowercased().hasSuffix(".git") {
            result.removeLast(4)
        }
        result = String(result.prefix(maxLength))
        guard result != name, validate(result) == .valid else { return nil }
        return result
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".": return true
        default: return false
        }
    }
}
