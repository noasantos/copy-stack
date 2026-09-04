#if DEBUG
import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// Turns the onboarding demo scenes into README media: one seamless loop per demo as H.264, plus
/// still frames. DEBUG only, driven by `scripts/record-demos.sh`:
///
///     CLIPSTACK_RECORD_DEMOS=<dir> ClipStack.app/Contents/MacOS/ClipStack
///
/// The scenes animate on SwiftUI's animation clock, which an offscreen `ImageRenderer` pass never
/// advances — frame-stepping it would only ever produce the cue end states. So every shot is hosted
/// in a real window and filmed while it plays: through ScreenCaptureKit at 60 fps when Screen
/// Recording is granted, otherwise by capturing this process's own window — no permission needed
/// for that, at the cost of running near 25 fps.
@MainActor
enum DemoRecorder {
    struct Shot {
        enum Motion {
            case still
            case quickPaste
            case capture

            /// One full loop of the timeline. Recording exactly this long makes the GIF seamless.
            var durationMilliseconds: Int? {
                switch self {
                case .still: return nil
                case .quickPaste: return 7400
                case .capture: return 6600
                }
            }
        }

        let name: String
        let step: OnboardingModel.Step
        let motion: Motion
        var dark = false
        var framed = false

        /// Shortcut pill under the scene. The onboarding window puts the keys in its own chrome,
        /// which a README clip does not carry, so the demo has to say the shortcut itself.
        var caption: (letter: String, title: String)? {
            switch motion {
            case .quickPaste: return ("V", "Quick Paste")
            case .capture: return ("S", "Capture area")
            case .still: return nil
            }
        }
    }

    static let frameRate: Int32 = 60
    /// Hero laptop size as a fraction of the canonical 1780×1070 artboard, chosen so the window
    /// still fits a 1512 pt display.
    static let heroScale: CGFloat = 0.75

