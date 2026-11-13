@preconcurrency import AVFoundation
import Foundation

struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum DictationError: Error, LocalizedError {
    case noMicrophone
    case speechUnavailable

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone input is available."
        case .speechUnavailable: "On-device speech recognition is not available for this language."
        }
    }
}
