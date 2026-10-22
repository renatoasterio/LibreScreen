# Permissions rules — LibreScreen code audit

**Scope.** How LibreScreen asks for, checks and reacts to the three TCC permissions it needs — Screen Recording (`CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess`), Camera and Microphone (`AVCaptureDevice.authorizationStatus(for:)`/`requestAccess(for:)`) — and how it keeps capture devices off when a feature is off. The non-negotiable rules: permissions are requested only inside `Infrastructure/Permissions/PermissionsService.swift`, only in response to a user action (turning on the camera, enabling the microphone, pressing Record), never at launch; no capture session starts before its status is `.authorized`; the app never records its own panels; it never needs Accessibility or Input Monitoring. Apply to `Infrastructure/Permissions`, the capture and camera services, the ViewModels that trigger those features, `Info.plist` and the entitlements file.

## 1. **All TCC calls live in `PermissionsService.swift`; the rest of the app uses the Domain protocol**

One choke point makes "never at launch" auditable with a single grep and keeps AVFoundation and CoreGraphics out of `Features/` and `Domain/`. ViewModels talk to `PermissionsServiceProtocol` and see a Domain `PermissionStatus`, never `AVAuthorizationStatus`.

Grep: `CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AVCaptureDevice\.(authorizationStatus|requestAccess)` — every hit outside `Infrastructure/Permissions/PermissionsService.swift` is a finding; `AVAuthorizationStatus` anywhere in `Domain/` or `Features/`.

Wrong:
```swift
// Features/Recorder/RecorderViewModel.swift
func cameraToggled(_ on: Bool) async {
    guard await AVCaptureDevice.requestAccess(for: .video) else { return }   // TCC from a ViewModel
}
```
Right:
```swift
// Domain/Permissions/PermissionsServiceProtocol.swift
enum Capability: Sendable { case screenRecording, camera, microphone }
enum PermissionStatus: Sendable { case notDetermined, authorized, denied, restricted }
protocol PermissionsServiceProtocol: Sendable {
    func status(of capability: Capability) -> PermissionStatus
    func request(_ capability: Capability) async -> PermissionStatus   // prompts only when .notDetermined
}
```

## 2. **Check the status first; request only when `.notDetermined`; never re-prompt**

`requestAccess` returns `false` immediately when the status is already `.denied`, so a caller that only looks at the Bool tells a user who declined weeks ago that they "just declined". `CGRequestScreenCaptureAccess()` also returns `false` right after *showing* the prompt, which is not a denial. Screen Recording has no `.restricted`/`.notDetermined` distinction in the API: derive `.notDetermined` from "preflight is false and we have not prompted in this launch". Any API that enumerates shareable content (`SCShareableContent`, `CGWindowListCopyWindowInfo` with names) triggers the Screen Recording prompt by itself, so it counts as a request.

Grep: `requestAccess\(for:` without `authorizationStatus\(for:` in the same function; `SCShareableContent\.(current|excludingDesktopWindows|getExcludingDesktopWindows)|CGWindowListCopyWindowInfo` outside the capture-start path.

Wrong:
```swift
func request(_ c: Capability) async -> PermissionStatus {
    CGRequestScreenCaptureAccess() ? .authorized : .denied       // false == prompt shown OR denied
}
```
Right:
```swift
func request(_ c: Capability) async -> PermissionStatus {
    let current = status(of: c)
    guard current == .notDetermined else { return current }        // caller shows guidance for denied/restricted
    switch c {
    case .camera:     return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    case .microphone: return await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
    case .screenRecording:
        _ = CGRequestScreenCaptureAccess()                          // shows the system prompt once
        return CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined   // re-checked on activation
    }
}
```

## 3. **Requests happen only inside a user action, never at launch, `init`, `onAppear` or `.task`**

A prompt the user did not cause is the top reason screen recorders get denied, and on recent macOS the denial is sticky and confusing (rule 4). Pressing Record asks for Screen Recording (and Microphone if enabled); turning on the camera asks for Camera; nothing else asks for anything.

