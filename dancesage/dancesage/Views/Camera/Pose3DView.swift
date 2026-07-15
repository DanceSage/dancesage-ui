import SwiftUI
import RealityKit
import UIKit
import simd

struct Pose3DView: UIViewRepresentable {
    let poses: [[PosePoint3D]]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.055, green: 0.035, blue: 0.075, alpha: 1))
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(with: poses.first)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let anchor = AnchorEntity(world: .zero)
        private let mannequin = Entity()
        private let camera = PerspectiveCamera()
        private var jointEntities: [ModelEntity] = []
        private var boneEntities: [ModelEntity] = []
        private var yaw: Float = 0
        private var pitch: Float = 0.04
        private var distance: Float = 2.7

        private let connections: [(Int, Int)] = [
            (0, 2), (0, 5), (2, 7), (5, 8),
            (11, 12), (11, 23), (12, 24), (23, 24),
            (11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19),
            (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
            (23, 25), (25, 27), (27, 29), (27, 31), (29, 31),
            (24, 26), (26, 28), (28, 30), (28, 32), (30, 32)
        ]

        func install(in view: ARView) {
            anchor.addChild(mannequin)
            anchor.addChild(camera)
            view.scene.addAnchor(anchor)

            let keyLight = DirectionalLight()
            keyLight.light.intensity = 2600
            keyLight.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, -1, 0))
            anchor.addChild(keyLight)

            let fillLight = PointLight()
            fillLight.light.intensity = 1500
            fillLight.light.attenuationRadius = 5
            fillLight.position = SIMD3<Float>(-1.5, 1.5, 2)
            anchor.addChild(fillLight)

            buildMannequin()
            updateCamera()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }

        func update(with points: [PosePoint3D]?) {
            guard let points, points.count == 33 else {
                mannequin.isEnabled = false
                return
            }
            mannequin.isEnabled = true

            let positions = normalizedPositions(from: points)
            for index in jointEntities.indices {
                jointEntities[index].position = positions[index]
            }

            for (index, connection) in connections.enumerated() {
                positionBone(boneEntities[index], from: positions[connection.0], to: positions[connection.1])
            }
        }

        private func buildMannequin() {
            let jointMaterial = SimpleMaterial(
                color: UIColor(red: 1.0, green: 0.28, blue: 0.82, alpha: 1),
                roughness: 0.35,
                isMetallic: false
            )
            let boneMaterial = SimpleMaterial(
                color: UIColor(red: 0.18, green: 0.94, blue: 0.92, alpha: 1),
                roughness: 0.3,
                isMetallic: false
            )

            let jointMesh = MeshResource.generateSphere(radius: 0.018)
            jointEntities = (0..<33).map { _ in
                let joint = ModelEntity(mesh: jointMesh, materials: [jointMaterial])
                mannequin.addChild(joint)
                return joint
            }

            boneEntities = connections.map { _ in
                let bone = ModelEntity(
                    mesh: makeCylinderMesh(height: 1, radius: 0.009, segments: 12),
                    materials: [boneMaterial]
                )
                mannequin.addChild(bone)
                return bone
            }
        }

        private func normalizedPositions(from points: [PosePoint3D]) -> [SIMD3<Float>] {
            let hipCenter = SIMD3<Float>(
                (points[23].x + points[24].x) / 2,
                -(points[23].y + points[24].y) / 2,
                -(points[23].z + points[24].z) / 2
            )
            return points.map { point in
                SIMD3<Float>(point.x, -point.y, -point.z) - hipCenter
            }
        }

        private func positionBone(_ bone: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
            let vector = end - start
            let length = simd_length(vector)
            guard length > 0.001 else {
                bone.isEnabled = false
                return
            }
            bone.isEnabled = true
            bone.position = (start + end) / 2
            bone.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: vector / length)
            bone.scale = SIMD3<Float>(1, length, 1)
        }

        private func makeCylinderMesh(height: Float, radius: Float, segments: Int = 18) -> MeshResource {
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            let halfHeight = height / 2

            // Side wall vertices, duplicated at the seam for clean interpolation.
            for index in 0...segments {
                let angle = Float(index) / Float(segments) * 2 * .pi
                let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
                positions.append(SIMD3<Float>(radial.x * radius, -halfHeight, radial.z * radius))
                normals.append(radial)
                positions.append(SIMD3<Float>(radial.x * radius, halfHeight, radial.z * radius))
                normals.append(radial)
            }

            for index in 0..<segments {
                let lowerLeft = UInt32(index * 2)
                let upperLeft = lowerLeft + 1
                let lowerRight = lowerLeft + 2
                let upperRight = lowerLeft + 3
                indices.append(contentsOf: [lowerLeft, upperLeft, lowerRight, upperLeft, upperRight, lowerRight])
            }

            // Independent cap vertices keep the top and bottom lighting flat.
            let bottomCenter = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, -halfHeight, 0))
            normals.append(SIMD3<Float>(0, -1, 0))
            let bottomStart = UInt32(positions.count)
            for index in 0..<segments {
                let angle = Float(index) / Float(segments) * 2 * .pi
                positions.append(SIMD3<Float>(cos(angle) * radius, -halfHeight, sin(angle) * radius))
                normals.append(SIMD3<Float>(0, -1, 0))
            }

            let topCenter = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, halfHeight, 0))
            normals.append(SIMD3<Float>(0, 1, 0))
            let topStart = UInt32(positions.count)
            for index in 0..<segments {
                let angle = Float(index) / Float(segments) * 2 * .pi
                positions.append(SIMD3<Float>(cos(angle) * radius, halfHeight, sin(angle) * radius))
                normals.append(SIMD3<Float>(0, 1, 0))
            }

            for index in 0..<segments {
                let next = (index + 1) % segments
                indices.append(contentsOf: [
                    bottomCenter,
                    bottomStart + UInt32(next),
                    bottomStart + UInt32(index),
                    topCenter,
                    topStart + UInt32(index),
                    topStart + UInt32(next)
                ])
            }

            var descriptor = MeshDescriptor(name: "DanceSageCylinder")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return try! MeshResource.generate(from: [descriptor])
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            yaw -= Float(translation.x) * 0.008
            pitch = min(max(pitch + Float(translation.y) * 0.006, -0.65), 0.65)
            gesture.setTranslation(.zero, in: gesture.view)
            updateCamera()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            distance = min(max(distance / Float(gesture.scale), 1.4), 5.0)
            gesture.scale = 1
            updateCamera()
        }

        private func updateCamera() {
            let horizontal = cos(pitch) * distance
            let position = SIMD3<Float>(
                sin(yaw) * horizontal,
                0.25 + sin(pitch) * distance,
                cos(yaw) * horizontal
            )
            camera.look(at: SIMD3<Float>(0, 0.15, 0), from: position, relativeTo: nil)
        }
    }
}
