import Foundation

/// Folders as text, read the way they were written. A session file names its folders as its own system writes them:
/// `/Users/you/Projects/shop` on a Mac or Linux, `C:\Users\you\Projects\shop` on Windows. The Mac and Linux way is
/// left to Foundation, as before; the Windows way is read here, the same on every platform.
public enum PathText {
    /// Written the Windows way: on a drive (`C:\shop`, `c:/shop`, `C:`) or on a share (`\\server\share`).
    public static func isWindows(_ path: String) -> Bool {
        if path.hasPrefix(#"\\"#) { return true }
        let c = Array(path.unicodeScalars.prefix(3))
        guard c.count >= 2, c[0].isASCII, c[0].properties.isAlphabetic, c[1] == ":" else { return false }
        return c.count == 2 || c[2] == #"\"# || c[2] == "/"
    }

    /// The last folder or file of a path ("shop").
    public static func name(_ path: String) -> String {
        guard isWindows(path) else { return (path as NSString).lastPathComponent }
        return parts(path).last ?? String(windows(path).dropLast())
    }

    /// The folder a path is in. A drive or a share is its own parent.
    public static func parent(_ path: String) -> String {
        guard isWindows(path) else { return (path as NSString).deletingLastPathComponent }
        let p = windows(path), n = parts(p)
        guard let last = n.last else { return p }
        let up = String(p.dropLast(last.count))
        return n.count == 1 ? up : String(up.dropLast())
    }

    /// One spelling for a Windows folder: backslashes, the drive in capitals, no `.` or `..`, no slash at the end
    /// (a drive keeps its own: `C:\`).
    public static func windows(_ path: String) -> String {
        let flat = path.replacingOccurrences(of: "/", with: #"\"#)
        let share = flat.hasPrefix(#"\\"#)
        var words = flat.split(separator: #"\"#, omittingEmptySubsequences: true).map(String.init)
        // what a path starts with and never loses: `C:` or `\\server\share`
        let fixed = share ? min(2, words.count) : 1
        var kept: [String] = []
        for (k, w) in words.enumerated() {
            if k < fixed { kept.append(share ? w : w.uppercased()); continue }
            if w == "." { continue }
            if w == ".." { if kept.count > fixed { kept.removeLast() }; continue }
            kept.append(w)
        }
        words = kept
        if share { return #"\\"# + words.joined(separator: #"\"#) }
        return words.count == 1 ? words[0] + #"\"# : words.joined(separator: #"\"#)
    }

    /// The folders below the drive or the share.
    private static func parts(_ path: String) -> [String] {
        let p = windows(path)
        let words = p.split(separator: #"\"#, omittingEmptySubsequences: true).map(String.init)
        return Array(words.dropFirst(p.hasPrefix(#"\\"#) ? 2 : 1))
    }
}
