import Foundation

/// Fast, locale-free conversion between `Date` and FMI's `YYYY-MM-DDTHH:MM:SSZ` timestamps.
enum UTCTime {
    /// Parses `YYYY-MM-DDTHH:MM:SS` followed by `Z` (fractional seconds are not used by FMI).
    static func parse<C: Collection>(_ text: C) -> Date? where C.Element == UInt8 {
        let b = Array(text)
        guard b.count >= 20, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T"),
              b[13] == UInt8(ascii: ":"), b[16] == UInt8(ascii: ":"), b[19] == UInt8(ascii: "Z")
        else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                let digit = Int(b[i]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3_600 + minute * 60 + second))
    }

    static func parse(_ text: String) -> Date? {
        parse(Array(text.utf8))
    }

    /// Formats whole seconds (fractions are truncated) as `YYYY-MM-DDTHH:MM:SSZ`.
    static func format(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSince1970.rounded(.down))
        let days = seconds.floorDiv(86_400)
        let secondOfDay = seconds - days * 86_400
        let (year, month, day) = civilFromDays(days)
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T"
            + "\(pad(secondOfDay / 3_600, 2)):\(pad(secondOfDay % 3_600 / 60, 2)):\(pad(secondOfDay % 60, 2))Z"
    }

    // Howard Hinnant's civil-date algorithms (proleptic Gregorian calendar).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = y.floorDiv(400)
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = z.floorDiv(146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

extension Int {
    fileprivate func floorDiv(_ divisor: Int) -> Int {
        let quotient = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }
}
