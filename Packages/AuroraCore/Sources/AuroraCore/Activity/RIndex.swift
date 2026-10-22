import Foundation

/// FMI's local magnetic activity value R, computed from 10-second magnetometer averages
/// (research.md R1).
public enum RIndex {
    /// 1350 / (3 components × 10 s): converts the mean summed difference to FMI's R scale.
    static let scale = 45.0
    /// Approximates FMI's instrument noise floor; fitted against FMI's published values.
    static let offset = 1.5
    static let sampleInterval = 10
    /// Number of differences in the window (10 minutes of 10 s samples).
    static let differenceCount = 60
    /// The newest half of the differences weighs twice as much as the older half.
    static let newestWeight = 2.0
    static let maxMissingSamples = 3

    /// R for the 10 minutes ending at `end`.
    ///
    /// FMI labels R with the end of the last 10 s averaging interval, so the window holds the 61
    /// samples at `end − 610 s … end − 10 s`. Samples outside the window are ignored. Returns nil
    /// when more than 3 samples in the window are missing (absent or with a missing component).
    public static func compute(samples: [MagnetometerSample], end: Date) -> Double? {
        let endSecond = Int(end.timeIntervalSince1970.rounded())
        var bySecond: [Int: (Double, Double, Double)] = [:]
        for sample in samples {
            guard let x = sample.x, let y = sample.y, let z = sample.z else { continue }
            bySecond[Int(sample.time.timeIntervalSince1970.rounded())] = (x, y, z)
        }

        // window[0] is the newest sample.
        let window = (1...differenceCount + 1).map { bySecond[endSecond - $0 * sampleInterval] }
        guard window.count(where: { $0 == nil }) <= maxMissingSamples else { return nil }

        var weightedSum = 0.0
        var weightSum = 0.0
        for k in 0..<differenceCount {
            guard let newer = window[k], let older = window[k + 1] else { continue }
            let weight = k < differenceCount / 2 ? newestWeight : 1
            weightedSum += weight * (abs(newer.0 - older.0) + abs(newer.1 - older.1) + abs(newer.2 - older.2))
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return max(0, scale * weightedSum / weightSum - offset)
    }
}
