import Foundation

enum UpdateInstaller {
    enum Method: Equatable {
        case homebrew(brew: String, cask: String)
        case github

        var label: String {
            switch self {
            case .homebrew: return "Homebrew"
            case .github: return "GitHub"
            }
        }
    }

    static var caskName: String? {
        switch Channel.current {
        case .stable: return "coppice"
        case .nightly: return "coppice-nightly"
        case .dev: return nil
        }
    }

    static func method(fileManager: FileManager = .default) -> Method {
        guard let cask = caskName else { return .github }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let brew = "\(prefix)/bin/brew"
            if fileManager.isExecutableFile(atPath: brew), fileManager.fileExists(atPath: "\(prefix)/Caskroom/\(cask)") {
                return .homebrew(brew: brew, cask: "rafay99-epic/apps/\(cask)")
            }
        }
        return .github
    }

    static func start(version: String, assetURL: URL, method: Method) throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "coppice-update-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        var brew = ""
        var cask = ""
        if case .homebrew(let path, let token) = method {
            brew = path
            cask = token
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            file.path,
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath,
            version,
            assetURL.absoluteString,
            Log.shared.logFileURL.path,
            brew,
            cask,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static let script = #"""
    pid="$1"; app="$2"; version="$3"; url="$4"; log="$5"; brew="$6"; cask="$7"; relaunch="${8:-1}"
    out="$(dirname "$log")/update.log"
    say() { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$log"; }
    version_of() { /usr/bin/defaults read "$1/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null; }
    installed() { [ "$(version_of "$app")" = "$version" ]; }
    while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
    printf '\n== %s update to %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$version" >> "$out"
    if [ -n "$brew" ]; then
      say "update: brew upgrade --cask $cask"
      if ! { "$brew" update && HOMEBREW_NO_AUTO_UPDATE=1 "$brew" upgrade --cask "$cask"; } >> "$out" 2>&1; then
        say "ERROR  Homebrew could not upgrade $cask, trying GitHub. Details in update.log"
      fi
    fi
    if ! installed; then
      say "update: downloading $url"
      work="$(mktemp -d)"
      if /usr/bin/curl -fsSL --retry 2 "$url" -o "$work/update.dmg" >> "$out" 2>&1 \
        && /usr/bin/hdiutil attach "$work/update.dmg" -nobrowse -noautoopen -readonly -mountpoint "$work/mnt" >> "$out" 2>&1; then
        source="$work/mnt/$(basename "$app")"
        if [ "$(version_of "$source")" = "$version" ] && /usr/bin/codesign --verify --deep "$source" >> "$out" 2>&1; then
          rm -rf "$app.old"
          if mv "$app" "$app.old" && /usr/bin/ditto "$source" "$app" >> "$out" 2>&1; then
            rm -rf "$app.old"
          else
            rm -rf "$app"
            mv "$app.old" "$app"
          fi
        else
          say "ERROR  the downloaded image is not a valid $version"
        fi
        /usr/bin/hdiutil detach "$work/mnt" -force >> "$out" 2>&1
      fi
      rm -rf "$work"
    fi
    if installed; then
      say "updated to $version"
    else
      say "ERROR  update to $version failed. Details in update.log"
    fi
    if [ "$relaunch" = 1 ]; then /usr/bin/open "$app"; fi
    """#
}
