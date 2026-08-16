import Foundation
import CoreGraphics

/// Geometry shared by the overlay replay and live ghost practice: anchoring an
/// attempt pose onto a reference pose, and measuring how far each joint is off.
enum PoseFeedback {

    static func isValid(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.y >= 0
    }

    /// Mirrors (when needed), then anchors the attempt's hips onto the reference's
    /// hips and matches torso scale — so comparison is about shape, not where the
    /// dancer stood.
    static func align(attempt pose: [CGPoint], to referencePose: [CGPoint]?, mirrored: Bool) -> [CGPoint] {
        var pose = pose
        if mirrored {
            pose = pose.map { isValid($0) ? CGPoint(x: 1 - $0.x, y: $0.y) : $0 }
        }
        guard pose.count == 33, let refPose = referencePose, refPose.count == 33 else { return pose }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }

        guard let refHips = mid(refPose[23], refPose[24]),
              let refShoulders = mid(refPose[11], refPose[12]),
              let attHips = mid(pose[23], pose[24]),
              let attShoulders = mid(pose[11], pose[12]) else { return pose }

        let refTorso = distance(refShoulders, refHips)
        let attTorso = distance(attShoulders, attHips)
        guard attTorso > 0.001, refTorso > 0.001 else { return pose }
        let scale = refTorso / attTorso

        return pose.map { point in
            guard isValid(point) else { return point }
            return CGPoint(
                x: (point.x - attHips.x) * scale + refHips.x,
                y: (point.y - attHips.y) * scale + refHips.y
            )
        }
    }

    /// Per-joint error levels (0 = matching, 1 = badly off) for an attempt pose
    /// that has already been aligned onto the reference. Distances are normalized
    /// by the reference torso so body size and camera distance drop out.
    /// Joints the camera couldn't see return 0 — never judged.
    static func jointErrors(reference: [CGPoint], alignedAttempt: [CGPoint]) -> [Double]? {
        guard reference.count == 33, alignedAttempt.count == 33 else { return nil }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        guard let refHips = mid(reference[23], reference[24]),
              let refShoulders = mid(reference[11], reference[12]) else { return nil }
        let torsoDx = refShoulders.x - refHips.x
        let torsoDy = refShoulders.y - refHips.y
        let torso = (torsoDx * torsoDx + torsoDy * torsoDy).squareRoot()
        guard torso > 0.001 else { return nil }

        return (0..<33).map { index in
            let ref = reference[index]
            let att = alignedAttempt[index]
            guard isValid(ref), isValid(att) else { return 0 }
            let dx = att.x - ref.x, dy = att.y - ref.y
            let distance = Double((dx * dx + dy * dy).squareRoot() / torso)
            // Within 20% of a torso-length: matching. Past 70%: fully red.
            let level = (distance - 0.2) / 0.5
            return min(1, max(0, level))
        }
    }
}
