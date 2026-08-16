import Foundation
import CoreGraphics

/// Geometry shared by the overlay replay and live ghost practice: anchoring an
/// attempt pose onto a reference pose, and measuring how far each joint is off.
enum PoseFeedback {

    /// Keypoints are normalized to the portrait frame, where one x-unit spans
    /// far fewer physical centimeters than one y-unit. All geometry must happen
    /// in physically proportional space or every distance and angle is warped.
    static let portraitAspect: CGFloat = 9.0 / 16.0

    static func toPhysical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * portraitAspect, y: p.y)
    }

    static func fromPhysical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / portraitAspect, y: p.y)
    }

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

        // All alignment math happens in physical proportions.
        let phys = pose.map { isValid($0) ? toPhysical($0) : $0 }
        let physRef = refPose.map { isValid($0) ? toPhysical($0) : $0 }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }

        guard let refHips = mid(physRef[23], physRef[24]),
              let refShoulders = mid(physRef[11], physRef[12]),
              let attHips = mid(phys[23], phys[24]),
              let attShoulders = mid(phys[11], phys[12]) else { return pose }

        let refTorso = distance(refShoulders, refHips)
        let attTorso = distance(attShoulders, attHips)
        guard attTorso > 0.001, refTorso > 0.001 else { return pose }
        let scale = refTorso / attTorso

        return phys.map { point in
            guard isValid(point) else { return point }
            return fromPhysical(CGPoint(
                x: (point.x - attHips.x) * scale + refHips.x,
                y: (point.y - attHips.y) * scale + refHips.y
            ))
        }
    }

    /// Per-joint error levels (0 = matching, 1 = badly off) for an attempt pose
    /// that has already been aligned onto the reference. Distances are normalized
    /// by the reference torso so body size and camera distance drop out.
    /// Joints the camera couldn't see return 0 — never judged.
    static func jointErrors(reference: [CGPoint], alignedAttempt: [CGPoint]) -> [Double]? {
        guard reference.count == 33, alignedAttempt.count == 33 else { return nil }

        let physRef = reference.map { isValid($0) ? toPhysical($0) : $0 }
        let physAtt = alignedAttempt.map { isValid($0) ? toPhysical($0) : $0 }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        guard let refHips = mid(physRef[23], physRef[24]),
              let refShoulders = mid(physRef[11], physRef[12]) else { return nil }
        let torsoDx = refShoulders.x - refHips.x
        let torsoDy = refShoulders.y - refHips.y
        let torso = (torsoDx * torsoDx + torsoDy * torsoDy).squareRoot()
        guard torso > 0.001 else { return nil }

        return (0..<33).map { index in
            let ref = physRef[index]
            let att = physAtt[index]
            guard isValid(ref), isValid(att) else { return 0 }
            let dx = att.x - ref.x, dy = att.y - ref.y
            let distance = Double((dx * dx + dy * dy).squareRoot() / torso)
            // Within a quarter torso-length: matching. Past a full torso: fully red.
            let level = (distance - 0.25) / 0.75
            return min(1, max(0, level))
        }
    }

    /// Mirrors a pose's identity: flips x and swaps left/right landmark indices.
    static func mirrored(_ pose: [CGPoint]) -> [CGPoint] {
        guard pose.count == 33 else { return pose }
        var flipped = pose.map { isValid($0) ? CGPoint(x: 1 - $0.x, y: $0.y) : $0 }
        let pairs: [(Int, Int)] = [
            (1, 4), (2, 5), (3, 6), (7, 8), (9, 10),
            (11, 12), (13, 14), (15, 16), (17, 18), (19, 20), (21, 22),
            (23, 24), (25, 26), (27, 28), (29, 30), (31, 32),
        ]
        for (l, r) in pairs { flipped.swapAt(l, r) }
        return flipped
    }
}
