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

/// 宇宙船の飛行物理を処理するシステム。
///
/// スロットル、ピッチ、ロールの入力に基づいて、宇宙船の動きと回転を更新します。
final class ShipFlightSystem: System {

    /// このシステムが処理するエンティティを特定するためのクエリ。
    /// 飛行、スロットル、ピッチ/ロールのコンポーネントをすべて持つエンティティが対象です。
    static let query = EntityQuery(
        where: (
            .has(ShipFlightComponent.self) &&
            .has(ThrottleComponent.self) &&
            .has(PitchRollComponent.self)
        )
    )

    /// システムの初期化メソッド。シーンのロード時にRealityKitによって呼び出されます。
    init(scene: Scene) {}

    /// 毎フレーム呼び出される更新メソッド。
    /// - Parameter context: 現在のシーンの更新コンテキスト。時間経過（deltaTime）などの情報を含みます。
    func update(context: SceneUpdateContext) {
        // クエリに一致するすべてのエンティティ（宇宙船）に対してループ処理を行います。
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {

            // 関連コンポーネントから現在の入力値を取得します。
            let throttle = entity.components[ThrottleComponent.self]!.throttle
            let pitchRoll = entity.components[PitchRollComponent.self]!

            // 飛行状態を保持するコンポーネント（ShipFlightStateComponent）が存在しない場合は、新しく作成して追加します。
            if entity.components[ShipFlightStateComponent.self] == nil {
                entity.components.set(ShipFlightStateComponent())
            }

            // 飛行状態コンポーネントを取得します。これは宇宙船の現在の回転状態を保持します。
            var flightState = entity.components[ShipFlightStateComponent.self]!

            let pitch = pitchRoll.pitch
            let roll = pitchRoll.roll

            // 前回のフレームからの経過時間を取得します。
            let deltaTime = Float(context.deltaTime)
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

            // エンティティが物理的な挙動を持つ（HasPhysics）ことを確認します。
            guard let physicsEntity = entity as? HasPhysics else { return }

            // 主推力コンポーネントが存在する場合、スロットル入力に応じて前方に力を加えます。
            if entity.components.has(PrimaryThrustComponent.self) {
                let strength: Float = 40
                let primaryThrust = entity.transform.matrix.forward * throttle * strength * deltaTime
                physicsEntity.addForce(primaryThrust, relativeTo: nil)
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