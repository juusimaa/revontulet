// AlertServer: routes, storage, APNs dispatch and the evaluation loop of the alert service.
//
// Alert rules, zones and message keys live in AuroraCore; this library only wires them to
// HTTP, SQLite and APNs.

import AuroraCore

/// Version of the alert service.
public enum AlertServer {
    public static let version = "0.1.0"
}
