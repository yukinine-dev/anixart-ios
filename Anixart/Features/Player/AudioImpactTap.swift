import AVFoundation
import AudioToolbox
import MediaToolbox
import CoreMedia

/// Listens to the episode's own audio while it plays and reports a sudden loud
/// moment -- a gunshot, an explosion, a hit -- as a strength from 0 to 1.
///
/// Built on `MTAudioProcessingTap`, a read-only analysis tap: `process` never
/// writes to the buffer it is handed, only reads it, so what plays back is
/// untouched regardless of whether detection works.
///
/// Not a classifier -- there is no way to know *what* made the noise, only that
/// something suddenly got much louder than the scene's own recent level. That
/// is usually exactly the moments worth a buzz, and rarely anything else, which
/// is why this is an opt-in, separately gated setting rather than always on.
final class AudioImpactTap {
    private var tapRef: MTAudioProcessingTap?
    private var format = AudioStreamBasicDescription()
    private var hasBaseline = false
    private var baseline: Float = 0.02
    private var lastTrigger: CFAbsoluteTime = 0

    var sensitivity: AppHapticContentSensitivity = .normal
    var onImpact: ((Double) -> Void)?

    /// Attaches a fresh tap to every audio track of the item's asset. One call
    /// per item -- a replacement item (quality change, retry) needs its own.
    static func attach(
        to item: AVPlayerItem,
        tracks: [AVAssetTrack],
        sensitivity: AppHapticContentSensitivity,
        onImpact: @escaping (Double) -> Void
    ) -> AudioImpactTap? {
        guard !tracks.isEmpty else { return nil }
        let monitor = AudioImpactTap()
        monitor.sensitivity = sensitivity
        monitor.onImpact = onImpact
        guard monitor.makeTap() else { return nil }

        let parameters = tracks.map { track -> AVMutableAudioMixInputParameters in
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTapProcessor = monitor.tapRef
            return input
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        item.audioMix = mix
        return monitor
    }

    private func makeTap() -> Bool {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            `init`: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<AudioImpactTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, formatPointer in
                let monitor = Unmanaged<AudioImpactTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                monitor.format = formatPointer.pointee
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, flagsOut, numberFramesOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard status == noErr else { return }
                let monitor = Unmanaged<AudioImpactTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                monitor.analyze(bufferListInOut)
            }
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let created = tap else { return false }
        // `takeRetainedValue` balances Create's +1 under ARC: `tapRef` owns it from
        // here on, with no further manual retain/release anywhere in this class.
        tapRef = created.takeRetainedValue()
        return true
    }

    /// Runs on the audio-processing thread `MTAudioProcessingTap` calls back on --
    /// no UIKit, no locks, nothing that can block the mix graph. Only a float RMS
    /// over the buffer and a comparison against a slow-moving loudness floor.
    private func analyze(_ bufferListInOut: UnsafeMutablePointer<AudioBufferList>) {
        // The tap passes through whatever format AVPlayer's mix graph already
        // uses internally, which in practice is linear PCM Float32. If some
        // stream ever hands over anything else, this simply never fires rather
        // than risk misreading raw bytes as samples.
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return }

        var sumSquares: Float = 0
        var sampleCount = 0
        for buffer in UnsafeMutableAudioBufferListPointer(bufferListInOut) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                let value = samples[i]
                sumSquares += value * value
            }
            sampleCount += count
        }
        guard sampleCount > 0 else { return }
        let energy = (sumSquares / Float(sampleCount)).squareRoot()

        guard hasBaseline else {
            baseline = energy
            hasBaseline = true
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let threshold = baseline * sensitivity.thresholdMultiplier + 0.01
        if energy > threshold, now - lastTrigger > sensitivity.cooldown {
            lastTrigger = now
            let strength = Double(min(1, (energy - baseline) / max(baseline, 0.01) / 4))
            onImpact?(strength)
        } else {
            // The floor drifts toward the current level, but slowly, and is
            // capped on the way up -- a loud scene should still be able to buzz
            // right after a quiet one, not just the first second of it.
            let towards = min(energy, baseline * 1.5)
            baseline = baseline * 0.97 + towards * 0.03
        }
    }
}
