import Foundation
@testable import SwiftMCP

struct TestRequest: MCPRequest {
    typealias Response = TestResponse
    typealias Params = EmptyParams

    static let method = "test"

    var params: EmptyParams = EmptyParams()
}

struct TestResponse: MCPResponse {
    typealias Request = TestRequest
    var _meta: [String: AnyCodable]?
    var result: String
}

struct TestNotification: MCPNotification {
    let method = "test"
    var params: [String: AnyCodable]

    init(params: [String: AnyCodable] = [:]) {
        self.params = params
    }
}
