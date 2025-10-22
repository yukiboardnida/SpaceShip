/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Class for managing ARKit scene reconstruction.
*/

#if os(visionOS)
import RealityKit
import ARKit

@MainActor
final class SceneReconstruction {

    // ARKitセッションを管理します。
    let session = ARKitSession()
    // シーン再構築プロバイダー。分類モードで初期化します。
    var provider = SceneReconstructionProvider(modes: [.classification])

    // すべてのメッシュエンティティの親となるエンティティ。
    let entity = Entity()
    // 検出されたメッシュを格納する辞書。キーはメッシュアンカーのIDです。
    var meshes: [UUID: Entity] = [:]

    // シーン再構築を開始します。
    func start() async throws {
        // デバイスがシーン再構築をサポートしているか確認します。
        guard SceneReconstructionProvider.isSupported else { return }
        // セッションを開始し、プロバイダーを実行します。
        try await session.run([provider])
        // メッシュの更新処理を開始します。
        prepareUpdates()
    }

    // シーン再構築を停止します。
    func stop() {
        session.stop()
        // プロバイダーを再初期化します。
        provider = SceneReconstructionProvider()
    }

    // メッシュの更新を監視し、処理します。
    private func prepareUpdates() {
        Task { @MainActor in
            // プロバイダーのアンカー更新を非同期に待ち受けます。
            for await update in provider.anchorUpdates {
                let meshAnchor = update.anchor
                // バックグラウンドでメッシュアンカーから静的なメッシュ形状を生成します。
                let shape = try await Task(priority: .background) {
                    try await ShapeResource.generateStaticMesh(from: meshAnchor)
                }.value

                // アンカーの更新イベントに応じて処理を分岐します。
                switch update.event {
                case .added:
                    // 新しいメッシュが追加された場合
                    addMeshAnchor(meshAnchor, shape: shape)
                case .updated:
                    // 既存のメッシュが更新された場合
                    updateMeshAnchor(meshAnchor, shape: shape)
                case .removed:
                    // メッシュが削除された場合
                    removeMeshAnchor(meshAnchor)
                }
            }
        }
    }

    // 新しいメッシュアンカーをシーンに追加します。
    private func addMeshAnchor(_ meshAnchor: MeshAnchor, shape: ShapeResource) {

        let entity = Entity()
        entity.name = "SceneReconstructionMesh-\(meshAnchor.id)"

        // メッシュエンティティを正しい位置に移動します。
        entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)

        // 衝突時に動かないように、静的な物理ボディコンポーネントを追加します。
        entity.components.set(PhysicsBodyComponent(mode: .static))

        // 仮想オブジェクトが衝突できるように、メッシュエンティティに衝突コンポーネントを追加します。
        configureCollisions(for: entity, with: shape)

        // 衝突イベント時に参照するため、メッシュエンティティにメッシュ分類コンポーネントを追加します。
        if let classifications = meshAnchor.geometry.classifications {
            configureClassification(for: entity, with: classifications)
        }

        // メッシュエンティティをアンカー識別子と共に保存し、エンティティ階層に追加します。
        self.meshes[meshAnchor.id] = entity
        self.entity.addChild(entity)
    }

    // 既存のメッシュアンカーを更新します。
    private func updateMeshAnchor(_ meshAnchor: MeshAnchor, shape: ShapeResource) {

        guard let entity = self.meshes.removeValue(forKey: meshAnchor.id) else {
            return
        }

        // メッシュエンティティを正しい位置に移動します。
        entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)

        // 仮想オブジェクトが衝突できるように、メッシュエンティティに衝突コンポーネントを追加します。
        configureCollisions(for: entity, with: shape)

        // 衝突イベント時に参照するため、メッシュエンティティにメッシュ分類コンポーネントを追加します。
        if let classifications = meshAnchor.geometry.classifications {
            configureClassification(for: entity, with: classifications)
        }

        // 更新されたメッシュエンティティを保存します。
        meshes[meshAnchor.id] = entity
    }

    // メッシュアンカーをシーンから削除します。
    private func removeMeshAnchor(_ meshAnchor: MeshAnchor) {
        meshes[meshAnchor.id]?.removeFromParent()
        meshes.removeValue(forKey: meshAnchor.id)
    }

    // エンティティに衝突コンポーネントを設定します。
    private func configureCollisions(for entity: Entity, with shape: ShapeResource) {
        entity.components.set(
            CollisionComponent(
                shapes: [shape],
                isStatic: true,
                filter: CollisionFilter(group: .sceneUnderstanding, mask: .all)
            )
        )
    }

    // エンティティに分類コンポーネントを設定します。
    private func configureClassification(for entity: Entity, with classifications: GeometrySource) {
        entity.components.set(
            AudioMaterialLookupComponent(audioMaterialPerFace: classifications.audioMaterialPerFace)
        )
    }
}

extension GeometrySource {
    // 各面に対応するオーディオマテリアルの配列を返します。
    var audioMaterialPerFace: [AudioMaterial] {
        (0..<count).map { index in
            let classification = buffer
                .contents()
                .advanced(by: offset + (stride * Int(index)))
                .assumingMemoryBound(to: MeshAnchor.MeshClassification.self)
                .pointee
            return AudioMaterial(classification: classification)
        }
    }
}

extension AudioMaterial {
    // メッシュの分類に基づいてオーディオマテリアルを初期化します。
    init(classification: MeshAnchor.MeshClassification) {
        switch classification {
        case .none, .wall, .ceiling, .table, .door, .stairs, .cabinet:
            self = .wood
        case .floor, .seat, .bed, .plant:
            self = .fabric
        case .window, .tv:
            self = .glass
        case .homeAppliance:
            self = .metal
        @unknown default:
            self = .none
        }
    }
}

#endif
