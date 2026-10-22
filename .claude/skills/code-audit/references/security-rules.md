# Security rules — LibreScreen code audit

**Scope.** LibreScreen is a local-only screen recorder: no App Sandbox, hardened runtime on, exactly two entitlements (camera, audio input), zero networking, zero telemetry. Every byte it produces lands in a folder the user chose; every byte it reads comes from the screen, the camera, the microphone and its own `UserDefaults`. This checklist covers what keeps that contract true: entitlement minimalism, absence of network and process-spawning code, safe file-system handling, clipboard and logging hygiene, trustworthy settings, honest privacy strings and a dependency-free supply chain. Apply to the whole Swift tree plus `*.entitlements`, `Info.plist`, `project.pbxproj` and the CI configuration.

## 1. **Hardened runtime stays on and the entitlements file contains exactly two keys**

Hardened runtime blocks code injection, DYLD environment variables and unsigned executable memory; each extra entitlement (`allow-jit`, `disable-library-validation`, network client, file access) widens what a compromised process can do. With no sandbox, the entitlements file is the only machine-readable statement of what the app is allowed to touch.

Grep: `<key>com\.apple\.security\.` in `*.entitlements` (expect only `device.camera` and `device.audio-input`); `ENABLE_HARDENED_RUNTIME = NO|allow-jit|disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory|security\.network|security\.files` in `project.pbxproj`.

Wrong:
```xml
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>   <!-- any dylib may load -->
<key>com.apple.security.network.client</key><true/>                 <!-- there is no network code -->
```
Right:
```xml
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
```
Verify the built product, not only the source: `codesign -d --entitlements :- LibreScreen.app` and `codesign -dv --verbose=2 LibreScreen.app 2>&1 | grep -i runtime`.

## 2. **No networking code at all**

The privacy promise is "nothing leaves the Mac". One `URLSession` call for an update check makes the app a network client, triggers firewall prompts and falsifies the README and the privacy label.

Grep: `URLSession|URLRequest|NWConnection|NWListener|NWBrowser|import Network|CFSocket|CFStream|NSURLConnection|NetService|SCNetworkReachability|CFHTTPMessage|WKWebView`; `https?://` outside comments and the single hard-coded project URL.

Wrong:
```swift
func checkForUpdates() async throws {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.org/latest.json")!)
    latestVersion = try JSONDecoder().decode(Release.self, from: data).version
}
```
Right:
```swift
// LibreScreen has no network code. The only outbound action is user-initiated and handled by the browser:
@MainActor func openProjectPage() { NSWorkspace.shared.open(Self.projectURL) }   // fixed, hard-coded URL
```

## 3. **No telemetry, analytics or crash uploaders**

Telemetry is networking plus data collection; even "anonymous" counters change the privacy label and need consent UI the app does not have. Diagnostics stay local: `os.Logger`, signposts and the macOS crash reports the user can share by hand.

Grep: `Analytics|Crashlytics|Sentry|Firebase|Mixpanel|Amplitude|Bugsnag|AppCenter|TelemetryDeck|MXMetricManager|MetricKit|CKContainer`.

Wrong:
```swift
MXMetricManager.shared.add(self)                              // collects usage/crash payloads
Analytics.track("recording_started", ["fps": settings.fps])
```
Right:
```swift
private static let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Recording")
Self.log.info("Recording started fps=\(settings.fps, privacy: .public)")   // local unified log only
```

## 4. **No `Process`/`NSTask`/`posix_spawn`, no shell, no dynamic code loading**

Spawning processes or loading bundles at runtime turns any file-name or settings bug into code execution, which hardened runtime and notarisation exist to rule out. Everything the app needs (encoding, muxing, thumbnails, revealing files) exists as a framework API.

Grep: `Process\(|NSTask|posix_spawn|\bsystem\(|execv|execl|popen\(|dlopen|dlsym|NSAppleScript|osascript|Bundle\([^)]*\)\.load\(|CFBundleLoadExecutable|NSClassFromString\(`.

Wrong:
```swift
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
p.arguments = ["-R", output.path]                             // shell-out; path becomes an argument
try p.run()
```
Right:
```swift
NSWorkspace.shared.activateFileViewerSelecting([output])      // reveal in Finder through the framework
```

