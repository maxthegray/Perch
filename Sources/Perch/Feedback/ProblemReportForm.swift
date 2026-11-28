import Foundation

/// Sends a problem report straight to a Google Form, so reporting needs no browser,
/// mail app or account. Posting to the form's `formResponse` endpoint is exactly what
/// its own submit button does; each answer is keyed by the question's `entry.` id.
struct ProblemReportForm: Sendable {
    let formID: String
    let whatHappenedEntry: String
    let reportEntry: String
    let versionEntry: String

    /// Nil hides Report a Problem everywhere.
    static let perch: ProblemReportForm? = ProblemReportForm(
        formID: "1FAIpQLSfbGkb9FDTJtdwnE3tthyskxabqCBqyOzslaf1N0JTLFPyrPg",
        whatHappenedEntry: "entry.1853355068",
        reportEntry: "entry.996802952",
        versionEntry: "entry.2002726552"
    )

    var submitURL: URL {
        URL(string: "https://docs.google.com/forms/d/e/\(formID)/formResponse")!
    }

    /// Google Forms caps an answer at a little over 100,000 characters.
    static let maxAnswerLength = 90_000

    func request(whatHappened: String, report: String, version: String) -> URLRequest {
        var request = URLRequest(url: submitURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            (whatHappenedEntry, whatHappened),
            (reportEntry, String(report.suffix(Self.maxAnswerLength))),
            (versionEntry, version)
        ]
        request.httpBody = fields
            .map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    func submit(whatHappened: String, report: String, version: String) async throws {
        let (_, response) = try await URLSession.shared.data(
            for: request(whatHappened: whatHappened, report: report, version: version)
        )
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
