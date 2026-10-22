import Testing
@testable import AuroraCore

@Suite("Chance rules (contracts/chance-rules.md)")
struct ChanceCalculatorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let number: Int
        let activity: ActivityLevel
        let darkness: Darkness
        let clouds: CloudCondition
        let level: ChanceLevel
        let limiting: LimitingFactor?
        let reason: ChanceReason

        var testDescription: String { "case \(number)" }
    }

    static let referenceCases: [Case] = [
        Case(number: 1, activity: .probable, darkness: .dark, clouds: .clear, level: .high, limiting: nil, reason: .goodConditions),
        Case(number: 2, activity: .probable, darkness: .tooLight, clouds: .clear, level: .none, limiting: .light, reason: .tooLight),
        Case(number: 3, activity: .probable, darkness: .dark, clouds: .overcast, level: .none, limiting: .clouds, reason: .overcast),
        Case(number: 4, activity: .probable, darkness: .twilight, clouds: .clear, level: .moderate, limiting: .twilight, reason: .twilight),
        Case(number: 5, activity: .probable, darkness: .dark, clouds: .partly, level: .moderate, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 6, activity: .probable, darkness: .twilight, clouds: .partly, level: .low, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 7, activity: .possible, darkness: .dark, clouds: .clear, level: .moderate, limiting: .activity, reason: .someActivity),
        Case(number: 8, activity: .possible, darkness: .twilight, clouds: .partly, level: .none, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 9, activity: .unlikely, darkness: .dark, clouds: .clear, level: .low, limiting: .activity, reason: .lowActivity),
        Case(number: 10, activity: .unlikely, darkness: .twilight, clouds: .clear, level: .none, limiting: .twilight, reason: .twilight),
        Case(number: 11, activity: .probable, darkness: .dark, clouds: .unknown, level: .high, limiting: nil, reason: .goodConditions),
        Case(number: 12, activity: .unlikely, darkness: .tooLight, clouds: .overcast, level: .none, limiting: .light, reason: .tooLight),
    ]

    @Test(arguments: referenceCases)
    func referenceCase(_ c: Case) {
        let chance = ChanceCalculator.chance(activity: c.activity, darkness: c.darkness, clouds: c.clouds)

        #expect(chance.level == c.level)
        #expect(chance.limitingFactor == c.limiting)
        #expect(chance.cloudsIncluded == (c.clouds != .unknown))
        #expect(ChanceCalculator.reason(for: chance, activity: c.activity, clouds: c.clouds) == c.reason)
    }

    @Test func everyCombinationGivesALevelNoHigherThanActivityAllows() {
        for activity in ActivityLevel.allCases {
            for darkness in Darkness.allCases {
                for clouds in CloudCondition.allCases {
                    let chance = ChanceCalculator.chance(activity: activity, darkness: darkness, clouds: clouds)
                    #expect(chance.level <= ChanceCalculator.startingLevel(activity))
                    #expect(chance.limitingFactor != nil || chance.level == .high)
                }
            }
        }
    }

    @Test(arguments: [
        (Optional(0), CloudCondition.clear), (3, .clear),
        (4, .partly), (6, .partly),
        (7, .overcast), (8, .overcast),
        (9, .unknown), (nil, .unknown),
    ])
    func cloudMapping(octas: Int?, expected: CloudCondition) {
        #expect(ChanceCalculator.cloudCondition(octas: octas) == expected)
    }

    @Test func reasonKeys() {
        #expect(ChanceReason.tooLight.key == "reason.tooLight")
        #expect(ChanceReason.goodConditions.key == "reason.goodConditions")
        #expect(Set(ChanceReason.allCases.map(\.key)).count == ChanceReason.allCases.count)
    }
}
