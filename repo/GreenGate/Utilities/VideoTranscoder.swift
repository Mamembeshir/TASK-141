import AVFoundation
import Foundation

enum VideoTranscoder {

    static let targetPreset = AVAssetExportPreset1280x720

    /// Transcodes a video at `inputURL` to 720p and writes to `outputURL`.
    /// Calls `completion` on `completionQueue` with success/failure.
    /// Pass `.global()` when using a semaphore to avoid blocking the main thread.
    static func transcode(
        inputURL: URL,
        outputURL: URL,
        completionQueue: DispatchQueue = .main,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let asset = AVURLAsset(url: inputURL)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: targetPreset
        ) else {
            completionQueue.async { completion(false, nil) }
            return
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false

        session.exportAsynchronously {
            completionQueue.async {
                switch session.status {
                case .completed: completion(true, nil)
                default:         completion(false, session.error)
                }
            }
        }
    }
}
