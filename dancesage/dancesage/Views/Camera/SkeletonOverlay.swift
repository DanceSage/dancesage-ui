import SwiftUI

struct SkeletonOverlay: View {
    let keypoints: [[CGPoint]]
    var useVisionIndices: Bool = false  // kept for compatibility, not used in styling mode
    var videoAspect: CGFloat = 9.0 / 16.0
    
    private struct SkeletonPalette {
        let primary: Color
        let secondary: Color
    }

    // Jewel-toned palettes echo the DanceSage logo and stay visible on video or white.
    private let personPalettes: [SkeletonPalette] = [
        SkeletonPalette(primary: Color(red: 0.20, green: 0.95, blue: 0.92),
                        secondary: Color(red: 0.94, green: 0.30, blue: 0.92)),
        SkeletonPalette(primary: Color(red: 1.00, green: 0.78, blue: 0.18),
                        secondary: Color(red: 1.00, green: 0.28, blue: 0.30))
    ]
    
    // Full 33 MediaPipe landmark indices:
    // 0: nose
    // 1: left eye inner, 2: left eye, 3: left eye outer
    // 4: right eye inner, 5: right eye, 6: right eye outer
    // 7: left ear, 8: right ear
    // 9: mouth left, 10: mouth right
    // 11: left shoulder, 12: right shoulder
    // 13: left elbow, 14: right elbow
    // 15: left wrist, 16: right wrist
    // 17: left pinky, 18: right pinky
    // 19: left index, 20: right index
    // 21: left thumb, 22: right thumb
    // 23: left hip, 24: right hip
    // 25: left knee, 26: right knee
    // 27: left ankle, 28: right ankle
    // 29: left heel, 30: right heel
    // 31: left foot index, 32: right foot index
    
    // Points to render for 33-point MediaPipe
    private let pointsToShow: Set<Int> = [
        0, 2, 5, 7, 8,
        11, 12, 13, 14, 15, 16,
        17, 18, 19, 20, 21, 22,
        23, 24, 25, 26, 27, 28,
        29, 30, 31, 32
    ]
    
    // Points to render for 17-point Vision
    private let pointsToShow17: Set<Int> = [
        0, 1, 2, 5, 6, 7, 8, 9, 10,
        11, 12, 13, 14, 15, 16
    ]
    
    // 17-point Vision connections
    private let connections17: [(Int, Int)] = [
        (0, 1), (0, 2),
        (5, 6), (5, 11), (6, 12), (11, 12),
        (5, 7), (7, 9), (6, 8), (8, 10),
        (11, 13), (13, 15), (12, 14), (14, 16)
    ]
    
