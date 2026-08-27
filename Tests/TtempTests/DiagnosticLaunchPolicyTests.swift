import XCTest

final class DiagnosticLaunchPolicyTests: XCTestCase {
    private let uuid = "E6F7877C-EDAD-4157-8018-49733B072152"
    private let hosted = ["TTEMP_DISPOSABLE_CI": "1", "GITHUB_ACTIONS": "true",
                          "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_OS": "macOS"]

    func testDedicatedIdentifiersAllowBothDiagnosticModes() {
        for identifier in [DiagnosticLaunchPolicy.developmentIdentifier,
                           "com.am921.ttemp.runtime-test.\(uuid)",
                           "com.am921.ttemp.update-test.\(uuid.lowercased())"] {
            for interactive in [false, true] {
                XCTAssertTrue(DiagnosticLaunchPolicy.allows(identifier: identifier, interactive: interactive,
                                                           disposableCI: false, environment: [:]))
            }
        }
    }

    func testProductionCannotBeDiagnosedLocallyEvenWithAnOptIn() {
        for interactive in [false, true] {
            for optIn in [false, true] {
                XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: interactive,
                                                            disposableCI: optIn, environment: [:]))
            }
        }
    }

    func testHostedProductionRequiresBothExplicitOptInsAndAutomaticMode() {
        XCTAssertTrue(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: false,
                                                   disposableCI: true, environment: hosted))
        XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: false,
                                                    disposableCI: false, environment: hosted))
        XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: true,
                                                    disposableCI: true, environment: hosted))
        for key in hosted.keys {
            var missing = hosted
            missing.removeValue(forKey: key)
            XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: false,
                                                        disposableCI: true, environment: missing), key)
        }
    }

    func testSelfHostedAndWrongPlatformAreRejected() {
        for (key, value) in [("RUNNER_ENVIRONMENT", "self-hosted"), ("RUNNER_OS", "Linux"),
                             ("TTEMP_DISPOSABLE_CI", "true"), ("GITHUB_ACTIONS", "false")] {
            var environment = hosted
            environment[key] = value
            XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: "com.am921.ttemp", interactive: false,
                                                        disposableCI: true, environment: environment))
        }
    }

    func testUnknownMissingAndPrefixOnlyIdentifiersAreRejected() {
        let invalid: [String?] = [nil, "", "com.am921.ttemp.tests", "com.am921.ttemp.development.extra",
                                 "com.am921.ttemp.runtime-test.", "com.am921.ttemp.update-test.invalid",
                                 "com.am921.ttemp.runtime-test.\(uuid)\n",
                                 "com.am921.ttemp.runtime-test.\(uuid)-extra",
                                 "com.am921.ttemp.runtime-test.{\(uuid)}", "org.example.Ttemp"]
        for identifier in invalid {
            XCTAssertFalse(DiagnosticLaunchPolicy.isTestIdentifier(identifier))
            XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: identifier, interactive: false,
                                                        disposableCI: true, environment: hosted))
        }
    }

    func testCIOverrideIsNotAcceptedForTestIdentifiers() {
        XCTAssertFalse(DiagnosticLaunchPolicy.allows(identifier: DiagnosticLaunchPolicy.developmentIdentifier,
                                                    interactive: false, disposableCI: true, environment: hosted))
    }
}
