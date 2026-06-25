import Foundation

public final class LabyrinthFrame: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var objects: [LabyrinthCanvasObject]
    public weak var parent: LabyrinthFrame?
    public var indexInParent: LabyrinthGridIndex?
    public var children: [LabyrinthGridIndex: LabyrinthFrame]
    public var depthFromRoot: Int

    public init(id: UUID = UUID(),
                objects: [LabyrinthCanvasObject] = [],
                parent: LabyrinthFrame? = nil,
                indexInParent: LabyrinthGridIndex? = nil,
                children: [LabyrinthGridIndex: LabyrinthFrame] = [:],
                depthFromRoot: Int = 0) {
        self.id = id
        self.objects = objects
        self.parent = parent
        self.indexInParent = indexInParent
        self.children = children
        self.depthFromRoot = depthFromRoot
    }

    public var hasLocalContent: Bool {
        !objects.isEmpty
    }

    public func child(at index: LabyrinthGridIndex) -> LabyrinthFrame {
        let key = index.clamped()
        if let existing = children[key] {
            return existing
        }

        let created = LabyrinthFrame(
            parent: self,
            indexInParent: key,
            depthFromRoot: depthFromRoot + 1
        )
        children[key] = created
        return created
    }

    public func childIfExists(at index: LabyrinthGridIndex) -> LabyrinthFrame? {
        children[index.clamped()]
    }

    @discardableResult
    public func ensureSuperRoot(id preferredID: UUID? = nil) -> LabyrinthFrame {
        if let parent {
            return parent
        }

        let newParent = LabyrinthFrame(id: preferredID ?? UUID(), depthFromRoot: depthFromRoot - 1)
        let center = LabyrinthGridIndex.center
        parent = newParent
        indexInParent = center
        newParent.children[center] = self
        return newParent
    }

    public func neighbor(_ direction: LabyrinthGridDirection,
                         retainNewRoot: (LabyrinthFrame) -> Void) -> LabyrinthFrame {
        guard let parent, let indexInParent else {
            let superRoot = ensureSuperRoot()
            retainNewRoot(superRoot)
            return neighbor(direction, retainNewRoot: retainNewRoot)
        }

        let delta = direction.delta
        let next = LabyrinthGridIndex(col: indexInParent.col + delta.dx,
                                      row: indexInParent.row + delta.dy)
        if next.isValid {
            return parent.child(at: next)
        }

        let uncle = parent.neighbor(direction, retainNewRoot: retainNewRoot)
        return uncle.child(at: next.wrapped())
    }

    public func neighborIfExists(_ direction: LabyrinthGridDirection) -> LabyrinthFrame? {
        guard let parent, let indexInParent else {
            return nil
        }

        let delta = direction.delta
        let next = LabyrinthGridIndex(col: indexInParent.col + delta.dx,
                                      row: indexInParent.row + delta.dy)
        if next.isValid {
            return parent.childIfExists(at: next)
        }

        guard let uncle = parent.neighborIfExists(direction) else {
            return nil
        }
        return uncle.childIfExists(at: next.wrapped())
    }

    @discardableResult
    public func pruneEmptyDescendants(preserving protected: Set<ObjectIdentifier> = []) -> Bool {
        for key in Array(children.keys) {
            guard let child = children[key] else { continue }
            let keepChild = child.pruneEmptyDescendants(preserving: protected)
            if !keepChild {
                children.removeValue(forKey: key)
            }
        }

        return hasLocalContent || !children.isEmpty || protected.contains(ObjectIdentifier(self))
    }
}

public struct LabyrinthChildFrameSnapshot: Codable, Equatable, Sendable {
    public var index: LabyrinthGridIndex
    public var frame: LabyrinthFrameSnapshot

    public init(index: LabyrinthGridIndex, frame: LabyrinthFrameSnapshot) {
        self.index = index
        self.frame = frame
    }
}

public struct LabyrinthFrameSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var depthFromRoot: Int
    public var indexInParent: LabyrinthGridIndex?
    public var objects: [LabyrinthCanvasObject]
    public var children: [LabyrinthChildFrameSnapshot]

    public init(id: UUID,
                depthFromRoot: Int,
                indexInParent: LabyrinthGridIndex?,
                objects: [LabyrinthCanvasObject],
                children: [LabyrinthChildFrameSnapshot]) {
        self.id = id
        self.depthFromRoot = depthFromRoot
        self.indexInParent = indexInParent
        self.objects = objects
        self.children = children
    }
}

extension LabyrinthFrame {
    public func snapshot() -> LabyrinthFrameSnapshot {
        let childSnapshots = children.keys.sorted { lhs, rhs in
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.col < rhs.col
        }.compactMap { index -> LabyrinthChildFrameSnapshot? in
            guard let child = children[index] else { return nil }
            return LabyrinthChildFrameSnapshot(index: index, frame: child.snapshot())
        }

        return LabyrinthFrameSnapshot(
            id: id,
            depthFromRoot: depthFromRoot,
            indexInParent: indexInParent,
            objects: objects,
            children: childSnapshots
        )
    }

    public static func fromSnapshot(_ snapshot: LabyrinthFrameSnapshot,
                                    parent: LabyrinthFrame? = nil) -> LabyrinthFrame {
        let frame = LabyrinthFrame(
            id: snapshot.id,
            objects: snapshot.objects,
            parent: parent,
            indexInParent: snapshot.indexInParent,
            depthFromRoot: snapshot.depthFromRoot
        )

        for child in snapshot.children {
            let childFrame = LabyrinthFrame.fromSnapshot(child.frame, parent: frame)
            childFrame.indexInParent = child.index
            frame.children[child.index] = childFrame
        }

        return frame
    }
}
