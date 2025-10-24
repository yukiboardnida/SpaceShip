// このファイルは宇宙船の飛行制御に関するコンポーネントとシステムを定義します。
// ShipFlightComponentは、宇宙船エンティティに飛行機能を追加するためのコンポーネントです。
// ShipFlightSystemは、スロットル、ピッチ、ロールの入力に基づいて宇宙船の加速度と回転を処理するシステムです。
// 毎フレーム、スロットルとピッチ/ロールの値を取得し、それに応じて宇宙船のヨー、ピッチ、ロールを更新します。
// また、物理エンジンを使用して宇宙船に推力を加え、垂直方向と水平方向の動きを補助します。
// ShipFlightStateComponentは、宇宙船の現在のヨーとピッチ/ロールの状態を保持します。
// PrimaryThrustComponentは、主推力が有効かどうかを示すコンポーネントです。

/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Component and System for accelerating and rotating the spaceship.
*/

import RealityKit

/// 宇宙船の飛行機能を有効化するためのコンポーネント。
///
/// このコンポーネントをエンティティに追加すると、`ShipFlightSystem`による飛行制御の対象となります。
struct ShipFlightComponent: Component {
    init() {
        // このコンポーネントが初期化される際に、関連するシステムをRealityKitに登録します。
        ShipFlightSystem.registerSystem()
    }
}

/// ペットのように行ったり来たりするランダム飛行の方向を保持するコンポーネント。
struct RandomFlightDirectionComponent: Component {
    var direction: SIMD3<Float>

    init(direction: SIMD3<Float>? = nil) {
        if let dir = direction {
            self.direction = normalize(dir)
        } else {
            // 初期方向はランダム
            self.direction = normalize(SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            ))
        }
    }
}

/// 宇宙船の飛行物理を処理するシステム。
///
/// スロットル、ピッチ、ロールの入力に基づいて、宇宙船の動きと回転を更新します。
final class ShipFlightSystem: System {

    enum FlightMode {
        case randomOnly
        case humanOnly
        case both
    }

    static var currentMode: FlightMode = .randomOnly

    /// このシステムが処理するエンティティを特定するためのクエリ。
    /// 飛行、スロットル、ピッチ/ロールのコンポーネントをすべて持つエンティティが対象です。
    static let query = EntityQuery(
        where: (
            .has(ShipFlightComponent.self) &&
            .has(ThrottleComponent.self) &&
            .has(PitchRollComponent.self)
        )
    )

    /// ランダム飛行方向を持つエンティティを特定するためのクエリ。
    static let randomDirectionQuery = EntityQuery(
        where: .has(RandomFlightDirectionComponent.self)
    )

    /// システムの初期化メソッド。シーンのロード時にRealityKitによって呼び出されます。
    init(scene: Scene) {}

    /// 毎フレーム呼び出される更新メソッド。
    /// - Parameter context: 現在のシーンの更新コンテキスト。時間経過（deltaTime）などの情報を含みます。
    func update(context: SceneUpdateContext) {
        // クエリに一致するすべてのエンティティ（宇宙船）に対してループ処理を行います。
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {

            // 飛行状態を保持するコンポーネント（ShipFlightStateComponent）が存在しない場合は、新しく作成して追加します。
            if entity.components[ShipFlightStateComponent.self] == nil {
                entity.components.set(ShipFlightStateComponent())
            }

            // 飛行状態コンポーネントを取得します。これは宇宙船の現在の回転状態を保持します。
            var flightState = entity.components[ShipFlightStateComponent.self]!

            let deltaTime = Float(context.deltaTime)

            if Self.currentMode == .humanOnly || Self.currentMode == .both {
                // Human control flight logic
                let pitchRoll = entity.components[PitchRollComponent.self]!
                let pitch = pitchRoll.pitch
                let roll = pitchRoll.roll

                // 回転の感度と、宇宙船の傾きの最大角度を定義します。
                let turnSpeed: Float = 1
                let maxPitchRoll: Float = 0.7

                // ロール入力に基づいて、ヨー回転（水平方向の向き）を計算し、更新します。
                let yawDelta = simd_quatf(angle: roll * deltaTime * turnSpeed, axis: .upward)
                flightState.yaw = (flightState.yaw * yawDelta).normalized

                // ピッチとロールの入力に基づいて、宇宙船の目標となる傾き（クォータニオン）を計算します。
                let newRoll = simd_quatf(angle: -roll * maxPitchRoll, axis: .back)
                let newPitch = simd_quatf(angle: pitch * maxPitchRoll, axis: .left)
                // 現在の傾きから目標の傾きへと滑らかに補間（slerp）し、自然な動きを実現します。
                flightState.pitchRoll = simd_slerp(flightState.pitchRoll, newRoll * newPitch, deltaTime * 2).normalized

                // 計算されたヨー回転と傾きを合成して、エンティティの最終的な回転を決定します。
                entity.transform.rotation = (flightState.yaw * flightState.pitchRoll).normalized
                // 更新された飛行状態をコンポーネントに書き戻します。
                entity.components[ShipFlightStateComponent.self] = flightState
            }

            // エンティティが物理的な挙動を持つ（HasPhysics）ことを確認します。
            guard let physicsEntity = entity as? HasPhysics else { return }

            if Self.currentMode == .randomOnly || Self.currentMode == .both {
                if entity.components.has(RandomFlightDirectionComponent.self) {
                    applyPetLikeMovement(to: physicsEntity, entity: entity, deltaTime: deltaTime)
                } else if entity.components.has(PrimaryThrustComponent.self) {
                    applyRandomThrust(to: physicsEntity, deltaTime: deltaTime)
                }
            }

            // 物理モーションコンポーネントを取得します。これには線形速度などの情報が含まれます。
            guard let motion = physicsEntity.physicsMotion else { return }

            // --- 補助推力による飛行安定化 ---
            // このセクションは、宇宙船が意図しない方向に滑る（ドリフトする）のを防ぎ、
            // より直感的な操縦感を提供するためのものです。

            // 宇宙船の上方向ベクトルに対する、現在の速度の垂直成分を計算します。
            let shipUp = entity.transform.matrix.upward
            let vertVelocity = dot(motion.linearVelocity, shipUp)

            // 宇宙船の右方向ベクトルに対する、現在の速度の水平成分を計算します。
            let shipRight = entity.transform.matrix.right
            let rightVelocity = dot(motion.linearVelocity, shipRight)

            // 垂直および水平方向の速度を打ち消す方向に補助的な力を加えます。
            // これにより、宇宙船は進行方向に対してまっすぐに進みやすくなります。
            let verticalAssistStrength: Float = 80
            let assistiveThrust = -vertVelocity * shipUp * deltaTime * verticalAssistStrength +
                                  -rightVelocity * shipRight * deltaTime * verticalAssistStrength
            physicsEntity.addForce(assistiveThrust, relativeTo: nil)
        }
    }

