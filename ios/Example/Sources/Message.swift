import Foundation

enum MessageRole {
    case user
    case assistant
}

struct Message {
    let id: UUID
    let role: MessageRole
    let content: String
}
