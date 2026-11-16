import Foundation

/// A project's own logo (D55), found in its files: a logo or icon at the top, a web app's icon or favicon, an app's icon
/// set. Looked up once per project folder and kept (a project rarely changes its logo); nil when it has none.
public enum ProjectLogo {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// Places a logo usually sits, relative to a project folder or one of its repos, best first.
    static let candidates = [
        "logo.svg", "logo.png", "icon.png", "assets/logo.svg", "assets/logo.png", "assets/brand/logo.svg", "assets/brand/logo.png",
        "assets/icon.png", "assets/images/logo.png", "docs/logo.png", "Brand/AppIcon.png",
        "public/logo.svg", "public/logo.png", "public/apple-touch-icon.png", "public/icon.png", "public/favicon.svg", "public/favicon.png",
        "static/logo.png", "static/favicon.png", "src/app/icon.png", "app/icon.png", "src/assets/logo.png",
        "app/web/icons/Icon-512.png", "app/web/icons/Icon-192.png", "web/icons/Icon-512.png", "web/icons/Icon-192.png",
        "app/web/favicon.png", "web/favicon.png", "resources/icon.png",
    ]

    public static func find(root: String) -> String? {
        lock.lock()
        if let hit = cache[root] { lock.unlock(); return hit }
        lock.unlock()
        let found = search(root)
        lock.lock(); cache[root] = .some(found); lock.unlock()
        return found
    }

    static func search(_ root: String) -> String? {
        let fm = FileManager.default, base = URL(fileURLWithPath: root)
        guard fm.fileExists(atPath: root), root != NSHomeDirectory() else { return nil }
        // the folder itself, then its repos in code/
        var places = [base]
        let code = base.appendingPathComponent("code")
        places += ((try? fm.contentsOfDirectory(at: code, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        for place in places {
            for c in candidates {
                let u = place.appendingPathComponent(c)
                if fm.fileExists(atPath: u.path), (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 > 64 }) ?? false { return u.path }
            }
        }
        // an app's icon set, a few levels down (not in dependencies or builds)
        for place in places {
            if let icon = appIconSet(in: place) { return icon }
        }
        return nil
    }

    /// The largest picture in an AppIcon.appiconset within four levels of a folder.
    static func appIconSet(in folder: URL) -> String? {
        let fm = FileManager.default
        let skip: Set = ["node_modules", ".git", "build", ".build", "Pods", "DerivedData", ".dart_tool", "vendor"]
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        while let u = e.nextObject() as? URL {
            if skip.contains(u.lastPathComponent) || e.level > 5 { e.skipDescendants(); continue }
            guard u.lastPathComponent == "AppIcon.appiconset" else { continue }
            let pngs = ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.fileSizeKey])) ?? []).filter { $0.pathExtension == "png" }
            return pngs.max { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 }?.path
        }
        return nil
    }

    /// Forget what was found (a test, or after a project added its logo).
    public static func reset() { lock.lock(); cache = [:]; lock.unlock() }
}