    private func applyPetLikeMovement(to physicsEntity: HasPhysics, entity: Entity, deltaTime: Float) {
        guard var randomDirComp = entity.components[RandomFlightDirectionComponent.self] else {
            return
        }

        let position = physicsEntity.position(relativeTo: nil)
        let origin = SIMD3<Float>(0, 0, 0)
        let _: Float = 10.0

        // ランダムに方向を少しずつ変化させる（より激しく）
        let randomChange = SIMD3<Float>(
            Float.random(in: -1.5...1.5),
            Float.random(in: -1.5...1.5),
            Float.random(in: -1.5...1.5)
        )
        randomDirComp.direction += randomChange * deltaTime
        randomDirComp.direction = normalize(randomDirComp.direction)

        // 原点方向へのやわらい補正
        let toOrigin = normalize(origin - position)
        let correctionStrength: Float = 0.5
        randomDirComp.direction = normalize(mix(randomDirComp.direction, toOrigin, t: correctionStrength * deltaTime))

        // 方向を更新
        entity.components.set(randomDirComp)

        // 推力を加える
        let strength: Float = 200
        let force = randomDirComp.direction * strength * deltaTime
        physicsEntity.addForce(force, relativeTo: nil)

        // ランダム回転（滑らかに slerp 補間）
        let currentRotation = physicsEntity.transform.rotation
        let randomAxis = normalize(SIMD3<Float>(
            Float.random(in: -1...1),
            Float.random(in: -1...1),
            Float.random(in: -1...1)
        ))
        let randomAngle = Float.random(in: -Float.pi/8...Float.pi/8) * deltaTime
        let randomRotation = simd_quatf(angle: randomAngle, axis: randomAxis)

        // Pitch と Roll のランダム角度を拡大してより激しく傾くように
        let pitchAngle = Float.random(in: -Float.pi...Float.pi) * deltaTime
        let rollAngle = Float.random(in: -Float.pi...Float.pi) * deltaTime
        let pitchRotation = simd_quatf(angle: pitchAngle, axis: .left)
        let rollRotation = simd_quatf(angle: rollAngle, axis: .back)
        let pitchRollRotation = (rollRotation * pitchRotation).normalized

        // 現在の回転に Pitch/Roll を加算
        let targetRotation = (currentRotation * pitchRollRotation * randomRotation).normalized

        // slerp で滑らかに補間
        let newRotation = simd_slerp(currentRotation, targetRotation, deltaTime).normalized
        physicsEntity.transform.rotation = newRotation
    }

    private func applyRandomThrust(to physicsEntity: HasPhysics, deltaTime: Float) {
        let position = physicsEntity.position(relativeTo: nil)
        let origin = SIMD3<Float>(0, 0, 0) // 自分の位置など、基準点に置き換え可
        let distance = length(position - origin)
        let maxDistance: Float = 1000.0

        // ランダム方向を生成
        var direction = normalize(SIMD3<Float>(
            Float.random(in: -1...1),
            Float.random(in: -1...1),
            Float.random(in: -1...1)
        ))

        // 遠ざかりすぎたら、中心に戻す方向へ
        if distance > maxDistance {
            direction = normalize(origin - position)
        }

        // 推力を加える
        let strength: Float = 100
        let force = direction * strength * deltaTime
        physicsEntity.addForce(force, relativeTo: nil)
    }
}

/// 宇宙船の現在の飛行状態（回転）を保持するためのコンポーネント。
struct ShipFlightStateComponent: Component {
    /// ヨー回転（水平方向の向き）を保持します。
    var yaw = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    /// ピッチとロール（傾き）を保持します。
    var pitchRoll = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    init() {
        // このコンポーネントをRealityKitに登録します。
        ShipFlightStateComponent.registerComponent()
    }
}

/// 物理的な衝突グループを定義するための拡張。
extension CollisionGroup {
    /// 地球の重力（のシミュレーション）用の衝突グループ。
    static let actualEarthGravity = CollisionGroup(rawValue: 100 << 0)
}

/// 主推力が有効であることを示すためのマーカーコンポーネント。
///
/// このコンポーネントを持つエンティティは、`ShipFlightSystem`内で前方への推力を受けます。
struct PrimaryThrustComponent: Component {}
