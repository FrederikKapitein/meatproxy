import Testing
@testable import FactoryCore

/// A CEO's markdown reads as plain words, but a name it quotes stays exactly as written.
@Suite struct PlainTextTests {
    @Test func codeSpansKeepTheirUnderscores() {
        #expect(FactoryText.plain("denied `mcp__sentry__whoami`.") == "denied mcp__sentry__whoami.")
        #expect(FactoryText.plain("add `\"mcp__sentry__find_projects\"`") == "add \"mcp__sentry__find_projects\"")
        #expect(FactoryText.plain("in `*_test.go` files") == "in *_test.go files")
    }

    @Test func namesOutsideCodeKeepTheirUnderscores() {
        #expect(FactoryText.plain("ci_runner_job.service and mcp__sentry__whoami") == "ci_runner_job.service and mcp__sentry__whoami")
    }

    @Test func emphasisAndLinksBecomePlainWords() {
        #expect(FactoryText.plain("**Bold** and __strong__, *it* and _em_.") == "Bold and strong, it and em.")
        #expect(FactoryText.plain("See [PR #185](https://github.com/x/y/pull/185) now") == "See PR #185 now")
    }
}
