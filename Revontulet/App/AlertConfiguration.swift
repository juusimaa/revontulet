import Foundation

/// Where the alert service is, from the `AlertsBaseURL` Info.plist key (set from the
/// `ALERTS_BASE_URL` build setting in project.yml).
enum AlertConfiguration {
    static var baseURL: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AlertsBaseURL") as? String,
              let url = URL(string: value), url.scheme != nil
        else { preconditionFailure("AlertsBaseURL missing from Info.plist; check ALERTS_BASE_URL in project.yml") }
        return url
    }
}
