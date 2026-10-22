# Memory rules — LibreScreen code audit

**Scope.** Object lifetime and memory pressure in LibreScreen: retain cycles created by escaping closures and delegates, ownership of the AppKit panels (recording HUD, camera bubble, countdown, per-display region-selection overlays), `NSEvent` monitors, teardown of `AVCaptureSession` and `SCStream`, and buffer discipline in the frame pipeline (`CVPixelBufferPool`, `CMSampleBuffer` retention, bounded queues). The app captures at 30–60 fps with Vision person segmentation and Core Image on Metal, so a leak that would be harmless in a form-based app becomes a stalled ScreenCaptureKit stream or a multi-gigabyte footprint within minutes. Apply these rules to `Infrastructure/` and `Features/`; `Domain/` holds value types and rarely has lifetime bugs. Acceptance target: **zero leaks after a one-minute recording with the camera on** (see "How to verify dynamically").

## 1. **Escaping closures that outlive the call capture `self` weakly; long-running `Task`s are stored and cancelled**

An unstructured `Task` keeps every strong capture alive until its body returns; a `for await` loop over ticks or frames never returns by itself, so a strong `self` keeps the ViewModel and everything it owns (panels, services) alive after the view is gone. Stored callback properties (`onFrame`, `onToggleRecord`) are the same cycle in another shape. `onAppear { Task { … } }` is never cancelled and runs again on each re-appearance: use `.task {}`, or store the `Task` and cancel it in `onDisappear`, `stop()` or `deinit`. A one-shot `DispatchQueue.async` block is not a cycle, but per-frame blocks should still capture weakly so a torn-down pipeline stops working.

Grep: `Task \{` without `\[weak self\]`; `\.onAppear \{[^}]*Task \{`; `on[A-Z]\w* = \{ self\.`; `Task \{` in `Features/` with no `cancel\(` in the same type.

Wrong:
```swift
.onAppear { Task { await viewModel.streamPreviewFrames() } }     // never cancelled, duplicates on re-appear
func start() { Task { for await t in clock.ticks { self.elapsed = t } } }   // strong self, endless loop
hotKeys.onToggleRecord = { self.toggleRecording() }               // vm -> hotKeys -> closure -> vm
```
Right:
```swift
.task { await viewModel.streamPreviewFrames() }                   // cancelled when the view disappears
private var tickTask: Task<Void, Never>?
func start() {
    tickTask?.cancel()
    tickTask = Task { [weak self] in
        guard let ticks = self?.clock.ticks else { return }
        for await t in ticks { guard let self, !Task.isCancelled else { return }; self.elapsed = t }
    }
}
func stop() { tickTask?.cancel(); tickTask = nil }                // from onDisappear and deinit
hotKeys.onToggleRecord = { [weak self] in self?.toggleRecording() }
```

## 2. **Timers: `DispatchSourceTimer` handlers capture weakly and are cancelled; `Timer` uses the block form plus `invalidate()`; no source is released while suspended**

A timer source retains its handler, the handler retains `self`, `self` retains the source, so the `FrameClock` never dies and keeps ticking into a dead pipeline; releasing a source that is still suspended traps inside libdispatch. `Timer.scheduledTimer(timeInterval:target:selector:)` is retained by the run loop and retains its target until `invalidate()`, so a countdown panel closed early stays alive.

Grep: `setEventHandler \{` without `\[weak self\]`; `makeTimerSource` in a type without `cancel\(\)`; `scheduledTimer\(timeInterval:.*target: self`; a `Timer` property with no `invalidate\(\)`.

Wrong:
```swift
timer.setEventHandler { self.tick() }                             // cycle; never cancelled
timer.schedule(deadline: .now(), repeating: .milliseconds(33)); timer.resume()
countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick),
                                      userInfo: nil, repeats: true)   // target retained until invalidate
```
Right:
```swift
func start() { timer.setEventHandler { [weak self] in self?.tick() }; timer.schedule(deadline: .now(), repeating: interval); timer.resume() }
func stop() { timer.setEventHandler(handler: nil); timer.cancel() }   // resumed in start(); never cancel a suspended source
deinit { stop() }
countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
    Task { @MainActor in self?.tick() }
}
func close() { countdownTimer?.invalidate(); countdownTimer = nil; orderOut(nil) }
```

## 3. **`NotificationCenter` block observers and `NSEvent` monitors are stored and removed**

