import Foundation

public enum ReportEndpoints {
    /// A bare JSON array, not a pageable envelope.
    public static func reasons(for kind: ReportTargetKind) -> Endpoint<[ReportReason]> {
        Endpoint(path: "report/\(kind.path)/reasons", auth: .required)
    }

    public static func send(to kind: ReportTargetKind, request: ReportRequest) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "report/\(kind.path)", body: .json(request), auth: .required)
    }
}
