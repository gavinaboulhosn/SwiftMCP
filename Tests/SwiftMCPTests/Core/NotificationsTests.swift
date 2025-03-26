import Foundation
import Testing

@testable import SwiftMCP

@Suite("Notifications Serialization Tests")
struct NotificationsTests {
    @Test("Decode Cancelled Notification")
    func decodeCancelledNotification() throws {
        let cancelledNotificationJSON = """
            {
              "jsonrpc": "2.0",
              "method": "notifications/cancelled",
              "params": {
                "requestId": 42,
                "reason": "User aborted the operation"
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self,
            from: cancelledNotificationJSON)

        guard case .notification(let notif) = message else {
            Issue.record("Expected a notification message")
            return
        }

        if let cancelledNotification = notif as? CancelledNotification {
            let params = cancelledNotification.params as? CancelledNotification.Params
            #expect(params?.requestId == .int(42))
            #expect(params?.reason == "User aborted the operation")
        } else {
            Issue.record("Notification is not a CancelledNotification")
        }
    }

    @Test("Decode Prompt List Changed Notification")
    func decodePromptListChangedNotification() throws {
        let promptListChangedNotificationJSON = """
            {
              "jsonrpc": "2.0",
              "method": "notifications/prompts/list_changed",
              "params": {
                "_meta": {
                  "reason": "new prompts added"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self,
            from: promptListChangedNotificationJSON)

        guard case .notification(let notif) = message else {
            Issue.record("Expected a notification message")
            return
        }

        if let promptListChangedNotification = notif as? PromptListChangedNotification {
            let params =
                promptListChangedNotification.params as? PromptListChangedNotification.Params
            if let meta = params?._meta {
                #expect((meta["reason"]?.value as? String) == "new prompts added")
            } else {
                Issue.record("Missing _meta in prompt list changed notification params")
            }
        } else {
            Issue.record("Notification is not a PromptListChangedNotification")
        }
    }
}

