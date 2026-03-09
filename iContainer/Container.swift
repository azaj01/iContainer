import Foundation

struct Container: Identifiable, Equatable {
    let id: String
    let name: String
    var status: ContainerStatus
    let image: String?
    let ipAddress: String?
}

enum ContainerStatus: Equatable {
    case running
    case stopped
} 