Grep: `applicationDidFinishLaunching|applicationWillFinishLaunching|init\(\)|\.onAppear|\.task \{|@main` in files that also contain `permissions\.request|request\(\.(camera|microphone|screenRecording)\)`.

Wrong:
```swift
func applicationDidFinishLaunching(_ note: Notification) {
    Task { _ = await permissions.request(.screenRecording); _ = await permissions.request(.camera) }
}
```
Right:
```swift
// RecorderViewModel (@MainActor)
func recordTapped() async {
    guard await permissions.request(.screenRecording) == .authorized else { guidance = .screen; return }
    if settings.microphoneEnabled, await permissions.request(.microphone) != .authorized { guidance = .mic; return }
    await recorder.start(settings)
}
func cameraToggled(_ on: Bool) async {   // asks for the camera only, and only when turning it on
    guard on else { await camera.stop(); return }
    guard await permissions.request(.camera) == .authorized else { guidance = .camera; return }
    await camera.start()
}
```

## 4. **Never cache "authorized"; ad-hoc signed builds lose TCC grants on every rebuild**

TCC keys its decision to the app's code-signing identity. An ad-hoc signature (`Signature=adhoc` in `codesign -dv`) changes with every build, so a Debug build granted yesterday can be unauthorised today while System Settings still shows the toggle on. macOS 15 additionally re-asks screen-recording apps periodically. Code must ask the system every time and treat a stale `.denied` as recoverable.

Grep: `@AppStorage\(".*(granted|authorized|permission)|forKey: ".*(granted|authorized)"|static var (isAuthorized|hasPermission)`.

Wrong:
```swift
@AppStorage("screenRecordingGranted") var granted = false
func recordTapped() { if granted { start() } else { request() } }   // stale after a rebuild
```
Right:
```swift
func recordTapped() async {                 // ask TCC every time: cheap and always correct
    guard await permissions.request(.screenRecording) == .authorized else { guidance = .screen; return }
    start()
}
```
Developer workaround when a Debug build is stuck denied after a rebuild (replace `<bundle id>`):
```sh
tccutil reset ScreenCapture <bundle id>
tccutil reset Camera <bundle id>
tccutil reset Microphone <bundle id>
```
Prefer a stable "Apple Development" signing identity over ad-hoc for local builds so the designated requirement does not change per build; flag a scheme or CI job that uses `CODE_SIGN_IDENTITY = "-"` for builds meant to be run interactively.

## 5. **`.denied` and `.restricted` get an explanation and a button into the right Privacy pane**

Once denied, nothing the app calls will show the system prompt again; the only path is System Settings. `.restricted` (MDM profile, parental controls) cannot be fixed by the user, so the message must say so instead of offering a button that does nothing.

Grep: `x-apple\.systempreferences:com\.apple\.preference\.security\?Privacy_(ScreenCapture|Camera|Microphone)` (expect all three); `case \.denied` without a UI path; `case \.restricted` folded into `.denied`.

Wrong:
```swift
if status == .denied { _ = await permissions.request(.camera) }   // no-op; the user sees nothing
```
Right:
```swift
enum PrivacyPane: String { case screen = "Privacy_ScreenCapture", camera = "Privacy_Camera", microphone = "Privacy_Microphone" }
@MainActor func openPrivacySettings(_ pane: PrivacyPane) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!)
}
// View: ContentUnavailableView { Label("Screen Recording is off", systemImage: "rectangle.dashed.badge.record") }
//   description: { Text("Allow LibreScreen under Privacy & Security > Screen & System Audio Recording, then try again.") }
//   actions: { Button("Open System Settings") { openPrivacySettings(.screen) } }
// .restricted: same view, the text says a management profile blocks it, and there is no button.
```

## 6. **No `AVCaptureSession.startRunning()` or `SCStream.startCapture()` before the matching status is `.authorized`**

Starting a session without authorisation either triggers a TCC prompt from deep inside Infrastructure (violating rules 1 and 3) or silently produces black frames and an empty recording. The check is cheap; it opens every `start()`.

