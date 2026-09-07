import XCTest

/// Supply-chain policy for `.github/workflows/*.yml`, enforced from the test suite because the
/// failure it prevents is invisible at runtime and only visible in the YAML:
///
/// 1. Every external `uses:` pins a full 40-character commit SHA with a `# vX.Y.Z` comment, so an
///    upstream tag or branch that moves cannot change what runs in a job holding our secrets.
///    (`actions/dependency-review-action@v5` was a mutable *branch*, not even a tag.)
/// 2. Every workflow declares a top-level `permissions:` block and none of it grants `write`.
///    Write scopes belong on the individual job that publishes, deploys, or dispatches, so a
///    build job running third-party actions cannot reach the release channel.
///
/// Dependabot rewrites both the SHA and the trailing version comment when it bumps an action,
/// so this ratchet costs nothing to maintain — it only blocks a hand-written mutable tag.
final class WorkflowPolicyTests: XCTestCase {
    /// The load-bearing part is the 40-hex SHA. The trailing `# vN…` comment is what makes a
    /// diff readable and is what Dependabot rewrites; anything may follow the version, because
    /// `github/codeql-action` documents its pins as `# v4 / codeql-bundle-v2.26.4`.
    private static let pinnedUses = try? NSRegularExpression(
        pattern: #"^\s*-?\s*uses:\s*[\w.\-]+/[\w.\-/]+@[0-9a-f]{40}\s+#\s*v\d+(\.\d+)*(\s.*)?$"#
    )

    private func workflowFiles() throws -> [URL] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/OrifoldTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent(".github/workflows")
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["yml", "yaml"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no workflow files found under \(directory.path)")
        return files
    }

    private func lines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
    }

    func testEveryActionReferenceIsPinnedToACommitSHAWithAVersionComment() throws {
        let expression = try XCTUnwrap(Self.pinnedUses)
        var violations: [String] = []
        var pinned = 0
        for file in try workflowFiles() {
            for (index, line) in try lines(of: file).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("uses:") || trimmed.hasPrefix("- uses:") else { continue }
                // A local reusable workflow comes from the same immutable commit as
                // its caller. Permit only the reviewed CI gate, never a mutable remote ref.
                if trimmed == "uses: ./.github/workflows/ci.yml" {
                    XCTAssertEqual(file.lastPathComponent, "release.yml")
                    continue
                }
                if expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil {
                    violations.append("\(file.lastPathComponent):\(index + 1): \(trimmed)")
                } else {
                    pinned += 1
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "action references must read `owner/repo@<40-hex-sha> # vX.Y.Z`:\n" + violations.joined(separator: "\n")
        )
        XCTAssertGreaterThan(pinned, 0, "the scan found no action references at all — it is not proving anything")
    }

    func testNoWorkflowGrantsWriteAtWorkflowScope() throws {
        var violations: [String] = []
        for file in try workflowFiles() {
            // The top-level block starts at column 0; job-level blocks are indented, so they
            // never open one here. The block runs to the next unindented line.
            var block: [(number: Int, text: String)] = []
            var insideBlock = false
            for (index, line) in try lines(of: file).enumerated() {
                if line.hasPrefix("permissions:") {
                    insideBlock = true
                    block.append((index + 1, line))
                    continue
                }
                guard insideBlock else { continue }
                if line.isEmpty || line.first?.isWhitespace == true {
                    block.append((index + 1, line))
                } else {
                    insideBlock = false
                }
            }
            guard !block.isEmpty else {
                violations.append("\(file.lastPathComponent): no top-level `permissions:` block")
                continue
            }
            for entry in block where (entry.text.components(separatedBy: "#").first ?? "").contains("write") {
                let grant = entry.text.trimmingCharacters(in: .whitespaces)
                violations.append("\(file.lastPathComponent):\(entry.number): \(grant)")
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "workflow-scope permissions must stay read-only; grant write on the job that needs it:\n"
                + violations.joined(separator: "\n")
        )
    }

    func testReleasePublishesOnlyAfterValidatingTheExactBuiltCommit() throws {
        let files = try workflowFiles()
        let release = try String(
            contentsOf: XCTUnwrap(files.first { $0.lastPathComponent == "release.yml" }), encoding: .utf8
        )
        let ci = try String(
            contentsOf: XCTUnwrap(files.first { $0.lastPathComponent == "ci.yml" }), encoding: .utf8
        )
        func job(_ name: String) throws -> String {
            let start = try XCTUnwrap(release.range(of: "\n  \(name):\n"))
            let remainder = release[start.upperBound...]
            let next = remainder.range(of: #"\n  [a-z][a-z-]*:\n"#, options: .regularExpression)
            return String(remainder[..<(next?.lowerBound ?? remainder.endIndex)])
        }
        let resolve = try job("resolve")
        XCTAssertTrue(resolve.contains("ref: ${{ inputs.release_tag || github.sha }}"))
        XCTAssertTrue(resolve.contains("git rev-parse HEAD"))
        let validation = try job("validate")
        XCTAssertTrue(validation.contains("needs: resolve"))
        XCTAssertTrue(validation.contains("uses: ./.github/workflows/ci.yml"))
        XCTAssertTrue(validation.contains("revision: ${{ needs.resolve.outputs.revision }}"))
        let build = try job("build")
        XCTAssertTrue(build.contains("needs: [resolve, validate]"))
        XCTAssertTrue(build.contains("ref: ${{ needs.resolve.outputs.revision }}"))
        for name in ["validate", "build", "publish-tagged", "publish-rolling"] {
            let content = try job(name)
            XCTAssertFalse(content.contains("always()"), "\(name) must not bypass failed dependencies")
            XCTAssertFalse(content.contains("continue-on-error: true"), "\(name) must fail closed")
        }
        for name in ["publish-tagged", "publish-rolling"] {
            XCTAssertTrue(try job(name).contains("needs: build"))
        }
        XCTAssertTrue(ci.contains("workflow_call:"))
        XCTAssertTrue(ci.contains("ref: ${{ inputs.revision || github.sha }}"))
        XCTAssertTrue(ci.contains("git diff --exit-code --"), "release validation must include generated-project parity")
        XCTAssertTrue(ci.contains("- name: Xcode tests"), "release validation must include the full hosted test gate")
        XCTAssertFalse(ci.contains("continue-on-error: true"))
    }
}
