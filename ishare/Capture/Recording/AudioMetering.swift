import AVFoundation
import Combine
import Defaults
import SwiftUI

struct RecordingAudioLevels: Equatable, Sendable {
    static let zero = RecordingAudioLevels(system: .zero, microphone: .zero)

    var system: AudioLevels
    var microphone: AudioLevels
}

enum PCMBufferConverter {
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              description.mediaType == .audio
        else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

final class MicrophoneSampleReceiver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let meter = PowerMeter()
    private let onLevels: @Sendable (AudioLevels) -> Void

    init(onLevels: @escaping @Sendable (AudioLevels) -> Void) {
        self.onLevels = onLevels
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let buffer = PCMBufferConverter.pcmBuffer(from: sampleBuffer) else { return }
        meter.process(buffer: buffer)
        onLevels(meter.levels)
    }
}

@MainActor
final class MicrophoneLevelMonitor: ObservableObject {
    @Published private(set) var levels = AudioLevels.zero
    @Published private(set) var isRunning = false
    @Published private(set) var isDenied = false

    private var runner: CaptureSessionRunner?
    private var receiver: MicrophoneSampleReceiver?
    private let sampleQueue = DispatchQueue(label: "dev.adrian.ishare.MicrophoneLevelMonitor")

    func start(deviceID: String?) async {
        stop()
        guard await CaptureDevices.requestAccess(for: .audio) else {
            isDenied = true
            return
        }
        isDenied = false
        guard let device = CaptureDevices.microphone(id: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        let runner = CaptureSessionRunner()
        let output = AVCaptureAudioDataOutput()
        let receiver = MicrophoneSampleReceiver { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self, isRunning else { return }
                self.levels = levels
            }
        }
        output.setSampleBufferDelegate(receiver, queue: sampleQueue)

        runner.session.beginConfiguration()
        if runner.session.canAddInput(input) { runner.session.addInput(input) }
        if runner.session.canAddOutput(output) { runner.session.addOutput(output) }
        runner.session.commitConfiguration()
        runner.start()

        self.runner = runner
        self.receiver = receiver
        isRunning = true
    }

    func stop() {
        runner?.stop()
        runner = nil
        receiver = nil
        isRunning = false
        levels = .zero
    }
}

struct AudioLevelMeter: View {
    let level: Float
    var peak: Float?
    var width: CGFloat = 46
    var height: CGFloat = 5

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(0.15))
            Capsule()
                .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                .mask(alignment: .leading) {
                    Capsule().frame(width: width * CGFloat(min(max(level, 0), 1)))
                }
            if let peak, peak > 0 {
                Capsule()
                    .fill(.primary.opacity(0.7))
                    .frame(width: 2)
                    .offset(x: max(0, width * CGFloat(min(peak, 1)) - 2))
            }
        }
        .frame(width: width, height: height)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(min(max(level, 0), 1) * 100))%"))
    }
}

struct LabeledAudioMeter: View {
    let systemImage: String
    let levels: AudioLevels
    var width: CGFloat = 46

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            AudioLevelMeter(level: levels.level, peak: levels.peakLevel, width: width)
        }
    }
}
