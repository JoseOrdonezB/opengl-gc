//
//  BGMPlayer.swift
//  lab9
//
//  Created by Jose Ordoñez on 23/11/25.
//

import Foundation
import AVFoundation

final class BGMPlayer: ObservableObject {

    static let shared = BGMPlayer()

    private var player: AVAudioPlayer?
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private init() {}

    func play() {
        if let p = player {
            if !p.isPlaying {
                p.play()
                isPlaying = true
            }
            return
        }

        guard let url = audioURL() else {
            print("BGMPlayer: no se encontró el archivo de audio en el bundle.")
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("BGMPlayer: error al crear AVAudioPlayer: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    private func audioURL() -> URL? {
        let bundle = Bundle.main

        let names: [(String, String)] = [
            ("1123", "MP3"),
            ("1123", "mp3")
        ]

        let subdirs: [String?] = [
            "Resources/Music",
            "Music",
            "Resources",
            nil
        ]

        for (name, ext) in names {
            for sub in subdirs {
                if let url = bundle.url(forResource: name,
                                        withExtension: ext,
                                        subdirectory: sub) {
                    return url
                }
            }
        }

        return nil
    }
}
