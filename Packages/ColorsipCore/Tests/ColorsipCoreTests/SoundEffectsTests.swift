import Foundation
import Testing
@testable import ColorsipCore

@MainActor
private final class FakeSoundPlayer: SoundPlayer {
    var played: [SoundEffect] = []
    func play(_ effect: SoundEffect) { played.append(effect) }
}

@Suite("Sound effects")
struct SoundEffectTests {
    let color = CSipColor(.srgb, 0.2, 0.4, 0.6)

    @Test func aPickThatClosesThePickerSlurps() {
        #expect(SoundEffect.forStep(.pick(color, close: true)) == .slurp)
        #expect(SoundEffect.forStep(.pick(color, close: true, paste: true)) == .slurp)
    }

    @Test func aPickThatKeepsThePickerOpenPlaysThePickSound() {
        #expect(SoundEffect.forStep(.pick(color, close: false)) == .pick)
    }

    @Test func closingOrChoosingAModeIsSilent() {
        #expect(SoundEffect.forStep(.close) == nil)
        #expect(SoundEffect.forStep(.none) == nil)
    }

    @Test func eachEffectHasItsOwnSoundFile() {
        #expect(SoundEffect.pick.resourceName == "pick-color")
        #expect(SoundEffect.slurp.resourceName == "zeeoup")
        #expect(SoundEffect.plopp.resourceName == "plopp")
    }
}

@Suite("Sound effects gate")
@MainActor
struct SoundEffectsGateTests {
    private func makeStore() -> (SettingsStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
        return (SettingsStore(store: LibraryStore(folder: root)), root)
    }

    @Test func playsWhenEnabled() {
        let (settings, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let player = FakeSoundPlayer()
        let sounds = SoundEffects(player: player, settings: settings)
        sounds.play(.plopp)
        sounds.play(.slurp)
        #expect(player.played == [.plopp, .slurp])
    }

    @Test func isSilentWhenDisabled() {
        let (settings, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        settings.update { $0.soundEffects = false }
        let player = FakeSoundPlayer()
        let sounds = SoundEffects(player: player, settings: settings)
        sounds.play(.plopp)
        #expect(player.played.isEmpty)
    }

    @Test func playingAStepPlaysItsSound() {
        let (settings, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let player = FakeSoundPlayer()
        let sounds = SoundEffects(player: player, settings: settings)
        sounds.play(for: .pick(CSipColor(.srgb, 1, 0, 0), close: false))
        sounds.play(for: .close)
        #expect(player.played == [.pick])
    }
}