    // Skeleton connections — covers full body including hands and feet
    private let connections: [(Int, Int)] = [
        // Face
        (0, 2), (0, 5),          // nose to eyes
        (2, 7), (5, 8),          // eyes to ears
        
        // Torso
        (11, 12),                // shoulders
        (11, 23), (12, 24),      // shoulder to hip
        (23, 24),                // hips
        
        // Left arm
        (11, 13),                // shoulder to elbow
        (13, 15),                // elbow to wrist
        (15, 17),                // wrist to pinky
        (15, 19),                // wrist to index
        (15, 21),                // wrist to thumb
        (17, 19),                // pinky to index (hand shape)
        
        // Right arm
        (12, 14),                // shoulder to elbow
        (14, 16),                // elbow to wrist
        (16, 18),                // wrist to pinky
        (16, 20),                // wrist to index
        (16, 22),                // wrist to thumb
        (18, 20),                // pinky to index (hand shape)
        
        // Left leg
        (23, 25),                // hip to knee
        (25, 27),                // knee to ankle
        (27, 29),                // ankle to heel
        (27, 31),                // ankle to foot index
        (29, 31),                // heel to foot index
        
        // Right leg
        (24, 26),                // hip to knee
        (26, 28),                // knee to ankle
        (28, 30),                // ankle to heel
        (28, 32),                // ankle to foot index
        (30, 32),                // heel to foot index
    ]
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for (personIndex, personKeypoints) in keypoints.enumerated() {
                    // Support both 17-point (Vision/partner) and 33-point (MediaPipe/styling)
                    guard personKeypoints.count == 17 || personKeypoints.count == 33 else { continue }
                    let palette = personPalettes[personIndex % personPalettes.count]
                    
                    // Use correct point set based on landmark count
                    let activePoints = personKeypoints.count == 33 ? pointsToShow : pointsToShow17

                    // Bones go down first so the luminous joints sit crisply on top.
                    let activeConnections = personKeypoints.count == 33 ? connections : connections17
                    drawSkeleton(
                        context: context,
                        keypoints: personKeypoints,
                        size: size,
                        palette: palette,
                        connections: activeConnections
                    )

                    // Draw glowing joint rings with a bright center point.
                    for index in activePoints {
                        guard index < personKeypoints.count else { continue }
                        let point = personKeypoints[index]
                        guard point.x >= 0 && point.y >= 0 else { continue }
                        
                        let scaled = scaledPoint(point, in: size)
                        
                        let scale = bodyScale(for: personKeypoints, in: size)
                        let radius = jointRadius(
                            for: index,
                            landmarkCount: personKeypoints.count,
                            scale: scale
                        )
                        let jointRect = CGRect(
                            x: scaled.x - radius,
                            y: scaled.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        let jointPath = Circle().path(in: jointRect)

                        context.drawLayer { layer in
                            layer.addFilter(.shadow(color: palette.secondary.opacity(0.82), radius: 7 * scale))
                            layer.fill(
                                jointPath,
                                with: .radialGradient(
                                    Gradient(colors: [
                                        .white,
                                        palette.primary,
                                        palette.secondary,
                                        Color.black.opacity(0.55)
                                    ]),
                                    center: CGPoint(x: scaled.x - radius * 0.30, y: scaled.y - radius * 0.30),
                                    startRadius: 0,
                                    endRadius: radius * 1.25
                                )
                            )
                        }
                        context.stroke(
                            jointPath,
                            with: .color(.white.opacity(0.72)),
                            style: StrokeStyle(lineWidth: max(0.8, 1.2 * scale))
                        )

                        let coreRadius = max(1.3, radius * 0.20)
                        context.fill(
                            Circle().path(in: CGRect(
                                x: scaled.x - radius * 0.38 - coreRadius,
                                y: scaled.y - radius * 0.38 - coreRadius,
                                width: coreRadius * 2,
                                height: coreRadius * 2
                            )),
                            with: .color(.white.opacity(0.92))
                        )
                    }
                }
            }
        }
    }
    
    private func drawSkeleton(
        context: GraphicsContext,
        keypoints: [CGPoint],
        size: CGSize,
        palette: SkeletonPalette,
        connections: [(Int, Int)]
    ) {
        let scale = bodyScale(for: keypoints, in: size)

        for (startIdx, endIdx) in connections {
            guard startIdx < keypoints.count, endIdx < keypoints.count else { continue }
            
            let startKp = keypoints[startIdx]
            let endKp = keypoints[endIdx]
            
            guard startKp.x >= 0 && startKp.y >= 0,
                  endKp.x >= 0 && endKp.y >= 0 else { continue }
            
            let startPoint = scaledPoint(startKp, in: size)
            let endPoint = scaledPoint(endKp, in: size)
            
            let radii = boneRadii(
                start: startIdx,
                end: endIdx,
                landmarkCount: keypoints.count,
                scale: scale
            )
            guard let bone = taperedCapsule(
                from: startPoint,
                to: endPoint,
                startRadius: radii.start,
                endRadius: radii.end
            ) else { continue }

            let dx = endPoint.x - startPoint.x
            let dy = endPoint.y - startPoint.y
            let length = hypot(dx, dy)
            let perpendicular = CGVector(dx: -dy / length, dy: dx / length)
            let midpoint = CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
            let widest = max(radii.start, radii.end)
            let shadeStart = CGPoint(
                x: midpoint.x - perpendicular.dx * widest,
                y: midpoint.y - perpendicular.dy * widest
            )
            let shadeEnd = CGPoint(
                x: midpoint.x + perpendicular.dx * widest,
                y: midpoint.y + perpendicular.dy * widest
            )

            context.drawLayer { layer in
                layer.addFilter(.shadow(color: palette.primary.opacity(0.72), radius: 6 * scale))
                layer.fill(
                    bone,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color.black.opacity(0.58), location: 0),
                            .init(color: palette.secondary.opacity(0.95), location: 0.18),
                            .init(color: palette.primary, location: 0.48),
                            .init(color: .white.opacity(0.92), location: 0.64),
                            .init(color: palette.primary, location: 0.76),
                            .init(color: Color.black.opacity(0.52), location: 1)
                        ]),
                        startPoint: shadeStart,
                        endPoint: shadeEnd
                    )
                )
            }
            context.stroke(bone, with: .color(.white.opacity(0.38)), lineWidth: max(0.7, scale))
        }
    }

    private func taperedCapsule(
        from start: CGPoint,
        to end: CGPoint,
        startRadius: CGFloat,
        endRadius: CGFloat
    ) -> Path? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return nil }

        let forward = CGVector(dx: dx / length, dy: dy / length)
        let perpendicular = CGVector(dx: -forward.dy, dy: forward.dx)
        let startUpper = CGPoint(x: start.x + perpendicular.dx * startRadius, y: start.y + perpendicular.dy * startRadius)
        let startLower = CGPoint(x: start.x - perpendicular.dx * startRadius, y: start.y - perpendicular.dy * startRadius)
        let endUpper = CGPoint(x: end.x + perpendicular.dx * endRadius, y: end.y + perpendicular.dy * endRadius)
        let endLower = CGPoint(x: end.x - perpendicular.dx * endRadius, y: end.y - perpendicular.dy * endRadius)

        var path = Path()
        path.move(to: startUpper)
        path.addLine(to: endUpper)
        path.addQuadCurve(
            to: endLower,
            control: CGPoint(x: end.x + forward.dx * endRadius, y: end.y + forward.dy * endRadius)
        )
        path.addLine(to: startLower)
        path.addQuadCurve(
            to: startUpper,
            control: CGPoint(x: start.x - forward.dx * startRadius, y: start.y - forward.dy * startRadius)
        )
        path.closeSubpath()
        return path
    }

    private func boneRadii(
        start: Int,
        end: Int,
        landmarkCount: Int,
        scale: CGFloat
    ) -> (start: CGFloat, end: CGFloat) {
        let pair = (start, end)

        if landmarkCount == 33 {
            switch pair {
            case (23, 25), (24, 26): return (9.5 * scale, 7.6 * scale)
            case (25, 27), (26, 28): return (7.6 * scale, 5.4 * scale)
            case (11, 13), (12, 14): return (7.2 * scale, 6.0 * scale)
            case (13, 15), (14, 16): return (6.0 * scale, 4.3 * scale)
            case (11, 23), (12, 24): return (6.2 * scale, 7.2 * scale)
            case (11, 12), (23, 24): return (5.5 * scale, 5.5 * scale)
            case (27, 29), (28, 30), (27, 31), (28, 32), (29, 31), (30, 32):
                return (3.4 * scale, 2.8 * scale)
            case (15, 17), (16, 18), (15, 19), (16, 20), (15, 21), (16, 22), (17, 19), (18, 20):
                return (2.8 * scale, 1.9 * scale)
            default: return (2.5 * scale, 2.0 * scale)
            }
        }

        switch pair {
        case (11, 13), (12, 14): return (9.5 * scale, 7.6 * scale)
        case (13, 15), (14, 16): return (7.6 * scale, 5.4 * scale)
        case (5, 7), (6, 8): return (7.2 * scale, 6.0 * scale)
        case (7, 9), (8, 10): return (6.0 * scale, 4.3 * scale)
        case (5, 11), (6, 12): return (6.2 * scale, 7.2 * scale)
        case (5, 6), (11, 12): return (5.5 * scale, 5.5 * scale)
        default: return (2.5 * scale, 2.0 * scale)
        }
    }

    private func jointRadius(for index: Int, landmarkCount: Int, scale: CGFloat) -> CGFloat {
        let largeJoints: Set<Int> = landmarkCount == 33 ? [11, 12, 23, 24] : [5, 6, 11, 12]
        let mediumJoints: Set<Int> = landmarkCount == 33 ? [13, 14, 25, 26] : [7, 8, 13, 14]
        let smallJoints: Set<Int> = landmarkCount == 33 ? [15, 16, 27, 28] : [9, 10, 15, 16]

        if largeJoints.contains(index) { return 8.2 * scale }
        if mediumJoints.contains(index) { return 6.6 * scale }
        if smallJoints.contains(index) { return 5.0 * scale }
        return 3.8 * scale
    }

    private func bodyScale(for keypoints: [CGPoint], in size: CGSize) -> CGFloat {
        let shoulders = keypoints.count == 33 ? (11, 12) : (5, 6)
        guard shoulders.0 < keypoints.count, shoulders.1 < keypoints.count else { return 1 }
        let left = keypoints[shoulders.0]
        let right = keypoints[shoulders.1]
        guard left.x >= 0, left.y >= 0, right.x >= 0, right.y >= 0 else { return 1 }
        let leftScaled = scaledPoint(left, in: size)
        let rightScaled = scaledPoint(right, in: size)
        let shoulderWidth = hypot(rightScaled.x - leftScaled.x, rightScaled.y - leftScaled.y)
        return min(max(shoulderWidth / 115, 0.62), 1.45)
    }

    private func scaledPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let viewAspect = size.width / max(size.height, 1)
        var normalized = point

        if videoAspect > viewAspect {
            let visibleWidth = viewAspect / videoAspect
            let crop = (1 - visibleWidth) / 2
            normalized.x = (point.x - crop) / visibleWidth
        } else if videoAspect < viewAspect {
            let visibleHeight = videoAspect / viewAspect
            let crop = (1 - visibleHeight) / 2
            normalized.y = (point.y - crop) / visibleHeight
        }

        return CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }
}
