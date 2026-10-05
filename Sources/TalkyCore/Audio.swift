import AVFoundation
import Foundation

public struct Recording {
    public var samples: [Float]   // 16 kHz mono
    public var peak: Float
    public var duration: TimeInterval { Double(samples.count) / 16_000 }
}

/// Captures the default input device and converts it to 16 kHz mono float, which is what Whisper wants.
/// A fresh AVAudioEngine per recording picks up mic changes (AirPods connecting, etc.).
public final class AudioRecorder: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var peak: Float = 0
    /// RMS level 0...1, called on the main queue.
    public var onLevel: ((Float) -> Void)?

    public init() {}

    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start() throws {
        stopEngine()
        lock.withLock { samples = []; samples.reserveCapacity(16_000 * 60); peak = 0 }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw TalkyError("No microphone available")
        }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw TalkyError("Can't convert from the microphone format")
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = target.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard err == nil, let ch = out.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: ch, count: Int(out.frameLength))
            var sum: Float = 0
            var localPeak: Float = 0
            for s in chunk {
                sum += s * s
                localPeak = max(localPeak, abs(s))
            }
            let rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()
            self.lock.withLock {
                self.samples.append(contentsOf: chunk)
                self.peak = max(self.peak, localPeak)
            }
            if let onLevel = self.onLevel {
                // Speech RMS sits around 0.02-0.2; scale so normal talking fills the meter.
                let level = min(1, rms * 8)
                DispatchQueue.main.async { onLevel(level) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw TalkyError("Microphone failed to start: \(error.localizedDescription)")
        }
        self.engine = engine
    }

    public func stop() -> Recording {
        stopEngine()
        return lock.withLock { Recording(samples: samples, peak: peak) }
    }

    public func cancel() {
        stopEngine()
        lock.withLock { samples = [] }
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}

public enum WAV {
    /// 16-bit PCM mono WAV.
    public static func data(samples: [Float], sampleRate: Int = 16_000) -> Data {
        var d = Data()
        let dataSize = UInt32(samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        d.reserveCapacity(d.count + Int(dataSize))
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }

    public static func writeTemp(samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("talky-\(UUID().uuidString).wav")
        try data(samples: samples).write(to: url)
        return url
    }
}
