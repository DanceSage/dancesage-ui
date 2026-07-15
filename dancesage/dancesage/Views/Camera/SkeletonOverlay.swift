import SwiftUI

struct SkeletonOverlay: View {
    let keypoints: [[CGPoint]]
    var useVisionIndices: Bool = false  // kept for compatibility, not used in styling mode
    var videoAspect: CGFloat = 9.0 / 16.0
    
    private let personColors: [Color] = [.green, .red]
    
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
                    let color = personColors[personIndex % personColors.count]
                    
                    // Use correct point set based on landmark count
                    let activePoints = personKeypoints.count == 33 ? pointsToShow : pointsToShow17

                    // Draw joint circles
                    for index in activePoints {
                        guard index < personKeypoints.count else { continue }
                        let point = personKeypoints[index]
                        guard point.x >= 0 && point.y >= 0 else { continue }
                        
                        let scaled = scaledPoint(point, in: size)
                        
                        // Larger circles for key joints, smaller for hand/foot detail
                        let radius: CGFloat = [11, 12, 23, 24].contains(index) ? 10 :
                                              [13, 14, 25, 26].contains(index) ? 8 : 6
                        
                        context.fill(
                            Circle().path(in: CGRect(
                                x: scaled.x - radius,
                                y: scaled.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )),
                            with: .color(color)
                        )
                    }
                    
                    // Draw skeleton lines
                    // Draw skeleton lines with correct connection set
                    let activeConnections = personKeypoints.count == 33 ? connections : connections17
                    drawSkeleton(context: context, keypoints: personKeypoints, size: size, color: color, connections: activeConnections)
                }
            }
        }
    }
    
    private func drawSkeleton(context: GraphicsContext, keypoints: [CGPoint], size: CGSize, color: Color, connections: [(Int, Int)]) {
        for (startIdx, endIdx) in connections {
            guard startIdx < keypoints.count, endIdx < keypoints.count else { continue }
            
            let startKp = keypoints[startIdx]
            let endKp = keypoints[endIdx]
            
            guard startKp.x >= 0 && startKp.y >= 0,
                  endKp.x >= 0 && endKp.y >= 0 else { continue }
            
            let startPoint = scaledPoint(startKp, in: size)
            let endPoint = scaledPoint(endKp, in: size)
            
            // Thinner lines for hand and foot detail
            let isDetail = [17, 18, 19, 20, 21, 22, 29, 30, 31, 32].contains(startIdx) ||
                           [17, 18, 19, 20, 21, 22, 29, 30, 31, 32].contains(endIdx)
            let lineWidth: CGFloat = isDetail ? 2 : 3
            
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
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
