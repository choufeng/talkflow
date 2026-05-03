import Foundation
import Accelerate

// MARK: - fbank 参数（对标 kaldi-native-fbank / TalkShow）

private let kSampleRate: Double = 16000
private let kFrameLengthMs: Double = 25
private let kFrameShiftMs: Double = 10
private let kNumMelBins = 80
private let kLowFreq: Double = 20
private let kHighFreq: Double = 7600

// MARK: - 公共 API

/// 提取 fbank 特征
/// - Parameter waveform: 16kHz 单声道 PCM 样本（范围 -1.0~1.0）
/// - Returns: [帧数 × 80维]
func extractFbank(waveform: [Float]) -> [[Float]] {
    let frameLen = Int(kSampleRate * kFrameLengthMs / 1000)    // 400
    let frameShift = Int(kSampleRate * kFrameShiftMs / 1000)    // 160
    let fftN = 1 << Int(ceil(log2(Double(frameLen))))           // 512

    guard waveform.count >= frameLen else { return [] }

    let numFrames = (waveform.count - frameLen) / frameShift + 1
    let melFilterbank = precomputeMelFilterbank(fftN: fftN)
    let log2n = vDSP_Length(log2(Double(fftN)))
    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
        return []
    }
    defer { vDSP_destroy_fftsetup(fftSetup) }

    // Hamming 窗
    var window = [Float](repeating: 0, count: frameLen)
    vDSP_hamm_window(&window, vDSP_Length(frameLen), 0)

    var result = [[Float]]()
    result.reserveCapacity(numFrames)

    for i in 0..<numFrames {
        let start = i * frameShift
        let end = min(start + frameLen, waveform.count)
        var frame = Array(waveform[start..<end])
        if frame.count < frameLen {
            frame.append(contentsOf: [Float](repeating: 0, count: frameLen - frame.count))
        }

        // 去直流
        var mean: Float = 0
        vDSP_meanv(frame, 1, &mean, vDSP_Length(frameLen))
        let negMean = -mean
        var dcRemoved = [Float](repeating: 0, count: frameLen)
        // vDSP_vsadd: dst[i] = src[i] + scalar
        dcRemoved.withUnsafeMutableBufferPointer { dst in
            frame.withUnsafeBufferPointer { src in
                var s = negMean
                vDSP_vsadd(src.baseAddress!, 1, &s, dst.baseAddress!, 1, vDSP_Length(frameLen))
            }
        }

        // 加窗
        var windowed = [Float](repeating: 0, count: frameLen)
        windowed.withUnsafeMutableBufferPointer { dst in
            dcRemoved.withUnsafeBufferPointer { src in
                window.withUnsafeBufferPointer { win in
                    vDSP_vmul(src.baseAddress!, 1, win.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(frameLen))
                }
            }
        }

        let fbank = computeFbankFrame(windowed, fftN: fftN, fftSetup: fftSetup, melFilterbank: melFilterbank)
        result.append(fbank)
    }

    return result
}

// MARK: - Mel 滤波器组

private func precomputeMelFilterbank(fftN: Int) -> [[Float]] {
    let numBins = fftN / 2 + 1

    let melLow = hzToMel(Float(kLowFreq))
    let melHigh = hzToMel(Float(kHighFreq))
    var melPoints = (0..<(kNumMelBins + 2)).map { i -> Float in
        let mel = melLow + Float(i) * (melHigh - melLow) / Float(kNumMelBins + 1)
        return melToHz(mel)
    }
    melPoints = melPoints.map { $0 * Float(fftN) / Float(kSampleRate) }

    return (0..<kNumMelBins).map { m in
        var filter = [Float](repeating: 0, count: numBins)
        for k in 0..<numBins {
            let fk = Float(k)
            if fk < melPoints[m] {
                filter[k] = 0
            } else if fk <= melPoints[m + 1] {
                let denom = melPoints[m + 1] - melPoints[m]
                filter[k] = denom > 0 ? (fk - melPoints[m]) / denom : 0
            } else if fk <= melPoints[m + 2] {
                let denom = melPoints[m + 2] - melPoints[m + 1]
                filter[k] = denom > 0 ? (melPoints[m + 2] - fk) / denom : 0
            } else {
                filter[k] = 0
            }
        }
        return filter
    }
}

// MARK: - 单帧 fbank

private func computeFbankFrame(
    _ frame: [Float],
    fftN: Int,
    fftSetup: FFTSetup,
    melFilterbank: [[Float]]
) -> [Float] {
    let numBins = fftN / 2 + 1

    // 填充到 fftN
    var padded = frame + [Float](repeating: 0, count: fftN - frame.count)

    // vDSP FFT 实数输入 → 输出需要 fftN/2 + 1 个复数
    var realPart = [Float](repeating: 0, count: numBins)
    var imagPart = [Float](repeating: 0, count: numBins)

    realPart.withUnsafeMutableBufferPointer { rp in
        imagPart.withUnsafeMutableBufferPointer { ip in
            padded.withUnsafeMutableBufferPointer { pb in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                pb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftN / 2) { complex in
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftN / 2))
                }
            }
        }
    }

    realPart.withUnsafeMutableBufferPointer { rp in
        imagPart.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(fftN))), FFTDirection(kFFTDirection_Forward))
        }
    }

    // 功率谱 = (real^2 + imag^2) / fftN
    var powerSpectrum = [Float](repeating: 0, count: numBins)
    for k in 0..<numBins {
        powerSpectrum[k] = (realPart[k] * realPart[k] + imagPart[k] * imagPart[k]) / Float(fftN)
    }

    // Mel 滤波器组
    var fbank = [Float](repeating: 0, count: kNumMelBins)
    for m in 0..<kNumMelBins {
        var sum: Float = 0
        powerSpectrum.withUnsafeBufferPointer { ps in
            melFilterbank[m].withUnsafeBufferPointer { mf in
                vDSP_dotpr(ps.baseAddress!, 1, mf.baseAddress!, 1, &sum, vDSP_Length(numBins))
            }
        }
        fbank[m] = max(sum, 1e-10)
    }

    // 对数
    var logFbank = [Float](repeating: 0, count: kNumMelBins)
    var count = Int32(kNumMelBins)
    vvlogf(&logFbank, fbank, &count)

    return logFbank
}

// MARK: - Mel 尺度转换

private func hzToMel(_ hz: Float) -> Float {
    1127.0 * log(1.0 + hz / 700.0)
}

private func melToHz(_ mel: Float) -> Float {
    700.0 * (exp(mel / 1127.0) - 1.0)
}
