//
//  PowerMeter.swift
//  ishare
//
//  Created by Adrian Castro on 29.07.23.
//

import Accelerate
import AVFoundation
import Foundation

struct AudioLevels: Equatable, Sendable {
    static let zero = AudioLevels(level: 0, peakLevel: 0)
    let level: Float
    let peakLevel: Float
}

// The protocol for the object that provides peak and average power levels to adopt.
protocol AudioLevelProvider {
    var levels: AudioLevels { get }
}

class PowerMeter: AudioLevelProvider {
    private let kMinLevel: Float = 0.000_000_01 // -160 dB

    private struct PowerLevels {
        let average: Float
        let peak: Float
    }

    private var values = [PowerLevels]()
    private var lastUpdate = Date.distantPast
    private let staleInterval: TimeInterval = 0.5

    private var meterTableAverage = MeterTable()
    private var meterTablePeak = MeterTable()

    var levels: AudioLevels {
        if values.isEmpty || Date().timeIntervalSince(lastUpdate) > staleInterval { return AudioLevels(level: 0.0, peakLevel: 0.0) }
        return AudioLevels(
            level: meterTableAverage.valueForPower(values[0].average),
            peakLevel: meterTablePeak.valueForPower(values[0].peak))
    }

    func processSilence() {
        if values.isEmpty { return }
        values = []
    }

    // Calculates the average (rms) and peak level of each channel in the PCM buffer and caches data.
    func process(buffer: AVAudioPCMBuffer) {
        var powerLevels = [PowerLevels]()
        let channelCount = Int(buffer.format.channelCount)
        let length = vDSP_Length(buffer.frameLength)

        if let floatData = buffer.floatChannelData {
            for channel in 0 ..< channelCount {
                powerLevels.append(calculatePowers(data: floatData[channel], strideFrames: buffer.stride, length: length))
            }
        } else if let int16Data = buffer.int16ChannelData {
            for channel in 0 ..< channelCount {
                // Convert the data from int16 to float values before calculating the power values.
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(buffer.frameLength))
                vDSP_vflt16(int16Data[channel], buffer.stride, &floatChannelData, buffer.stride, length)
                var scalar = Float(INT16_MAX)
                vDSP_vsdiv(floatChannelData, buffer.stride, &scalar, &floatChannelData, buffer.stride, length)

                powerLevels.append(calculatePowers(data: floatChannelData, strideFrames: buffer.stride, length: length))
            }
        } else if let int32Data = buffer.int32ChannelData {
            for channel in 0 ..< channelCount {
                // Convert the data from int32 to float values before calculating the power values.
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(buffer.frameLength))
                vDSP_vflt32(int32Data[channel], buffer.stride, &floatChannelData, buffer.stride, length)
                var scalar = Float(INT32_MAX)
                vDSP_vsdiv(floatChannelData, buffer.stride, &scalar, &floatChannelData, buffer.stride, length)

                powerLevels.append(calculatePowers(data: floatChannelData, strideFrames: buffer.stride, length: length))
            }
        }
        values = powerLevels
        lastUpdate = Date()
    }

    private func calculatePowers(data: UnsafePointer<Float>, strideFrames: Int, length: vDSP_Length) -> PowerLevels {
        var max: Float = 0.0
        vDSP_maxv(data, strideFrames, &max, length)
        if max < kMinLevel {
            max = kMinLevel
        }

        var rms: Float = 0.0
        vDSP_rmsqv(data, strideFrames, &rms, length)
        if rms < kMinLevel {
            rms = kMinLevel
        }

        return PowerLevels(average: 20.0 * log10(rms), peak: 20.0 * log10(max))
    }
}

private struct MeterTable {
    // The decibel value of the minimum displayed amplitude.
    private let kMinDB: Float = -60.0

    // The table needs to be large enough so that there are no large gaps in the response.
    private let tableSize = 300

    private let scaleFactor: Float
    private var meterTable = [Float]()

    init() {
        let dbResolution = kMinDB / Float(tableSize - 1)
        scaleFactor = 1.0 / dbResolution

        // This controls the curvature of the response.
        // 2.0 is the square root, 3.0 is the cube root.
        let root: Float = 2.0

        let rroot = 1.0 / root
        let minAmp = dbToAmp(dBValue: kMinDB)
        let ampRange = 1.0 - minAmp
        let invAmpRange = 1.0 / ampRange

        for index in 0 ..< tableSize {
            let decibels = Float(index) * dbResolution
            let amp = dbToAmp(dBValue: decibels)
            let adjAmp = (amp - minAmp) * invAmpRange
            meterTable.append(powf(adjAmp, rroot))
        }
    }

    private func dbToAmp(dBValue: Float) -> Float {
        powf(10.0, 0.05 * dBValue)
    }

    func valueForPower(_ power: Float) -> Float {
        if power < kMinDB {
            return 0.0
        } else if power >= 0.0 {
            return 1.0
        } else {
            let index = Int(power) * Int(scaleFactor)
            return meterTable[index]
        }
    }
}
