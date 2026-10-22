/// Why the chance is what it is; shown with the level as "<Level> – <reason>".
public enum ChanceReason: String, Sendable, Hashable, Codable, CaseIterable {
    case tooLight
    case overcast
    case partlyCloudy
    case twilight
    case lowActivity
    case someActivity
    case goodConditions

    /// Localisation key, e.g. `reason.tooLight`.
    public var key: String { "reason.\(rawValue)" }
}

/// The fixed rule that combines activity, darkness and clouds (contracts/chance-rules.md).
public enum ChanceCalculator {
    public static func chance(activity: ActivityLevel, darkness: Darkness, clouds: CloudCondition) -> Chance {
        let cloudsIncluded = clouds != .unknown
        if darkness == .tooLight {
            return Chance(level: .none, limitingFactor: .light, cloudsIncluded: cloudsIncluded)
        }
        if clouds == .overcast {
            return Chance(level: .none, limitingFactor: .clouds, cloudsIncluded: cloudsIncluded)
        }

        var level = startingLevel(activity)
        var limitingFactor: LimitingFactor?
        if darkness == .twilight {
            level = level.lowered()
            limitingFactor = .twilight
        }
        if clouds == .partly {
            level = level.lowered()
            limitingFactor = .clouds
        }
        if limitingFactor == nil, level != .high {
            limitingFactor = .activity
        }
        return Chance(level: level, limitingFactor: limitingFactor, cloudsIncluded: cloudsIncluded)
    }

    /// 0–3 octas clear, 4–6 partly, 7–8 overcast; 9 (sky obscured) or missing unknown.
    public static func cloudCondition(octas: Int?) -> CloudCondition {
        guard let octas else { return .unknown }
        switch octas {
        case 0...3: return .clear
        case 4...6: return .partly
        case 7...8: return .overcast
        default: return .unknown
        }
    }

    public static func reason(for chance: Chance, activity: ActivityLevel, clouds: CloudCondition) -> ChanceReason {
        switch chance.limitingFactor {
        case .light: .tooLight
        case .clouds: clouds == .overcast ? .overcast : .partlyCloudy
        case .twilight: .twilight
        case .activity: activity == .unlikely ? .lowActivity : .someActivity
        case nil: .goodConditions
        }
    }

    static func startingLevel(_ activity: ActivityLevel) -> ChanceLevel {
        switch activity {
        case .unlikely: .low
        case .possible: .moderate
        case .probable: .high
        }
    }
}

extension ChanceLevel {
    fileprivate func lowered() -> ChanceLevel {
        ChanceLevel(rawValue: rawValue - 1) ?? .none
    }
}
