import Foundation

enum BackupName {
    /// Local, readable date and time only. Stored at capture time, not recomputed
    /// when the user changes time zones or renames the backup later.
    static func timestamp(
        _ date: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendError.message("Enter a backup name.")
        }
        guard trimmed.count <= 120 else {
            throw BackendError.message("Keep the backup name to 120 characters or fewer.")
        }
        return trimmed
    }
}