    static var requestedOutputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment["CLIPSTACK_RECORD_DEMOS"], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
    }

    static var shots: [Shot] {
        [false, true].flatMap { dark -> [Shot] in
            let suffix = dark ? "dark" : "light"
            return [
                Shot(name: "quick-paste-\(suffix)", step: .quickPaste, motion: .quickPaste, dark: dark),
                Shot(name: "area-capture-\(suffix)", step: .capture, motion: .capture, dark: dark),
                Shot(name: "history-popover-\(suffix)", step: .welcome, motion: .still, dark: dark),
                Shot(name: "hero-\(suffix)", step: .welcome, motion: .still, dark: dark, framed: true)
            ]
        }
    }

    static func run(outputDirectory: URL) {
        Task { @MainActor in
            do {
                try await recordAll(into: outputDirectory)
                exit(0)
            } catch {
                log("failed: \(String(describing: error))")
                exit(1)
            }
        }
    }

    private static func recordAll(into directory: URL) async throws {
        if !Permissions.screenRecordingGranted {
            // Surfaces the system prompt once per build, which is the fastest route to the toggle.
            _ = CGRequestScreenCaptureAccess()
            log("""
            Screen Recording is not granted for this build — capturing the window directly instead, \
            which tops out near 25 fps. For 60 fps clips, grant Screen Recording to \
            build/Debug/ClipStack.app in System Settings ▸ Privacy & Security and run this again.
            """)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)

        for shot in shots {
            let url = try await record(shot, into: directory)
            log("recorded \(url.lastPathComponent)")
        }
    }

    private static func record(_ shot: Shot, into directory: URL) async throws -> URL {
        let timeline = DemoTimeline()
        let stage = Stage(shot: shot, timeline: timeline)
        defer {
            timeline.stop()
            stage.dismiss()
        }

        // One run loop turn is not enough: the scene reports its caret and status-item geometry
        // through preference keys, and the Quick Paste panel is anchored off that first report.
        try await Task.sleep(nanoseconds: 900_000_000)

        guard let duration = shot.motion.durationMilliseconds else {
            let url = directory.appendingPathComponent("\(shot.name).png")
            try await writeStill(of: stage, to: url)
            return url
        }

        let url = directory.appendingPathComponent("\(shot.name).mov")
        try? FileManager.default.removeItem(at: url)

        let start = { @MainActor in
            switch shot.motion {
            case .quickPaste: timeline.startQuickPaste()
            case .capture: timeline.startCapture()
            case .still: break
            }
        }

        if Permissions.screenRecordingGranted {
            try await recordThroughScreenCaptureKit(stage: stage, to: url, milliseconds: duration, start: start)
        } else {
            try await recordThroughWindowList(stage: stage, to: url, milliseconds: duration, start: start)
        }
        return url
    }

    private static func recordThroughScreenCaptureKit(stage: Stage,
                                                      to url: URL,
                                                      milliseconds: Int,
                                                      start: @escaping @MainActor () -> Void) async throws {
        let writer = try MovieWriter(url: url, pixelSize: stage.pixelSize)
        let output = StreamOutput(writer: writer, duration: CMTime(value: CMTimeValue(milliseconds), timescale: 1000))
        let stream = SCStream(filter: try await stage.contentFilter(), configuration: stage.streamConfiguration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "clipstack.demo-recorder"))
        try await stream.startCapture()

        // Let the capture pipeline settle before cue 0, so the loop starts on a real frame.
        try await Task.sleep(nanoseconds: 300_000_000)
        output.arm()
        start()

        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000 + 10)
        while !output.isComplete, Date() < deadline {
            try await Task.sleep(nanoseconds: 40_000_000)
        }

        try await stream.stopCapture()
        try await writer.finish()
    }

    private static func recordThroughWindowList(stage: Stage,
                                                       to url: URL,
                                                       milliseconds: Int,
                                                       start: @escaping @MainActor () -> Void) async throws {
        let writer = try MovieWriter(url: url, pixelSize: stage.pixelSize)
        let frameNanos = UInt64(1_000_000_000 / Double(frameRate))
        let total = Double(milliseconds) / 1000

        start()
        let began = CFAbsoluteTimeGetCurrent()
        var elapsed: Double = 0
        var frames = 0
        while elapsed < total {
            if let buffer = stage.snapshot(into: writer.pixelBufferPool) {
                writer.append(buffer, at: CMTime(seconds: elapsed, preferredTimescale: 600))
                frames += 1
            }
            try await Task.sleep(nanoseconds: frameNanos)
            elapsed = CFAbsoluteTimeGetCurrent() - began
        }
        try await writer.finish()
        log(String(format: "own-window capture ran at %.1f fps", Double(frames) / elapsed))
    }

    private static func writeStill(of stage: Stage, to url: URL) async throws {
        let image: CGImage
        if #available(macOS 14.0, *), Permissions.screenRecordingGranted {
            image = try await SCScreenshotManager.captureImage(contentFilter: stage.contentFilter(),
                                                               configuration: stage.streamConfiguration)
        } else if let captured = stage.windowImage(retina: true) {
            image = captured
        } else {
            throw RecorderError.windowNotShareable
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = stage.size
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RecorderError.encodingFailed
        }
        try data.write(to: url)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("demo-recorder: \(message)\n".utf8))
    }

    enum RecorderError: Error {
        case windowNotShareable
        case encodingFailed
        case writerFailed(String)
    }
}

/// The window a shot is filmed in. Borderless, shadowless and pinned to the top-left of the main
/// display so the whole surface stays inside the frame buffer.
@MainActor
private final class Stage {
    let size: CGSize
    private let window: NSWindow
    private let content: AnyView

    /// ScreenCaptureKit composites on the GPU and films at Retina scale for free. Own-window
    /// capture pays for every pixel twice — copy out, then blit in — and 4× the pixels costs it
    /// half its frame rate, which a demo loop feels more than it feels the sharpness.
    var scale: CGFloat {
        Permissions.screenRecordingGranted ? window.backingScaleFactor : 1
    }

