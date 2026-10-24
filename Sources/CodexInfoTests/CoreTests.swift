import Foundation
import CodexInfoCore

func registerCoreTests() {
    test("CredentialStore parses top-level access token") { context in
        let data = #"{"access_token":"tok_test"}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_test")
    }

    test("CredentialStore parses nested tokens access token") { context in
        let data = #"{"tokens":{"access_token":"tok_nested"}}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_nested")
    }

    test("CredentialStore rejects missing token") { context in
        let data = #"{"tokens":{}}"#.data(using: .utf8)!
        context.expectThrows(try FileCredentialStore.parse(data))
    }
}