## 5. **File names derived from window titles, app names or dates are sanitised**

Window titles are attacker-controlled text (a web page sets its own title). `/`, `:`, control characters, leading dots and over-long names produce files in the wrong folder, hidden files, or write failures that lose the recording.

Grep: `appendingPathComponent\(".*\\\(`; `appendingPathComponent\(\w*(title|Title|name|Name)`; `\.mov"` with interpolation.

Wrong:
```swift
let url = outputDir.appendingPathComponent("\(window.title ?? "Recording") \(Date()).mov")
```
Right:
```swift
static func safeFileName(_ raw: String, ext: String) -> String {
    let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
    var name = raw.components(separatedBy: banned).joined(separator: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty || name.hasPrefix(".") { name = "Recording" }
    return String(name.prefix(120)) + "." + ext
}
```

## 6. **Output paths are resolved and checked to stay inside the chosen folder; symlinks are not followed blindly**

Even with sanitised names, a stored folder path can point at a symlink or be edited in `UserDefaults` to a `..`-style value; writing through an unexpected link can clobber files elsewhere. Resolve both ends and compare before every write.

Grep: `URL\(fileURLWithPath: (settings|defaults)`; `resolvingSymlinksInPath|standardizedFileURL|isSymbolicLinkKey` (expected near every write).

Wrong:
```swift
let dest = URL(fileURLWithPath: defaults.string(forKey: "outputDir")!).appendingPathComponent(fileName)
try FileManager.default.moveItem(at: temp, to: dest)          // follows whatever the folder became
```
Right:
```swift
func destination(in dir: URL, fileName: String) throws -> URL {
    let base = dir.resolvingSymlinksInPath().standardizedFileURL
    let target = base.appendingPathComponent(fileName).standardizedFileURL
    guard target.deletingLastPathComponent() == base else { throw OutputError.escapesFolder }
    if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
        throw OutputError.refusesSymlink
    }
    return target
}
```

## 7. **Writes are atomic and never overwrite without intent**

A crash or power loss mid-write must not leave a half-written file in the user's folder, and two recordings started in the same second must not clobber each other. Small files use `.atomic`; recordings are written by `AVAssetWriter` into a `.part` file on the *same volume* as the destination and then renamed once, which is atomic.

Grep: `\.write\(to:` without `options:`; `removeItem\(at:` immediately followed by `moveItem`; `copyItem\(at:` used for the final move; `AVAssetWriter\(outputURL: .*temporaryDirectory` when the destination may be on another volume.

Wrong:
```swift
try pngData.write(to: dest)                                   // partial file on crash
try? FileManager.default.removeItem(at: dest)                 // delete-then-move: window with no file
try FileManager.default.moveItem(at: temp, to: dest)
```
Right:
```swift
try pngData.write(to: dest, options: [.atomic, .withoutOverwriting])
// recordings: scratch directory on the destination volume, then one rename
let scratch = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: dest.deletingLastPathComponent(), create: true)
let part = scratch.appendingPathComponent(dest.lastPathComponent + ".part")
// … AVAssetWriter(outputURL: part, fileType: .mov) … await writer.finishWriting() …
try FileManager.default.moveItem(at: part, to: dest)          // same volume => rename(2); dest is unique
```

## 8. **Temporary files live in a private subfolder of `FileManager.default.temporaryDirectory` and are removed on every exit path**

`/tmp` is shared and predictable; the per-user temp directory is private to the user. Leftovers from crashes are multi-gigabyte movies, so failure paths and a launch-time sweep matter as much as the happy path.

Grep: `"/tmp|NSTemporaryDirectory\(\)|/var/tmp`; `temporaryDirectory` in a function without `removeItem` or `defer`.

Wrong:
```swift
let temp = URL(fileURLWithPath: "/tmp/librescreen-\(UUID()).mov")   // shared dir, never cleaned
```
Right:
```swift
let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("LibreScreen-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: workDir) }   // runs on success, throw and cancellation
// at launch: remove "LibreScreen-*" folders older than 24 h left behind by crashes
```

## 9. **Only the user-chosen output folder (and temp) are ever written; no silent fallbacks**

