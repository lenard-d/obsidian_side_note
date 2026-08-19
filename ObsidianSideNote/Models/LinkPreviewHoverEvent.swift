import CoreGraphics

struct LinkPreviewHoverEvent: Equatable {
    enum Phase: String {
        case entered
        case exited
    }

    enum LinkKind: String {
        case wiki
        case markdown
    }

    let phase: Phase
    let sessionID: String
    let kind: LinkKind
    let target: String
    let anchorScreenRect: CGRect
}
