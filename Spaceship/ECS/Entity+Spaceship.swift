/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Spaceship related Entity extensions.
*/

import RealityKit
import RealityKitContent

extension Entity {

    // 宇宙船エンティティを作成する静的メソッド
    static func makeSpaceship() async throws -> ModelEntity {

        // 宇宙船は物理的な力と衝突を使用します。`ModelEntity`として宣言することで、
        // `HasPhysics`プロトコルによって提供される機能を継承します。
        let spaceship = ModelEntity()
        spaceship.name = "Spaceship"

        // "ShipAssembly"という名前のエンティティを非同期で読み込みます。これは宇宙船の3Dモデルです。
        let shipModel = try await Entity(named: "ShipAssembly", in: realityKitContentBundle)
        shipModel.name = "ShipModel"
        spaceship.addChild(shipModel)

        let animations = shipModel.availableAnimations
        if !animations.isEmpty {
            shipModel.playAnimation(animations[0].repeat())
        } 

        // 物理ボディコンポーネントを動的モードで作成します。
        var physicsBody = PhysicsBodyComponent(mode: .dynamic)
        // 重力の影響を受けないように設定します。
        physicsBody.isAffectedByGravity = false
        // 直線運動の減衰を設定します。
        physicsBody.linearDamping = 0.2
        // 質量を設定します。
        physicsBody.massProperties.mass = 0.4
        spaceship.components.set(physicsBody)

        // 胴体の衝突形状をカプセルで生成します。
        let bodyCollisionShape = ShapeResource
            .generateCapsule(height: 0.1, radius: 0.015)
            .offsetBy(rotation: .init(angle: .pi / 2, axis: [1, 0, 0]))

        // 翼の衝突形状をカプセルで生成します。
        let wingsCollisionShape = ShapeResource
            .generateCapsule(height: 0.11, radius: 0.015)
            .offsetBy(rotation: .init(angle: .pi / 2, axis: [1, 0, 0]))
            .offsetBy(rotation: .init(angle: .pi / 2, axis: [0, 1, 0]))
            .offsetBy(translation: [0, 0, 0.02])

        // 衝突コンポーネントを設定します。
        spaceship.components.set(
            CollisionComponent(
                shapes: [
                    bodyCollisionShape,
                    wingsCollisionShape
                ],
                // 衝突フィルタを設定します。
                filter: .init(group: .actualEarthGravity, mask: .all)
            )
        )

        // 宇宙船にヘッドライトを追加します。
        addHeadlight(to: spaceship)

        // "Exploded"という名前のエンティティを見つけて無効にします。
        shipModel.findEntity(named: "Exploded")?.isEnabled = false

        // 左右のエンジンにオーディオソースを設定します。
        for engineName in ["LeftEngine", "RightEngine"] {
            let engine = shipModel.findEntity(named: engineName)!
            try await configureEngineAudioSource(on: engine)
        }

        // スロットル、ピッチロール、オーディオ、ビジュアルのコンポーネントを設定します。
        spaceship.components.set(ThrottleComponent())
        spaceship.components.set(PitchRollComponent())
        spaceship.components.set(ShipAudioComponent())
        spaceship.components.set(ShipVisualsComponent())

        return spaceship
    }
    
    // 宇宙船にヘッドライトを追加する静的メソッド
    static func addHeadlight(to spaceship: Entity) {
        if let headLightEntity = spaceship.findEntity(named: "HeadLight") {
            // スポットライトコンポーネントを作成します。
            var spotLight = SpotLightComponent(
                color: .init(
                    red: 255.0 / 255.0,
                    green: 233.0 / 255.0,
                    blue: 138.0 / 255.5,
                    alpha: 1.0
                )
            )
            // 光の強度を設定します。
            spotLight.intensity = 7000
            // 減衰半径を設定します。
            spotLight.attenuationRadius = 20
            // 内側の角度を設定します。
            spotLight.innerAngleInDegrees = 45
            // 外側の角度を設定します。
            spotLight.outerAngleInDegrees = 60
            
            // スポットライトの影を設定します。
            var spotLightShadow = SpotLightComponent.Shadow()
            spotLightShadow.zFar = .fixed(20)
            headLightEntity.components.set([spotLight, spotLightShadow])
        }
    }