    var pixelSize: CGSize {
        CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    init(shot: DemoRecorder.Shot, timeline: DemoTimeline) {
        let scene = DesktopScene(step: shot.step, permission: .granted, timeline: timeline)
        if shot.framed {
            let canonical = MacBookFrame<EmptyView>.canonicalSize
            let scale = DemoRecorder.heroScale
            let padding: CGFloat = 48
            let laptop = CGSize(width: (canonical.width * scale).rounded(),
                                height: (canonical.height * scale).rounded())
            size = CGSize(width: laptop.width + padding * 2, height: laptop.height + padding * 2)
            content = AnyView(
                MacBookFrame { scene }
                    .scaleEffect(scale / MacBookFrame<EmptyView>.scale, anchor: .topLeading)
                    .frame(width: laptop.width, height: laptop.height, alignment: .topLeading)
                    .padding(padding)
                    .background(OnboardingChrome.windowBackground)
            )
        } else if let caption = shot.caption {
            size = DemoGeometry.screen
            content = AnyView(
                scene.overlay(alignment: .bottom) {
                    ShortcutCaption(timeline: timeline,
                                    letter: caption.letter,
                                    title: caption.title,
                                    showsLegend: shot.motion == .quickPaste)
                }
            )
        } else {
            size = DemoGeometry.screen
            content = AnyView(scene)
        }

        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = shot.framed ? .windowBackgroundColor : .black
        window.level = .floating
        window.collectionBehavior = [.fullScreenNone, .ignoresCycle]

        let host = NSHostingView(rootView: content.environment(\.colorScheme, shot.dark ? .dark : .light))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.minX, y: screen.frame.maxY - size.height))
        }
        window.orderFrontRegardless()
    }

    var streamConfiguration: SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: DemoRecorder.frameRate)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.scalesToFit = false
        if #available(macOS 14.0, *) {
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
        }
        return configuration
    }

    func contentFilter() async throws -> SCContentFilter {
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let match = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw DemoRecorder.RecorderError.windowNotShareable
        }
        return SCContentFilter(desktopIndependentWindow: match)
    }

    /// Own-window capture. `CGWindowListCreateImage` is deprecated in favour of ScreenCaptureKit,
    /// but it is the one path that composites the window — materials included — without the Screen
    /// Recording grant, because the window belongs to this process. Roughly 25 fps at Retina scale.
    func snapshot(into pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool, let image = windowImage() else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: CVPixelBufferGetWidth(buffer),
                                      height: CVPixelBufferGetHeight(buffer),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: CVPixelBufferGetWidth(buffer),
                                                                   height: CVPixelBufferGetHeight(buffer))))
        return buffer
    }

    /// A still is one frame, so it can afford the Retina copy a 25 fps loop cannot.
    @available(macOS, deprecated: 14.0)
    func windowImage(retina: Bool = false) -> CGImage? {
        CGWindowListCreateImage(.null,
                                .optionIncludingWindow,
                                CGWindowID(window.windowNumber),
                                [.boundsIgnoreFraming, retina ? .bestResolution : .nominalResolution])
    }

    func dismiss() {
        window.orderOut(nil)
    }
}

/// Names the shortcut the clip is demonstrating, and lights its keys from the same timeline the
/// scene runs on.
private struct ShortcutCaption: View {
    @ObservedObject var timeline: DemoTimeline
    let letter: String
    let title: String
    let showsLegend: Bool

    var body: some View {
        HStack(spacing: 14) {
            ShortcutBadges(letter: letter, pressedKeys: timeline.pressedKeys)
            Text(verbatim: title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OnboardingChrome.label)
            if showsLegend {
                Divider().frame(height: 18)
                QuickPasteLegend(pressedKeys: timeline.pressedKeys)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(OnboardingChrome.windowBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(OnboardingChrome.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .padding(.bottom, 44)
    }
}

/// H.264 movie writer shared by both capture paths.
private final class MovieWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let lock = NSLock()
    private var started = false

    var pixelBufferPool: CVPixelBufferPool? {
        if !started { startIfNeeded(at: .zero) }
        return adaptor.pixelBufferPool
    }

    init(url: URL, pixelSize: CGSize) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 40_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(pixelSize.width),
            kCVPixelBufferHeightKey as String: Int(pixelSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        writer.add(input)
    }

    func startIfNeeded(at time: CMTime) {
        lock.withLock {
            guard !started else { return }
            started = true
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        startIfNeeded(at: .zero)
        guard input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw DemoRecorder.RecorderError.writerFailed(writer.error.map(String.init(describing:)) ?? "unknown")
        }
    }
}

/// Feeds the stream's own sample buffers into the movie, stopping one loop after the first armed frame.
private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: MovieWriter
    private let duration: CMTime
    private let lock = NSLock()
    private var armed = false
    private var complete = false
    private var startTime: CMTime?

    init(writer: MovieWriter, duration: CMTime) {
        self.writer = writer
        self.duration = duration
        super.init()
    }

    var isComplete: Bool { lock.withLock { complete } }

    func arm() { lock.withLock { armed = true } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, isFrameComplete(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        guard armed, !complete else {
            lock.unlock()
            return
        }
        if startTime == nil {
            startTime = timestamp
            lock.unlock()
            writer.startIfNeeded(at: timestamp)
            lock.lock()
        }
        guard let startTime else {
            lock.unlock()
            return
        }
        if CMTimeCompare(CMTimeSubtract(timestamp, startTime), duration) >= 0 {
            complete = true
            lock.unlock()
            return
        }
        lock.unlock()
        writer.append(sampleBuffer)
    }

    private func isFrameComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}
#endif
