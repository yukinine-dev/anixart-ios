import Foundation

extension ProfileDeletionResponse {
    /// Only for `profile/deletion/status`, not the request/cancel responses.
    /// Android sets its has-request flag from the code, not from nullable dates.
    public var hasDeletionRequest: Bool? {
        switch code {
        case 0: return true
        case 3: return false
        default: return nil
        }
    }
}

public struct ProfileEnforcementAppealRequest: Codable, Hashable, Sendable {
    public var message: String?
    public init(message: String?) { self.message = message }
    private enum CodingKeys: String, CodingKey { case message }

    /// The APK sends a request body even for an adjustment without a message.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(message, forKey: .message)
    }
}

extension WireEnumValue {
    public func matches(name: String, ordinal: Int) -> Bool {
        switch self {
        case .name(let value): return value.caseInsensitiveCompare(name) == .orderedSame
        case .ordinal(let value): return value == ordinal
        }
    }
}

extension ProfileEnforcement {
    public var appealStatusTitle: String {
        guard let appealStatus else { return "Статус уточняется" }
        if appealStatus.matches(name: "NOT_SUBMITTED", ordinal: 1) { return "Не подана" }
        if appealStatus.matches(name: "SUBMITTED", ordinal: 2) { return "На рассмотрении" }
        if appealStatus.matches(name: "ACCEPTED", ordinal: 3) { return "Принята" }
        if appealStatus.matches(name: "REJECTED", ordinal: 4) { return "Отклонена" }
        return "Статус уточняется"
    }

    public var isAdjustment: Bool { appealType?.matches(name: "ADJUSTMENT", ordinal: 3) == true }

    public func mayAppeal(at date: Date = .now) -> Bool {
        guard isRevoked != true,
              appealStatus?.matches(name: "NOT_SUBMITTED", ordinal: 1) == true,
              let expires = appealExpiresTimestamp, TimeInterval(expires) > date.timeIntervalSince1970
        else { return false }
        return isAdjustment || appealType?.matches(name: "MESSAGE", ordinal: 2) == true
    }
}
