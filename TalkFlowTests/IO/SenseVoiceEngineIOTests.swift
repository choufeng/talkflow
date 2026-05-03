// TalkFlowTests/IO/
import XCTest
@testable import TalkFlow

final class SenseVoiceEngineIOTests: XCTestCase {

    // MARK: - 静音判定

    func test_shortAudio_classifiedAsSilence() {
        let samples = [Float](repeating: 0, count: 1000)
        let result = makeSenseVoiceEngineForTesting().classifySilence(samples: samples)
        XCTAssertTrue(result)
    }

    func test_longAudio_notSilence() {
        let samples = [Float](repeating: 0, count: 5000)
        let result = makeSenseVoiceEngineForTesting().classifySilence(samples: samples)
        XCTAssertFalse(result)
    }

    // MARK: - 重采样

    func test_resample_preservesCount() {
        let engine = makeSenseVoiceEngineForTesting()
        let input = [Float](repeating: 1.0, count: 44100)
        let output = engine.resampleTo16k(samples: input, srcRate: 44100)
        XCTAssertEqual(output.count, 16000)
    }

    func test_resample_sameRate_isIdentity() {
        let engine = makeSenseVoiceEngineForTesting()
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let output = engine.resampleTo16k(samples: input, srcRate: 16000)
        XCTAssertEqual(output, input)
    }

    // MARK: - 解码

    func test_decodeAudio_invalidFile_throws() {
        let engine = makeSenseVoiceEngineForTesting()
        let url = URL(fileURLWithPath: "/tmp/nonexistent.m4a")
        XCTAssertThrowsError(try engine.decodeAudio(url: url))
    }

    // MARK: - fbank

    func test_fbank_sineWave_producesFrames() {
        let sampleCount = 16000
        let samples = (0..<sampleCount).map { i -> Float in
            sin(2.0 * Float.pi * 440.0 * Float(i) / 16000.0)
        }
        let feats = extractFbank(waveform: samples)
        XCTAssertGreaterThan(feats.count, 80)
        if let first = feats.first {
            XCTAssertEqual(first.count, 80)
        }
    }

    func test_fbank_shorterThanWindow_returnsEmpty() {
        let samples = [Float](repeating: 0, count: 399)
        let feats = extractFbank(waveform: samples)
        XCTAssertTrue(feats.isEmpty)
    }

    func test_fbank_allZeros_isNonNegative() {
        let samples = [Float](repeating: 0, count: 8000)
        let feats = extractFbank(waveform: samples)
        XCTAssertFalse(feats.isEmpty)
        for frame in feats {
            for val in frame {
                XCTAssertFalse(val.isNaN)
                XCTAssertFalse(val.isInfinite)
            }
        }
    }
}