Grep: `startRunning\(\)|startCapture\(\)|SCScreenshotManager\.captureImage|SCShareableContent\.` — the enclosing function must contain `status\(of:` or `== \.authorized` before the call.

Wrong:
```swift
func start() async throws {
    try configure()
    sessionQueue.async { self.session.startRunning() }    // may prompt, may record black
}
```
Right:
```swift
func start() async throws {
    guard permissions.status(of: .camera) == .authorized else { throw CaptureError.notAuthorized(.camera) }
    try configure()
    sessionQueue.async { self.session.startRunning() }
}
```

## 7. **Turning a feature off stops the session and releases the device; the indicator light must go off**

Hiding the bubble or disabling a connection keeps the camera open (green LED on) and the microphone input live (orange dot on); users read that as spyware. Stop and tear down within a second of the toggle, and tear everything down when the recording ends.

Grep: `isHidden = true|orderOut\(|connection\.isEnabled = false|isMuted` in camera/microphone code without `stopRunning\(\)|removeInput\(` nearby.

Wrong:
```swift
func setCamera(on: Bool) { bubblePanel.isHidden = !on }                   // session runs, LED stays on
func setMicrophone(on: Bool) { audioInput.ports.first?.isEnabled = on }   // orange dot stays on
```
Right:
```swift
func setCamera(on: Bool) async {
    if on { try? await cameraService.start() } else { await cameraService.stop() }   // stopRunning + removeInput
    bubbleController.setVisible(on)
}
func setMicrophone(on: Bool) {
    sessionQueue.async { on ? self.addMicInput() : self.removeMicInput() }   // remove the input; do not mute
}
```
Manual check: toggle each feature off and watch the camera LED and the menu-bar microphone/screen indicators; all must clear.

## 8. **Camera and microphone are requested separately, each only when its own feature is enabled**

Least privilege is per capability. Requesting the microphone because the camera bubble was turned on (or the reverse) is a prompt the user did not cause for a permission the app does not need yet.

Grep: `requestAccess\(for: \.audio\)` in the same function as `requestAccess\(for: \.video\)`; `request\(\.camera\)` next to `request\(\.microphone\)`.

Wrong:
```swift
func cameraToggled(_ on: Bool) async {
    _ = await permissions.request(.camera)
    _ = await permissions.request(.microphone)       // "while we are at it"
}
```
Right:
```swift
func cameraToggled(_ on: Bool) async {
    guard on, await permissions.request(.camera) == .authorized else { … }
}
func microphoneToggled(_ on: Bool) async {
    guard on, await permissions.request(.microphone) == .authorized else { … }
}
```

## 9. **Info.plist usage strings match the real behaviour; missing keys terminate the app**

macOS kills a process that touches the camera or microphone without `NSCameraUsageDescription`/`NSMicrophoneUsageDescription`. The text is the only thing the user sees in the prompt, so it must say what LibreScreen does with the device and when the device is on.

Grep: `NSCameraUsageDescription|NSMicrophoneUsageDescription` in `Info.plist` or `INFOPLIST_KEY_` in `project.pbxproj`; verify the built app with `plutil -p LibreScreen.app/Contents/Info.plist | grep UsageDescription`.

Wrong:
```xml
<!-- no NSMicrophoneUsageDescription, yet the recorder adds an AVCaptureDeviceInput for audio -->
<key>NSCameraUsageDescription</key><string>Camera</string>
```
Right:
```xml
<key>NSCameraUsageDescription</key>
<string>LibreScreen shows your camera in a bubble over the recording while you keep the camera turned on.</string>
<key>NSMicrophoneUsageDescription</key>
<string>LibreScreen records your voice when the microphone is enabled for a recording.</string>
```

## 10. **The app never captures its own panels: `sharingType = .none` on every panel plus self-exclusion in `SCContentFilter`**

The HUD, camera bubble, countdown and region overlays sit on top of the captured area; without exclusion they are burned into the movie. `sharingType = .none` hides a window from capture services; excluding the app in the filter also covers windows created later and screenshots taken with `SCScreenshotManager`.