    // エンジンのオーディオソースを設定する静的メソッド
    static func configureEngineAudioSource(on spaceship: Entity) async throws {
        try await configureEngineTurbineAudioSource(on: spaceship)
        try await configureEngineExhaustAudioSource(on: spaceship)
        try await configureVaporTrailAudioSource(on: spaceship)
    }

    // エンジンタービンのオーディオソースを設定する静的メソッド
    static func configureEngineTurbineAudioSource(on spaceship: Entity) async throws {
        let audioSource = Entity()
        audioSource.name = "AudioSource-EngineTurbine"
        audioSource.orientation = .init(angle: .pi, axis: [0, 1, 0])
        audioSource.components.set(SpatialAudioComponent(directivity: .beam(focus: 0.25)))
        spaceship.addChild(audioSource)
    }

    // エンジン排気のオーディオソースを設定する静的メソッド
    static func configureEngineExhaustAudioSource(on spaceship: Entity) async throws {
        // このオーディオソースは、スロットルに応じて大きくなる青い輝く円錐で視覚的に表現される
        // ジェット排気のオーディオを再生します。したがって、このオーディオソースの音量は
        // スロットルによって変調されます。
        let audioSource = Entity()
        audioSource.name = "AudioSource-EngineExhaust"
        audioSource.orientation = .init(angle: .pi, axis: [0, 1, 0])
        audioSource.components.set(SpatialAudioComponent(directivity: .beam(focus: 0.25)))
        spaceship.addChild(audioSource)
    }

    // 蒸気跡のオーディオソースを設定する静的メソッド
    static func configureVaporTrailAudioSource(on spaceship: Entity) async throws {
        // このオーディオソースは、煙のようなパーティクルエフェクトで視覚的に表現される
        // エンジンの凝縮のオーディオを再生します。このオーディオソースの音量は、
        // 常にシューという音を立てているため、船のスロットルによって変調されません。
        let audioSource = Entity()
        audioSource.name = "AudioSource-EngineParticles"
        audioSource.orientation = .init(angle: .pi, axis: [0, 1, 0])
        audioSource.components.set(SpatialAudioComponent(directivity: .beam(focus: 0.25)))
        spaceship.addChild(audioSource)
    }

    // 宇宙船を爆発させるメソッド
    func explode(parentingDebrisTo newParent: Entity) {

        guard let exploded = findEntity(named: "Exploded") else { return }

        // このエンティティの線形速度。
        let linearVelocity = components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero

        for piece in exploded.children {

            piece.setParent(newParent, preservingWorldTransform: true)

            var physicsBody = PhysicsBodyComponent()
            physicsBody.isAffectedByGravity = false
            physicsBody.massProperties.mass = 0.1
            physicsBody.linearDamping = 0
            piece.components.set(physicsBody)

            let randomVelocity: SIMD3<Float> = [
                .random(in: -1...1),
                .random(in: -1...1),
                .random(in: -1...1)
            ]

            let modifiedVelocity = randomVelocity * linearVelocity
            let physicsMotion = PhysicsMotionComponent(linearVelocity: modifiedVelocity)
            piece.components.set(physicsMotion)

            var collision = CollisionComponent(
                shapes: [.generateBox(size: .init(repeating: 0.01))]
            )
            collision.filter = .init(group: .actualEarthGravity, mask: .all)

            piece.components.set(AudioMaterialComponent(material: .plastic))

            piece.components.set(collision)
        }

        removeFromParent()
    }

    // 不透明度をフェードさせるメソッド
    func fadeOpacity(from start: Float? = nil, to end: Float, duration: Double) {
        let start = start ?? components[OpacityComponent.self]?.opacity ?? 0
        let fadeInAnimationDefinition = FromToByAnimation(
            from: Float(start),
            to: Float(end),
            duration: duration,
            timing: .easeInOut,
            bindTarget: .opacity
        )
        let fadeInAnimation = try! AnimationResource.generate(with: fadeInAnimationDefinition)
        components.set(OpacityComponent(opacity: start))
        playAnimation(fadeInAnimation)
    }
}
