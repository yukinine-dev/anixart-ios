import AVFoundation
import Foundation

struct VoiceAudioConfiguration: Equatable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    // Apple's duckOthers option is valid only for playback/playAndRecord/
    // multiRoute, not record. Speech input needs no mixing/ducking options.
    static let recording = VoiceAudioConfiguration(category: .record, mode: .measurement, options: [])

    /// AVAudioSession does not expose its previous active flag. Do not deactivate
    /// an existing playback category when returning audio ownership to the player.
    var preservesPlayback: Bool { category == .playback || category == .playAndRecord || category == .multiRoute }
}

@MainActor
protocol VoiceAudioSessionControlling: AnyObject {
    var configuration: VoiceAudioConfiguration { get }
    func configure(_ configuration: VoiceAudioConfiguration) throws
    func setActive(_ active: Bool, notifyOthers: Bool) throws
}

@MainActor
final class SystemVoiceAudioSession: VoiceAudioSessionControlling {
    private let session = AVAudioSession.sharedInstance()
    var configuration: VoiceAudioConfiguration {
        VoiceAudioConfiguration(category: session.category, mode: session.mode, options: session.categoryOptions)
    }
    func configure(_ configuration: VoiceAudioConfiguration) throws {
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
    }
    func setActive(_ active: Bool, notifyOthers: Bool) throws {
        try session.setActive(active, options: notifyOthers ? .notifyOthersOnDeactivation : [])
    }
}

/// Only changes category/mode/options while recording. Cleanup is idempotent and
/// does not overwrite a player that has since configured a different category.
@MainActor
final class VoiceAudioSessionLease {
    private let audioSession: any VoiceAudioSessionControlling
    private var previous: VoiceAudioConfiguration?
    private var installed: VoiceAudioConfiguration?

    init(audioSession: any VoiceAudioSessionControlling) { self.audioSession = audioSession }

    func acquire() throws {
        guard previous == nil else { return }
        previous = audioSession.configuration
        do {
            try audioSession.configure(.recording)
            // The OS can normalize the configuration. Compare
            // cleanup ownership with what was actually installed, not our input.
            installed = audioSession.configuration
            try audioSession.setActive(true, notifyOthers: false)
            installed = audioSession.configuration
        } catch {
            _ = release()
            throw error
        }
    }

    @discardableResult
    func release() -> String? {
        guard let previous else { return nil }
        let installed = self.installed
        self.previous = nil
        self.installed = nil
        guard let installed, audioSession.configuration == installed else { return nil }
        var failure: String?
        if !previous.preservesPlayback {
            do { try audioSession.setActive(false, notifyOthers: true) }
            catch { failure = error.localizedDescription }
        }
        do { try audioSession.configure(previous) }
        catch {
            failure = error.localizedDescription
            // Do not leave the recording session active after a restoration error.
            try? audioSession.setActive(false, notifyOthers: true)
        }
        return failure
    }
}