`addObserver(forName:object:queue:using:)` and `addLocalMonitorForEvents`/`addGlobalMonitorForEvents` return tokens that are *not* cleaned up on deinit (unlike selector observers); the block captures `self`, so a controller that registers in `begin()` and drops the token leaks every instance, and a second overlay session installs a second handler that consumes Escape for a dead controller. Iterating `NotificationCenter.default.notifications(named:)` inside a stored `Task` is an equivalent that is cancelled with the task.

Grep: `addObserver\(forName:|addLocalMonitorForEvents|addGlobalMonitorForEvents` not assigned to a property; `removeObserver|removeMonitor` missing from the same type.

Wrong:
```swift
NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                       queue: .main) { _ in self.refreshPermissions() }    // token dropped
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in                             // token dropped
    if event.keyCode == 53 { self.cancelSelection() }; return event
}
```
Right:
```swift
private var activationObserver: (any NSObjectProtocol)?
private var escMonitor: Any?
func begin() {
    activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
        object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPermissions() } }
    escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53 else { return event }; self?.cancelSelection(); return nil
    }
}
func end() {                                                        // also called from deinit
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    if let escMonitor { NSEvent.removeMonitor(escMonitor) }
}
```

## 4. **Delegates are `weak var` and the protocol is class-constrained**

A strong delegate reference from a child (overlay window, bubble panel, capture output) back to its controller is the classic two-object cycle; neither side is ever released.

Grep: `var \w*[dD]elegate\w*:` not preceded by `weak`; `protocol \w+Delegate` without `AnyObject`.

Wrong:
```swift
protocol RegionOverlayDelegate { func overlay(_ o: RegionOverlayWindow, didSelect rect: CGRect) }
final class RegionOverlayWindow: NSWindow {
    var selectionDelegate: RegionOverlayDelegate?         // strong -> cycle with the controller
}
```
Right:
```swift
@MainActor protocol RegionOverlayDelegate: AnyObject { func overlay(_ o: RegionOverlayWindow, didSelect rect: CGRect) }
final class RegionOverlayWindow: NSWindow {
    weak var selectionDelegate: RegionOverlayDelegate?
}
```

## 5. **Every `NSPanel`/`NSWindow` has exactly one Swift owner and `isReleasedWhenClosed = false`**

`isReleasedWhenClosed` defaults to `true` for `NSWindow` and `false` for `NSPanel`. Under ARC a `true` value means `close()` releases an object a Swift property still holds (crash on next access), while a window with no Swift owner that is only `orderFront`ed is kept alive by AppKit and never reachable again (leak). The HUD, bubble, countdown and per-display overlays must be held by one controller that creates, reuses and tears them down.

Grep: `: NSPanel|: NSWindow|NSPanel\(|NSWindow\(`; `isReleasedWhenClosed` (expect `= false` once per owned window); `orderFront\(` on a local `let`.

Wrong:
```swift
func showOverlays() {
    for screen in NSScreen.screens {
        let w = RegionOverlayWindow(screen: screen)       // local; unreachable after return
        w.orderFront(nil)                                 // stays on screen, never released
    }
}
```
Right:
```swift
@MainActor final class RegionSelectionController {
    private var overlays: [RegionOverlayWindow] = []
    func begin() {
        overlays = NSScreen.screens.map { screen in
            let w = RegionOverlayWindow(screen: screen)
            w.isReleasedWhenClosed = false; w.orderFront(nil); return w   // ARC owns it, not -close
        }
    }
    func end() { overlays.forEach { $0.close() }; overlays.removeAll() }
}
```

## 6. **`AVCaptureSession` is stopped, inputs/outputs removed and the delegate cleared on teardown**

Dropping the reference does not stop a running session: the capture graph, the delegate queue and the device stay alive (camera light stays on), and a new session on the next toggle doubles the cost. `startRunning()`/`stopRunning()` block, so they run on the session queue, never on the main actor.

Grep: `AVCaptureSession\(\)`; `startRunning\(\)` without `stopRunning\(\)`; `setSampleBufferDelegate\(` without a `nil` counterpart.

Wrong:
```swift
func setCamera(on: Bool) {
    if on { let s = AVCaptureSession(); configure(s); s.startRunning(); session = s }
    else { session = nil }         // still running, delegate still retained, light still on
}
```
Right:
```swift
func stopCamera() {                // on sessionQueue
    guard let session else { return }
    session.stopRunning()
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    session.beginConfiguration()
    session.inputs.forEach(session.removeInput); session.outputs.forEach(session.removeOutput)
    session.commitConfiguration()
    self.session = nil
}
```

