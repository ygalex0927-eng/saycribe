import XCTest
@testable import SaycribeApp

final class ASRTests: XCTestCase {
    func testABIVersion() { XCTAssertEqual(ASR.abiVersion, 1); XCTAssertEqual(ASR.sampleRate, 16000) }

    func testRecognizerMissingModel() {
        XCTAssertThrowsError(try Recognizer(config: .init(modelDir: "/tmp/no-model"))) { err in
            XCTAssertEqual(err as? ASRError, .modelMissing)
        }
    }

    func testSegmenterMissingModel() {
        XCTAssertThrowsError(try Segmenter(config: .init(sileroModel: "/tmp/no-vad"))) { err in
            XCTAssertEqual(err as? ASRError, .modelMissing)
        }
    }

    func testErrorMessagesAreChinese() {
        XCTAssertTrue(ASRError.modelMissing.userMessage.contains("模型"))
    }
}