Grep: `sharingType = \.none` (expect one per panel/window subclass); `SCContentFilter\(display:` without `excludingApplications:`; `excludingWindows: \[\]`.

Wrong:
```swift
let filter = SCContentFilter(display: display, excludingWindows: [])     // HUD and bubble appear in the movie
```
Right:
```swift
// AppKit: in every panel/window initialiser used while recording
sharingType = .none
// Capture: exclude this app for display/region capture (window capture is limited to one window anyway)
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
```
Order matters: panels get `sharingType = .none` *before* they are shown; the countdown and overlays are ordered out before the first frame or excluded as well.

## 11. **Hotkeys use Carbon `RegisterEventHotKey`; nothing requires Accessibility or Input Monitoring**

`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` and `CGEvent.tapCreate` see every keystroke of every app and need the Input Monitoring/Accessibility prompt; `AXUIElement` needs Accessibility. None of them are required: registered hot keys are delivered to the app without any permission, and local monitors suffice inside the app's own overlay windows.

Grep: `AXIsProcessTrusted|AXUIElement|CGEvent\.tapCreate|CGEventTapCreate|IOHIDManager|addGlobalMonitorForEvents\(matching: \[?\.(keyDown|keyUp|flagsChanged)`.

Wrong:
```swift
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in   // Input Monitoring prompt; sees all keystrokes
    if e.modifierFlags.contains([.command, .shift]) && e.keyCode == 15 { self.toggleRecording() }
}
```
Right:
```swift
var ref: EventHotKeyRef?
RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), hotKeyID,
                    GetApplicationEventTarget(), 0, &ref)       // no TCC; handler via InstallEventHandler
```

## 12. **Statuses are refreshed when the app becomes active and when a stream stops with an error**

Users grant permission in System Settings and switch back; the UI must notice without a relaunch where macOS allows it (camera, microphone) and must say "quit and reopen LibreScreen" where it does not (Screen Recording usually takes effect only after a relaunch). Since macOS 14 the user can also stop a capture from the menu-bar indicator, and macOS 15 can revoke screen recording mid-session; `SCStreamDelegate.stream(_:didStopWithError:)` must finish the file and explain, never crash or lose the recording.

Grep: `didBecomeActiveNotification` (expect it in the permissions/ViewModel layer); `didStopWithError` (expect an implementation that finalises the writer); `fatalError|preconditionFailure` inside it.

Wrong:
```swift
func stream(_ stream: SCStream, didStopWithError error: Error) { fatalError("stream stopped: \(error)") }
```
Right:
```swift
nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    pipeline.finish(reason: .systemStopped(error))      // closes the AVAssetWriter, keeps what was recorded
    events.yield(.stopped(.systemStopped(error)))       // ViewModel refreshes statuses, shows guidance if denied
}
// ViewModel: on NSApplication.didBecomeActiveNotification -> refreshStatuses() (see memory-rules.md #4)
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | A prompt can appear without a user action, a device can be used without authorisation or stay on after the feature is off, the app records itself, or it reaches for a permission it must never need | Request outside `PermissionsService` or at launch/`init`/`onAppear` (#1, #3); session started before `.authorized` (#6); camera/mic live after toggle off (#7); own panels captured (#10); any Accessibility/Input Monitoring API (#11); `fatalError` in `didStopWithError` (#12); missing usage string for a device that is used (#9) |
| Medium | The user can get stuck or misled, but no device is misused | No guidance/button for `.denied` (#5); cached authorisation flags (#4); joint camera+mic request (#8); `CGRequestScreenCaptureAccess()` `false` treated as denial (#2); statuses not refreshed on activation (#12); `AVAuthorizationStatus` leaking into Features (#1) |
| Low | Wording or polish | Guidance text that names the wrong pane; `.restricted` shown with a useless button (#5); usage strings that are honest but vague (#9); missing manual verification note for indicator lights (#7) |