## 7. **`SCStream` is stopped with `stopCapture()` and its outputs removed before the reference is dropped**

A stream released while capturing keeps delivering frames to the registered output object; the output, its handler queue and the last buffers stay alive, and the next `startCapture()` competes with the orphan for the same display.

Grep: `SCStream\(`; `addStreamOutput\(` without `removeStreamOutput\(`; `startCapture\(` in a file without `stopCapture\(`.

Wrong:
```swift
func stop() { stream = nil }       // capture continues; output still registered
```
Right:
```swift
func stop() async {
    guard let stream else { return }
    try? await stream.stopCapture()
    try? stream.removeStreamOutput(frameOutput, type: .screen)
    try? stream.removeStreamOutput(frameOutput, type: .audio)
    self.stream = nil
    frameOutput.dropPendingFrame()  // release the last retained buffer (rule 9)
}
```

## 8. **Per-frame output buffers come from a `CVPixelBufferPool`; frame work runs inside `autoreleasepool`**

`CVPixelBufferCreate` per frame allocates a fresh IOSurface 60 times a second; a pool recycles them and keeps Metal and Core Image from re-mapping memory. Core Image, Vision and CGImage calls return autoreleased objects; on a long-lived dispatch queue they drain only when the block ends, so wrapping the per-frame body in `autoreleasepool` keeps the peak flat.

Grep: `CVPixelBufferCreate\(` (only in pool setup or tests); `CVPixelBufferPoolCreatePixelBuffer`; `autoreleasepool` missing from files that call `ciContext.render` or `VNImageRequestHandler`.

Wrong:
```swift
func render(_ image: CIImage) -> CVPixelBuffer? {
    var out: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &out)   // new surface per frame
    if let out { ciContext.render(image, to: out) }
    return out
}
```
Right:
```swift
// pool created once per (width, height, format) with kCVPixelBufferIOSurfacePropertiesKey and
// kCVPixelBufferMetalCompatibilityKey; recreated when the output size changes; flushed on stop
func render(_ image: CIImage) -> CVPixelBuffer? {
    autoreleasepool {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let out else { return nil }
        ciContext.render(image, to: out)
        return out
    }
}
```

## 9. **`CMSampleBuffer`s from ScreenCaptureKit and AVFoundation are released within one frame interval**

`SCStream` owns a small ring of buffers (`SCStreamConfiguration.queueDepth`, typically 3–8). If the app retains more than that (an array, a pending `Task` per frame, a "last N frames" cache) the stream has nothing left to write into and stalls or drops to a few fps; `AVCaptureVideoDataOutput` drops frames the same way. Keep at most one frame per stage, encode synchronously on the pipeline queue, and copy only what must outlive the callback.

Grep: `\[CMSampleBuffer\]`; `append\((sampleBuffer|sb)\)`; `Task \{` inside `didOutputSampleBuffer|captureOutput\(`.

Wrong:
```swift
nonisolated func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
    pending.append(sb)                 // unbounded; SCStream runs out of buffers and stalls
    Task { await self.process(sb) }    // one task per frame, no ordering, no limit
}
```
Right:
```swift
nonisolated func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sb.isValid, let pixelBuffer = sb.imageBuffer,
          sb.screenFrameStatus == .complete else { return }    // helper reading SCStreamFrameInfo.status
    pipeline.submit(Frame(pixelBuffer: pixelBuffer, pts: sb.presentationTimeStamp))   // one slot, rule 10
}
```

## 10. **Queues between capture and consumers are bounded: one latest-frame slot, drop when busy**

The encoder, the segmentation pass and the preview all run slower than capture at times; an unbounded `DispatchQueue.async` per frame or an `.unbounded` `AsyncStream` turns every slowdown into a backlog that is never recovered and retains every queued frame. Keep a single overwrite slot, check `AVAssetWriterInput.isReadyForMoreMediaData`, count dropped frames for diagnostics.

Grep: `queue\.async \{` inside frame callbacks; `AsyncStream<` without `bufferingPolicy`; `\.unbounded`.

