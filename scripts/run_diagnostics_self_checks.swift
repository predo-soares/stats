import Foundation

@main
struct RunDiagnosticsSelfChecks {
    static func main() async {
        let report = await DiagnosticsSelfChecks().run()
        print(report.summary)

        for check in report.passedChecks {
            print("PASS: \(check)")
        }

        for check in report.failedChecks {
            print("FAIL: \(check)")
        }

        if !report.isSuccessful {
            exit(1)
        }
    }
}
