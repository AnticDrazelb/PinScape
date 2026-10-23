import CoreNFC
import Foundation

/// Reads and writes Pinscape NFC stickers. A sticker holds nothing but a link like
/// `pinscape://sticker/<id>`; the pins themselves stay on your phone.
final class StickerReader: NSObject, NFCNDEFReaderSessionDelegate {
    static let shared = StickerReader()

    enum Outcome {
        case read(String)
        case wrote
        case failed(String)
    }

    private enum Mode {
        case read
        case write(URL)
    }

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .read
    private var completion: ((Outcome) -> Void)?

    static var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    static func url(for stickerID: String) -> URL {
        URL(string: "pinscape://sticker/\(stickerID)")!
    }

    func scan(_ completion: @escaping (Outcome) -> Void) {
        begin(.read, message: "Hold the top of your iPhone near a Pinscape sticker.", completion: completion)
    }

    func write(stickerID: String, _ completion: @escaping (Outcome) -> Void) {
        begin(.write(Self.url(for: stickerID)), message: "Hold the top of your iPhone near a blank NFC sticker.", completion: completion)
    }

    private func begin(_ mode: Mode, message: String, completion: @escaping (Outcome) -> Void) {
        guard Self.isAvailable else {
            completion(.failed("This iPhone can't read NFC stickers."))
            return
        }
        self.mode = mode
        self.completion = completion
        let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        session.alertMessage = message
        session.begin()
        self.session = session
    }

    private func finish(_ outcome: Outcome) {
        let completion = completion
        self.completion = nil
        DispatchQueue.main.async {
            completion?(outcome)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let error = error as? NFCReaderError,
           error.code == .readerSessionInvalidationErrorUserCanceled || error.code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            completion = nil
            return
        }
        finish(.failed(error.localizedDescription))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Tags are handled in didDetect tags.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if error != nil {
                session.invalidate(errorMessage: "Couldn't connect to the sticker. Try again.")
                return
            }
            switch self.mode {
            case .read:
                tag.readNDEF { message, _ in
                    let url = message?.records.compactMap { $0.wellKnownTypeURIPayload() }.first { $0.scheme == "pinscape" }
                    guard let url, url.host == "sticker", let id = url.pathComponents.last, id != "/" else {
                        session.invalidate(errorMessage: "That isn't a Pinscape sticker yet.")
                        return
                    }
                    session.alertMessage = "Got it."
                    session.invalidate()
                    self.finish(.read(id))
                }
            case .write(let url):
                tag.queryNDEFStatus { status, _, _ in
                    guard status == .readWrite, let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                        session.invalidate(errorMessage: "This sticker can't be written to.")
                        return
                    }
                    tag.writeNDEF(NFCNDEFMessage(records: [payload])) { error in
                        if error != nil {
                            session.invalidate(errorMessage: "Writing failed. Try again.")
                        } else {
                            session.alertMessage = "Sticker ready."
                            session.invalidate()
                            self.finish(.wrote)
                        }
                    }
                }
            }
        }
    }
}
