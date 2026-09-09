import SceneKit
import AppKit

/// An SCNView that reports drag gestures and simple clicks back to its
/// controller, since the whole point of BoxBucko is a draggable desktop pet.
final class PetView: SCNView {
    var onDragStart: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)? // ending mouse velocity, points/sec
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var dragStartScreenPoint: NSPoint = .zero
    private var lastDragScreenPoint: NSPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var didDrag = false
    private var velocity: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartScreenPoint = NSEvent.mouseLocation
        lastDragScreenPoint = dragStartScreenPoint
        lastDragTime = event.timestamp
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - lastDragScreenPoint.x
        let dy = current.y - lastDragScreenPoint.y
        if abs(current.x - dragStartScreenPoint.x) > 3 || abs(current.y - dragStartScreenPoint.y) > 3 {
            didDrag = true
        }
        let dt = max(event.timestamp - lastDragTime, 1.0 / 120.0)
        velocity = CGPoint(x: dx / CGFloat(dt), y: dy / CGFloat(dt))
        lastDragScreenPoint = current
        lastDragTime = event.timestamp
        if didDrag {
            onDrag?(CGSize(width: dx, height: dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnd?(velocity)
        } else if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}