Without a sandbox the app *can* write anywhere, so the discipline lives in code review. Falling back to `~/Desktop` or `~/Movies` when the saved folder is missing hides recordings from the user and may write into a folder they deliberately moved away from.

Grep: `homeDirectoryForCurrentUser|NSHomeDirectory\(\)|fileURLWithPath: "/Users|fileURLWithPath: "~|desktopDirectory|moviesDirectory` anywhere except the folder picker's initial default.

Wrong:
```swift
let dir = savedOutputDir.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")   // silent
```
Right:
```swift
guard let dir = savedOutputDir, FileManager.default.isWritableFile(atPath: dir.path) else {
    throw OutputError.folderUnavailable      // ViewModel shows the error and offers "Choose Folder…"
}
```

## 10. **Clipboard: `clearContents()` before writing; never read without a user action**

Writing without clearing leaves stale types on the pasteboard and `writeObjects` can fail silently. Reading the general pasteboard at launch or on a timer exposes whatever the user last copied (passwords, tokens) to a process with no reason to see it, and newer macOS versions can show a paste alert for programmatic reads.

Grep: `NSPasteboard\.general\.(string|data|readObjects|pasteboardItems|propertyList)\(|pasteboard\.types` (expect none); `writeObjects\(|setData\(|setString\(` not preceded by `clearContents\(\)`.

Wrong:
```swift
NSPasteboard.general.writeObjects([image])                      // no clearContents
if let s = NSPasteboard.general.string(forType: .string) { … }  // read at launch, no user intent
```
Right:
```swift
@MainActor func copyToClipboard(_ image: NSImage) {   // called only from the Copy button / hotkey
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([image])
}
```

## 11. **Logging goes through `os.Logger`; paths, window titles, app and device names are `.private`; no `print`**

`print`/`NSLog` write unredacted text to stdout and the unified log, where any local process or a shared sysdiagnose can read it. `Logger` redacts interpolated strings unless marked `.public`; mark sensitive values `.private` explicitly so a later "make it public" edit is visible in review.

Grep: `\bprint\(|NSLog\(|debugPrint\(|dump\(|os_log\(` (expect none); `Logger.*\\\((url|path|title|name|displayName|localizedName)` without `privacy:`; `privacy: \.public` next to any string value.

Wrong:
```swift
print("Saved to \(url.path)")
logger.info("Capturing \(window.title ?? "") from \(app.applicationName)")   // relies on defaults
```
Right:
```swift
private static let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Capture")
Self.log.info("Saved to \(url.path, privacy: .private)")
Self.log.info("Capturing id=\(window.windowID, privacy: .public) title=\(window.title ?? "", privacy: .private)")
```

## 12. **`UserDefaults` holds settings only: no secrets, no history of what was recorded**

`~/Library/Preferences/<bundle id>.plist` is readable by every process running as the user and ends up in backups. Window titles, app names and file lists are a record of the user's activity; "permission granted" flags go stale after a rebuild (see `permissions-rules.md`).

Grep: `UserDefaults\.standard\.set\(|@AppStorage\("` — list every key and flag `title|history|recent|token|key|password|secret|granted|authorized`.

Wrong:
```swift
defaults.set(window.title, forKey: "lastWindowTitle")
defaults.set(true, forKey: "screenRecordingGranted")
```
Right:
```swift
// keys: fps, codec, quality, outputDirectory (path), showCamera, microphoneEnabled, hotKeys, countdownSeconds
defaults.set(settings.fps, forKey: Key.fps)
// recent recordings: at most 10 file URLs, no titles, cleared when the user clears them
```

## 13. **Settings loaded from disk are untrusted: clamp and validate before they reach the pipeline**

Anyone (or any buggy script) can `defaults write` the plist. A zero or negative fps produces an invalid `CMTime`, an absurd bitrate or dimension allocates gigabytes or crashes the encoder, and an unknown codec raw value traps on `!`.

Grep: `integer\(forKey:|double\(forKey:|string\(forKey:` used directly in `SCStreamConfiguration|AVAssetWriterInput|CMTime\(`; `\(rawValue: .*\)!`.

