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
        private var headEntity: ModelEntity?
        private var neckEntity: ModelEntity?
        private var groundEntity: ModelEntity?
        private var yaw: Float = 0
        private var pitch: Float = 0.04
        private var distance: Float = 2.7

        private let connections: [(Int, Int)] = [
            (11, 12), (11, 23), (12, 24), (23, 24),
            (11, 13), (13, 15), (15, 19),
            (12, 14), (14, 16), (16, 20),
            (23, 25), (25, 27), (27, 29), (29, 31),
            (24, 26), (26, 28), (28, 30), (30, 32)
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

            updateHead(using: positions)
            let floorY = min(positions[29].y, positions[30].y, positions[31].y, positions[32].y) - 0.035
            groundEntity?.position.y = floorY
        }

        private func buildMannequin() {
            var jointMaterial = PhysicallyBasedMaterial()
            jointMaterial.baseColor = .init(tint: UIColor(red: 0.95, green: 0.30, blue: 0.92, alpha: 1))
            jointMaterial.emissiveColor = .init(color: UIColor(red: 0.16, green: 0.92, blue: 0.90, alpha: 1))
            jointMaterial.emissiveIntensity = 0.45
            jointMaterial.roughness = 0.24
            jointMaterial.metallic = 0.22

            let jointMesh = MeshResource.generateSphere(radius: 0.032)
            jointEntities = (0..<33).map { index in
                let joint = ModelEntity(mesh: jointMesh, materials: [jointMaterial])
                let scale: Float = [11, 12, 23, 24].contains(index) ? 1.3 :
                    [13, 14, 25, 26].contains(index) ? 1.12 : 0.82
                joint.scale = SIMD3<Float>(repeating: scale)
                mannequin.addChild(joint)
                return joint
            }

            boneEntities = connections.map { connection in
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: UIColor(red: 0.18, green: 0.92, blue: 0.90, alpha: 1))
                material.emissiveColor = .init(color: UIColor(red: 0.12, green: 0.55, blue: 0.62, alpha: 1))
                material.emissiveIntensity = 0.32
                material.roughness = 0.2
                material.metallic = 0.3

                let radius = radiusForBone(connection)
                let bone = ModelEntity(
                    mesh: makeCylinderMesh(height: 1, radius: radius),
                    materials: [material]
                )
                mannequin.addChild(bone)
                return bone
            }

            var headMaterial = PhysicallyBasedMaterial()
            headMaterial.baseColor = .init(tint: UIColor(red: 1.0, green: 0.66, blue: 0.18, alpha: 1))
            headMaterial.emissiveColor = .init(color: UIColor(red: 0.75, green: 0.18, blue: 0.48, alpha: 1))
            headMaterial.emissiveIntensity = 0.22
            headMaterial.roughness = 0.18
            headMaterial.metallic = 0.38
            let head = ModelEntity(mesh: .generateSphere(radius: 1), materials: [headMaterial])
            mannequin.addChild(head)
            headEntity = head

            let neck = ModelEntity(
                mesh: makeCylinderMesh(height: 1, radius: 0.038),
                materials: [jointMaterial]
            )
            mannequin.addChild(neck)
            neckEntity = neck

            let groundMaterial = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.10), roughness: 0.9, isMetallic: false)
            let ground = ModelEntity(mesh: .generatePlane(width: 3, depth: 3), materials: [groundMaterial])
            mannequin.addChild(ground)
            groundEntity = ground
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

        private func updateHead(using positions: [SIMD3<Float>]) {
            guard let headEntity, let neckEntity else { return }
            let earCenter = (positions[7] + positions[8]) / 2
            let faceCenter = (earCenter + positions[0]) / 2
            let shoulderWidth = simd_length(positions[12] - positions[11])
            let radius = min(max(shoulderWidth * 0.25, 0.085), 0.14)
            headEntity.position = faceCenter
            headEntity.scale = SIMD3<Float>(radius * 0.88, radius * 1.08, radius)
            let shoulderCenter = (positions[11] + positions[12]) / 2
            positionBone(neckEntity, from: shoulderCenter, to: faceCenter)
        }

        private func radiusForBone(_ connection: (Int, Int)) -> Float {
            switch connection {
            case (23, 25), (24, 26): return 0.052
            case (25, 27), (26, 28): return 0.042
            case (11, 13), (12, 14): return 0.040
            case (13, 15), (14, 16): return 0.032
            case (11, 23), (12, 24): return 0.045
            case (27, 29), (28, 30), (29, 31), (30, 32): return 0.027
            default: return 0.034
            }
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
