import Foundation
#if os(Windows)
import WinSDK
#endif

/// What differs between a Mac, Linux and Windows for the collector: where programs are and which processes live. The
/// Keychain and the certificate check are next to their own code (`Secrets`, `SiteProbe`).

/// Where the programs are that Meatproxy starts: claude, codex, gh, ssh. The usual places come first, because an app
/// started from the Finder has no shell PATH; then every folder on the PATH.
public enum Tools {
    /// How one system names and finds its programs.
    struct System: Equatable {
        /// between folders (`/` or `\`) and between the folders of a PATH (`:` or `;`)
        var slash: String, between: Character
        /// what a program's file may end in: nothing, or `.exe` and `.com` on Windows (a `.cmd` or `.bat` needs a
        /// shell to run, and Meatproxy starts programs directly, never through a shell)
        var endings: [String]
        /// where installers put command-line tools
        var usual: [String]

        static func unix(home: String) -> System {
            System(slash: "/", between: ":", endings: [""],
                   usual: ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local"])
        }
        /// `local`: %LOCALAPPDATA%, where Codex installs
        static func windows(home: String, local: String?) -> System {
            System(slash: #"\"#, between: ";", endings: [".exe", ".com"],
                   usual: [#"\#(home)\.local\bin"#] + (local.map { [#"\#($0)\Programs\OpenAI\Codex\bin"#] } ?? []))
        }
    }

    static var system: System {
        #if os(Windows)
        return .windows(home: NSHomeDirectory(), local: variable("LOCALAPPDATA", ProcessInfo.processInfo.environment))
        #else
        return .unix(home: NSHomeDirectory())
        #endif
    }

    /// A variable of the environment by name. Windows spells them as it likes (`Path`, `PATH`), so there any case counts.
    static func variable(_ name: String, _ env: [String: String]) -> String? {
        if let v = env[name] { return v }
        #if os(Windows)
        return env.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        #else
        return nil
        #endif
    }

    /// Every file `name` could be, in the order it is looked for: the usual places, then the PATH's folders.
    static func candidates(_ name: String, path: String?, on system: System) -> [String] {
        let folders = (path ?? "").split(separator: system.between).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        var seen = Set<String>(), out: [String] = []
        for folder in system.usual + folders where !folder.isEmpty && seen.insert(folder).inserted {
            let base = folder.hasSuffix(system.slash) ? folder + name : folder + system.slash + name
            // a name that already says what it is ("ssh.exe") is taken as it is
            let named = system.endings.contains { !$0.isEmpty && name.lowercased().hasSuffix($0) }
            out += named ? [base] : system.endings.map { base + $0 }
        }
        return out
    }

    /// Where a program is, or nil when it is not installed.
    public static func find(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        candidates(name, path: variable("PATH", environment), on: system).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// ssh and its helpers (ssh-add): the system's own. On Windows that is OpenSSH in System32, the one that reaches
    /// the Windows ssh-agent; the ssh that comes with Git does not.
    public static func ssh(_ name: String = "ssh", environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        #if os(Windows)
        let root = variable("SystemRoot", environment) ?? #"C:\Windows"#
        let own = #"\#(root)\System32\OpenSSH\\#(name).exe"#
        #else
        let own = "/usr/bin/\(name)"
        #endif
        if FileManager.default.isExecutableFile(atPath: own) { return own }
        return find(name, environment: environment) ?? own
    }

    /// The PATH for a process Meatproxy starts: the usual tool folders in front of your own. Windows programs are
    /// found through the PATH they already have, so there it stays as it is.
    public static func searchPath(_ environment: [String: String]) -> String? {
        #if os(Windows)
        return variable("PATH", environment)
        #else
        return ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", NSHomeDirectory() + "/.local/bin", environment["PATH"] ?? ""].joined(separator: ":")
        #endif
    }

    /// Puts `searchPath` into an environment.
    static func addSearchPath(to environment: inout [String: String]) {
        #if os(Windows)
        _ = environment
        #else
        environment["PATH"] = searchPath(environment)
        #endif
    }
}

/// The processes on this machine: the ones Meatproxy starts, and whether the one a lock file names still lives.
public enum Processes {
    /// Starts a process that can be stopped again. On Linux a process inherits the signals its starting thread has
    /// blocked, and a background thread blocks nearly all of them: started from there it would never hear
    /// `terminate()`, so a run could not be stopped, taken over or timed out. Here it starts with nothing blocked.
    /// (Foundation on macOS does that itself, and Windows has no signals.)
    public static func start(_ process: Process) throws {
        #if os(Linux)
        var none = sigset_t(), before = sigset_t()
        sigemptyset(&none)
        pthread_sigmask(SIG_SETMASK, &none, &before)
        defer { pthread_sigmask(SIG_SETMASK, &before, nil) }
        #endif
        try process.run()
    }

    /// this process's id
    public static var own: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// A process with this id is running.
    public static func isAlive(_ pid: Int32) -> Bool {
        #if os(Windows)
        // PROCESS_QUERY_LIMITED_INFORMATION; a process that ended keeps its id until its last handle closes, so ask
        // for its exit code too: 259 (STILL_ACTIVE) means it runs
        guard pid > 0, let handle = OpenProcess(DWORD(0x1000), false, DWORD(pid)) else { return false }
        defer { _ = CloseHandle(handle) }
        var code: DWORD = 0
        return GetExitCodeProcess(handle, &code) && code == 259
        #else
        return kill(pid, 0) == 0
        #endif
    }
}