Wrong:
```swift
config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(defaults.integer(forKey: "fps")))   // 0 -> invalid
config.width = defaults.integer(forKey: "width")                                                     // 0 or 10^9
let codec = Codec(rawValue: defaults.string(forKey: "codec")!)!
```
Right:
```swift
static let fpsRange = 1...60, bitrateRange = 500_000...80_000_000, sideRange = 16...8192
func clamp<T: Comparable>(_ v: T, to r: ClosedRange<T>, or d: T) -> T { r.contains(v) ? v : d }
let fps = clamp(defaults.integer(forKey: Key.fps), to: Self.fpsRange, or: 30)
let width = clamp(defaults.integer(forKey: Key.width), to: Self.sideRange, or: 1920) & ~1   // even for H.264/HEVC
let codec = Codec(rawValue: defaults.string(forKey: Key.codec) ?? "") ?? .hevc
```

## 14. **Info.plist usage strings exist for exactly the capabilities used and describe them honestly**

Touching the camera or microphone without `NSCameraUsageDescription`/`NSMicrophoneUsageDescription` terminates the app. A vague or exaggerated string misleads the user and fails review; a usage string for a capability the app does not use (location, contacts, Apple Events) signals code that should not exist.

Grep: `UsageDescription` in `Info.plist` and `INFOPLIST_KEY_\w+UsageDescription` in `project.pbxproj`; compare the set with `requestAccess\(for:` call sites.

Wrong:
```xml
<key>NSCameraUsageDescription</key><string>This app needs camera access.</string>
<key>NSAppleEventsUsageDescription</key><string>Automation</string>   <!-- nothing sends Apple Events -->
```
Right:
```xml
<key>NSCameraUsageDescription</key>
<string>LibreScreen shows your camera in a small bubble over the recording. The camera is used only while you keep it turned on.</string>
<key>NSMicrophoneUsageDescription</key>
<string>LibreScreen records your voice when you enable the microphone for a recording. Audio is saved only to the file you choose.</string>
```

## 15. **Zero third-party runtime dependencies; build tools pinned in CI**

Every package is code that runs inside the hardened, notarised process with the camera entitlement; a compromised or abandoned package becomes the app's problem. Unpinned CI tools make builds non-reproducible and let a toolchain change alter the binary silently.

Grep: `XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference` in `project.pbxproj`; `Package\.swift|Package\.resolved|Podfile|Cartfile|\.xcframework`; imports outside the Apple set: `rg -n '^import ' --glob '*.swift' | grep -vE 'import (Foundation|AppKit|SwiftUI|AVFoundation|ScreenCaptureKit|CoreImage|CoreMedia|CoreVideo|Vision|Metal|MetalKit|Carbon|os|Observation|Synchronization|UniformTypeIdentifiers|CoreGraphics|QuartzCore|CoreAudio|AudioToolbox|VideoToolbox|Darwin|Testing|XCTest)'`; in CI: `uses: .*@(main|master|v\d+)$`, `xcode-version: latest`.

Wrong:
```swift
import HotKey                      // SPM package for global shortcuts
import KeyboardShortcuts
```
Right:
```swift
import Carbon.HIToolbox            // own RegisterEventHotKey wrapper in Infrastructure/HotKeys
// CI: Xcode chosen by explicit version, SwiftLint/swift-format by version, actions pinned to a commit SHA
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | Data can leave the Mac, code can be executed or loaded dynamically, the app's privilege surface grows, or user files outside the chosen folder can be read or written | Any networking or telemetry call (#2, #3); `Process`/`dlopen`/AppleScript (#4); extra entitlement or hardened runtime off (#1); unsanitised name or unresolved path reaching a write (#5, #6); pasteboard read without a user action (#10); secrets or activity history in `UserDefaults` (#12) |
| Medium | A recording or setting can be lost or corrupted, or private details reach a log or a shared location, without crossing a trust boundary | Non-atomic or overwriting writes (#7); temp files not removed on failure paths (#8); silent output-folder fallback (#9); unclamped settings that can crash the encoder (#13); `print`/`NSLog` of paths or titles (#11); missing usage string for a device that is used (#14); unpinned CI toolchain (#15) |
| Low | Hygiene issues with no exploit path and no data loss | `.public` on harmless numerics or `print` of constants (#11); usage string wording (#14); unused but harmless Info.plist key; missing launch-time temp sweep when per-run cleanup exists (#8) |