Wrong:
```swift
nonisolated func submit(_ frame: Frame) {
    queue.async { self.encode(frame) }     // backlog grows while the encoder is slow; frames retained
}
```
Right:
```swift
private let slot = Mutex<Frame?>(nil)                    // Synchronization, macOS 15
private let drainScheduled = Atomic<Bool>(false)
nonisolated func submit(_ frame: Frame) {
    slot.withLock { $0 = frame }                          // overwrite, never grow
    guard !drainScheduled.exchange(true, ordering: .acquiringAndReleasing) else { return }
    queue.async { [self] in
        drainScheduled.store(false, ordering: .releasing)
        guard let frame = slot.withLock({ let f = $0; $0 = nil; return f }) else { return }
        guard writerInput.isReadyForMoreMediaData else { droppedFrames += 1; return }
        encode(frame)
    }
}
```

## 11. **`@Observable` objects are owned by `@State` or injected, never created inside `body`**

`body` runs on every render; constructing a ViewModel there creates a new object (and a new capture session, timer or observer) each time, abandons the previous one mid-work and loses state. The same applies to panel controllers created from a SwiftUI view.

Grep: `var body: some View \{[^}]*= \w+ViewModel\(`; `ViewModel\(\)` outside `@State`, `init` or the App entry point.

Wrong:
```swift
struct CameraBubbleView: View {
    var body: some View {
        let vm = CameraPreviewViewModel()                 // new object (and session) every render
        CameraPreview(viewModel: vm)
    }
}
```
Right:
```swift
struct CameraBubbleView: View {
    @State private var viewModel = CameraPreviewViewModel()   // once per view identity
    var body: some View { CameraPreview(viewModel: viewModel) }
}
// or inject from the parent: init(viewModel: CameraPreviewViewModel)
```

## How to verify dynamically

Static review cannot see IOSurface, Metal or AVFoundation allocations; run this after the code pass.

1. Build Debug, launch the app outside Xcode, start a recording with the camera bubble and microphone on, record for 60 s, stop, close the HUD. Repeat the start/stop cycle three times.
2. Leaked objects on the running process (launch with `MallocStackLogging=1 open -W LibreScreen.app` first when you want allocation stacks):
   ```sh
   pid=$(pgrep -x LibreScreen)
   leaks "$pid" | tail -n 5                              # expected: "0 leaks for 0 total leaked bytes"
   leaks "$pid" | grep -E 'ROOT LEAK|LibreScreen\.'     # leaked LibreScreen types, if any
   ```
3. Instruments Leaks template, attached to the running app or launching it:
   ```sh
   xcrun xctrace record --template Leaks --attach "$pid" --time-limit 90s --output /tmp/librescreen-leaks.trace
   xcrun xctrace record --template Leaks --launch -- path/to/LibreScreen.app --time-limit 90s --output /tmp/librescreen-leaks.trace
   open /tmp/librescreen-leaks.trace      # expected: no leak markers; Allocations "Persistent" flat after the first 5 s
   ```
4. Xcode Memory Graph: run with *Scheme > Diagnostics > Malloc Stack Logging* enabled, do the recording cycle, press *Debug Memory Graph*, filter the navigator by "LibreScreen". Expected after the HUD closes: 0 `SCStream`, 0 `AVCaptureSession`, 0 `RegionOverlayWindow`, only the intentionally cached HUD/bubble panels, one instance of each ViewModel, no leak badges.
5. `footprint "$pid"` (or Activity Monitor > Memory) before and after the three cycles: the difference stays under roughly 50 MB. Growth while `leaks` reports zero means frames are retained by something still reachable (rules 9–10), not leaked.

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | Memory grows for the whole recording, the capture stalls, or a capture device stays open after the feature is off | Sample buffers retained beyond `queueDepth` (#9); unbounded frame queue (#10); `SCStream`/`AVCaptureSession` not stopped or kept alive by a cycle (#6, #7); `DispatchSourceTimer` cycle keeping the pipeline alive (#2) |
| Medium | A bounded leak per user action (each start/stop, each panel open) or a duplicate worker doing real work | Panel without an owner (#5); observers/monitors never removed (#3); `Task` not cancelled on disappear (#1); new pixel buffer per frame (#8); `@Observable` created in `body` (#11) |
| Low | Lifetime is extended but bounded and released on teardown; style-level `weak`/`unowned` choices; missing `autoreleasepool` with no measured growth | Strong `self` in a one-shot `DispatchQueue.async` (#1); `Timer` target cycle on a timer that is reliably invalidated (#2); strong delegate on an object that is torn down together with its owner (#4) |
