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
            .has(ShipControlComponent.self)
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
                // Human-controlled walking logic
                // Ensure ShipControlComponent exists (provides yaw from hand-tracking system)
                guard let shipControl = entity.components[ShipControlComponent.self] else { continue }
                let yawValue = shipControl.parameters.yaw

                // Update flightState: set yaw from shipControl and keep pitch/roll fixed (identity)
                flightState.yaw = simd_quatf(angle: yawValue, axis: SIMD3<Float>(0, 1, 0))
                flightState.pitchRoll = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))

                // Apply rotation to entity
                entity.transform.rotation = (flightState.yaw * flightState.pitchRoll).normalized
                entity.components[ShipFlightStateComponent.self] = flightState

                // Movement: use ThrottleComponent.throttle to control walking speed (transform-based)
                guard let throttleComp = entity.components[ThrottleComponent.self] else { continue }
                let throttleValue = throttleComp.throttle
                let baseWalkingSpeed: Float = 2.0 // meters per second (tweakable)
                let forward = entity.transform.matrix.forward
                let displacement = forward * throttleValue * baseWalkingSpeed * deltaTime
                var newPosition = entity.transform.translation + displacement
                entity.transform.translation = newPosition
            }

            // Removed physics-based random movement and assistive forces:
            // The following code block and related calls have been removed as per instructions.
            // This includes:
            // guard let physicsEntity = entity as? HasPhysics else { return }
            // if Self.currentMode == .randomOnly || Self.currentMode == .both {
            //     if entity.components.has(RandomFlightDirectionComponent.self) {
            //         applyPetLikeMovement(to: physicsEntity, entity: entity, deltaTime: deltaTime)
            //     } else if entity.components.has(PrimaryThrustComponent.self) {
            //         applyRandomThrust(to: physicsEntity, deltaTime: deltaTime)
            //     }
            // }
            // guard let motion = physicsEntity.physicsMotion else { return }
            // assistive thrust calculations and physicsEntity.addForce calls

        }
    }

    // Removed applyPetLikeMovement and applyRandomThrust methods as per instructions.

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
