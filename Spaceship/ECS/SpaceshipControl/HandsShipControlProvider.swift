/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Component and System for hand tracking based spaceship control.
*/

#if os(visionOS)

import RealityKit

/// 手の特定の部位（指先、手のひらなど）を追跡するためのコンポーネント。
/// このコンポーネントを持つエンティティは、`HandsShipControlProviderSystem`によって手の位置情報が更新されます。
struct HandTrackingComponent: Component {
    /// 追跡する手の部位の列挙型。
    enum Location: String {
        case leftIndexFingerTip, leftThumbTip, leftPalm, rightPalm
    }

    /// このコンポーネントが追跡する手の部位。
    let location: HandTrackingComponent.Location
}

/// スロットルラベルの配置を計算するためのコンポーネント。
/// 左手の人差し指と親指の先端の位置に基づいて、スロットル表示の位置を決定します。
struct ThrottleLabelPlacementComponent: Component {
    init() {
        ThrottleLabelPlacementComponent.registerComponent()
    }

    /// 人差し指と親指の先端の変換行列から、スロットルラベルの変換行列を計算します。
    func computeTransformWith(indexTipTransform: float4x4,
                              thumbTipTransform: float4x4) -> float4x4 {
        let midPosition = (indexTipTransform.translation + thumbTipTransform.translation) * 0.5
        let offset = SIMD3<Float>(0, 0.1, 0)
        let position = midPosition + offset
        return float4x4(translation: position)
    }
}

/// ピッチ・ロールラベルの配置を計算するためのコンポーネント。
/// 右手のひらの位置に基づいて、ピッチ・ロール表示の位置を決定します。
struct PitchRollLabelPlacementComponent: Component {
    init() {
        PitchRollLabelPlacementComponent.registerComponent()
    }

    /// 右手のひらの変換行列から、ピッチ・ロールラベルの変換行列を計算します。
    func computeTransformWith(rightPalmTransform: float4x4) -> float4x4 {
        let offset = SIMD3<Float>(0, 0.1, 0)
        let position = rightPalmTransform.translation + offset
        return float4x4(translation: position)
    }
}

/// 手の追跡データに基づいて宇宙船（またはキャラクター）の制御パラメータを更新するシステム。
/// `SpatialTrackingSession`を使用して手の位置を取得し、スロットルや方向の計算を行います。
final class HandsShipControlProviderSystem: System {

    /// `ShipControlSystem`の前に実行されるように依存関係を設定します。
    static var dependencies: [SystemDependency] = [.before(ShipControlSystem.self)]
    
    /// `PitchRollLabelPlacementComponent`を持つエンティティをクエリするための定義。
    static let pitchRollLabelQuery = EntityQuery(where: .has(PitchRollLabelPlacementComponent.self))
    
    /// 空間トラッキングセッション。手の位置情報を取得するために使用します。
    let session = SpatialTrackingSession()

    /// システムの初期化。
    init(scene: Scene) {
        // `HandTrackingComponent`をRealityKitに登録します。
        HandTrackingComponent.registerComponent()

        // メインスレッドで空間トラッキングセッションを開始します。
        Task { @MainActor in
            let config = SpatialTrackingSession.Configuration(tracking: [.hand])
            
            _ = await session.run(config)
        }
    }

    /// 毎フレーム呼び出される更新メソッド。
    /// 手の追跡データを取得し、それに基づいて制御パラメータを更新します。
    func update(context: SceneUpdateContext) {
        // 追跡された手のアンカーの変換行列を保存するための辞書。
        var transforms: [HandTrackingComponent.Location: simd_float4x4] = [:]

        // `HandTrackingComponent`を持つすべてのエンティティ（手の部位）をループ処理します。
        for entity in context.entities(matching: EntityQuery(where: .has(HandTrackingComponent.self)), updatingSystemWhen: .rendering) {
            guard let anchorEntity = entity as? AnchorEntity,
                  anchorEntity.isAnchored else {
                continue
            }

            guard let handTrackingComponent = entity.components[HandTrackingComponent.self] else { continue }

            // 各手の部位のワールド座標における変換行列を保存します。
            transforms[handTrackingComponent.location] = entity.transformMatrix(relativeTo: nil)
        }

        // `ThrottleLabelPlacementComponent`を持つエンティティを更新します。
        if let indexTipTransform = transforms[.leftIndexFingerTip],
           let thumbTipTransform = transforms[.leftThumbTip] {

            for entity in context.entities(matching: EntityQuery(where: .has(ThrottleLabelPlacementComponent.self)), updatingSystemWhen: .rendering) {
                guard let component = entity.components[ThrottleLabelPlacementComponent.self] else { continue }
                let transform = component.computeTransformWith(indexTipTransform: indexTipTransform,
                                                               thumbTipTransform: thumbTipTransform)
                entity.interpolate(towards: transform, smoothingFactor: 0.1)
            }
        }

        // `PitchRollLabelPlacementComponent`を持つエンティティを更新します。
        if let rightPalmTransform = transforms[.rightPalm] {
            for entity in context.entities(matching: HandsShipControlProviderSystem.pitchRollLabelQuery, updatingSystemWhen: .rendering) {
                guard let component = entity.components[PitchRollLabelPlacementComponent.self] else { continue }
                let transform = component.computeTransformWith(rightPalmTransform: rightPalmTransform)
                entity.interpolate(towards: transform, smoothingFactor: 0.1)
            }
        }

        // `ShipControlComponent`を持つエンティティ（宇宙船またはキャラクター）の制御パラメータを更新します。
        for entity in context.entities(matching: EntityQuery(where: .has(ShipControlComponent.self)), updatingSystemWhen: .rendering) {
            updateShipControlParameters(for: entity, context: context, transforms: transforms)
        }
    }
    
    /// 宇宙船（またはキャラクター）の制御パラメータを手の追跡データに基づいて更新します。
    /// 左手のピンチでスロットルを、右手の位置で歩行方向を決定します。
    func updateShipControlParameters(for entity: Entity, context: SceneUpdateContext, transforms: [HandTrackingComponent.Location: simd_float4x4]) {
        let shipControlParameters = entity.components[ShipControlComponent.self]!.parameters
        let currentThrottle = shipControlParameters.throttle

        // 左手の人差し指と親指の先端が追跡されているか確認します。
        guard let indexTipTransform = transforms[.leftIndexFingerTip],
              let thumbTipTransform = transforms[.leftThumbTip] else {
            print("⚠️ Lost tracking of left hand. Disabling throttle.")
            // 追跡が失われた場合、スロットルをゼロに補間します。
            shipControlParameters.throttle = interpolateThrottle(current: currentThrottle,
                                                                 target: .zero,
                                                                 deltaTime: context.deltaTime)
            return
        }

        // 左手のピンチ操作から目標スロットル値を計算します。
        let targetThrottle = computeTargetThrottle(indexTipTransform: indexTipTransform,
                                                   thumbTipTransform: thumbTipTransform)

        // 現在のスロットル値から目標値へ滑らかに補間します。
        shipControlParameters.throttle = interpolateThrottle(current: currentThrottle,
                                                             target: targetThrottle,
                                                             deltaTime: context.deltaTime)

        // 右手のひらが追跡されているか確認します。
        guard let rightPalmTransform = transforms[.rightPalm] else { return }

        // キャラクターの現在のワールド座標での位置を取得します。
        let characterPosition = entity.position(relativeTo: nil)

        // 右手の位置とキャラクターの位置から、歩行方向を計算します。
        let walkingDirection = computeWalkingDirection(rightPalmTransform: rightPalmTransform, characterPosition: characterPosition)

        // TODO: ShipControlParametersに新しいプロパティ(direction)を追加して、そこに保存することを想定しています。
        // (ShipControlParametersの変更も後ほど必要になります)
        // shipControlParameters.direction = walkingDirection

        // 既存のpitchとrollは歩行操作では使用しないため、0に設定します。
        shipControlParameters.pitch = 0
        shipControlParameters.roll = 0

        // デバッグ用に計算された歩行方向をコンソールに出力します。
        print("Walking Direction: \(walkingDirection)")
    }

    /// 現在のスロットル値から目標スロットル値へ滑らかに補間します。
    func interpolateThrottle(current: Float, target: Float, deltaTime: TimeInterval) -> Float {
        let delta = target - current
        let deltaTimeScaled = Float(deltaTime) * 5
        let interpolatedThrottle = current + delta * deltaTimeScaled
        return interpolatedThrottle
    }

    /// 左手の人差し指と親指の先端の距離に基づいてスロットル値を計算します。
    func computeTargetThrottle(indexTipTransform: float4x4, thumbTipTransform: float4x4) -> Float {
        let indexTipPosition = indexTipTransform.translation
        let thumbTipPosition = thumbTipTransform.translation
        // 指先の間の距離（ピンチの度合い）を計算します。
        let pinchMagnitude = distance(indexTipPosition, thumbTipPosition)
        // `PinchToThrottle`ユーティリティを使用して、ピンチの度合いをスロットル値に変換します。
        return PinchToThrottle.computeThrottle(with: pinchMagnitude)
    }

    /// 右手のひらの位置とキャラクターの位置から、歩行方向ベクトルを計算します。
    /// この関数は、キャラクターが向かうべき水平方向を決定するために使用されます。
    /// - Parameters:
    ///   - rightPalmTransform: 右手のひらのワールド座標における変換行列。
    ///   - characterPosition: キャラクターのワールド座標における位置。
    /// - Returns: キャラクターが進むべき水平方向を示す正規化されたSIMD3<Float>ベクトル。
    func computeWalkingDirection(rightPalmTransform: float4x4, characterPosition: SIMD3<Float>) -> SIMD3<Float> {
        let rightPalmPosition = rightPalmTransform.translation

        // キャラクターの位置から右手の位置への方向ベクトルを計算します。
        var direction = rightPalmPosition - characterPosition

        // y軸（高さ）の要素を0にして、水平方向のベクトルにします。
        direction.y = 0

        // ベクトルを正規化して、方向だけを取り出します。
        if length(direction) > 0 {
            return normalize(direction)
        } else {
            // 右手がキャラクターの真上にある場合など、方向が計算できない場合はデフォルトの前方（-Z方向）を返します。
            return SIMD3<Float>(0, 0, -1)
        }
    }

    /// 左手のひらと右手のひらの位置に基づいて、宇宙船のピッチとロールを計算します。
    /// この関数は、元の宇宙船制御ロジックで使用されていました。
    func computePitchAndRoll(leftPalmTransform: float4x4, rightPalmTransform: float4x4) -> (Float, Float) {
        let leftPalmPosition = leftPalmTransform.translation
        let rightPalmPosition = rightPalmTransform.translation

        let leftToRight = rightPalmPosition - leftPalmPosition

        guard leftToRight.length() > 0 else {
            // Sometimes the positions are the same and you can't compute a direction.
            return (0, 0)
        }

        let right = normalize(rightPalmPosition - leftPalmPosition)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let backward = normalize(cross(right, worldUp))
        let upward = normalize(cross(backward, right))

        let midpoint = float4x4(columns: (
                SIMD4<Float>(right, 0),
                SIMD4<Float>(upward, 0),
                SIMD4<Float>(backward, 0),
                [0, 0, 0, 1]))

        // rightPalmTransform definition:
        // [1, 0, 0] is the direction from palm to wrist
        // [0, 1, 0] is the direction from palm to center of hand
        // [0, 0, 1] is the direction from palm to the opposite of thumb
        //
        // Define `handForward` as the direction from wrist to palm,
        // and `handThumb` as the direction from palm to thumb.
        let palmToWrist: SIMD4<Float> = [-1, 0, 0, 0]
        let palmToThumb: SIMD4<Float> = [0, 0, -1, 0]

        let handRelativeToMidpoint = midpoint.inverse * rightPalmTransform

        let handForward = normalize((handRelativeToMidpoint * palmToWrist).xyz)
        let handThumb = normalize((handRelativeToMidpoint * palmToThumb).xyz)

        // Project `handForward` direction to the YZ plane for controlling pitch.
        let projectToPitchPlane: SIMD3 = normalize(SIMD3(0, handForward.y, handForward.z))
        let angleFromZ: Float = atan2(projectToPitchPlane.y, projectToPitchPlane.z)

        // Convert angle from positive Z to angle from negative Z (both around negative X).
        let pitch: Float = -angleFromZ + .pi * sign(angleFromZ)

        // Project `handThumb` direction to the XY plane for controlling roll.
        let projectToRollPlane: SIMD3 = normalize(SIMD3(handThumb.x, handThumb.y, 0))
        let angleFromX: Float = atan2(projectToRollPlane.y, projectToRollPlane.x)

        // Convert angle from positive X to angle from negative X (both around positive Z).
        let roll: Float = angleFromX - .pi * sign(angleFromX)

        return (pitch, roll)
    }
}

extension Entity {
    /// エンティティの変換行列を目標値へ滑らかに補間します。
    func interpolate(towards: float4x4, smoothingFactor: Float) {
        let current = transformMatrix(relativeTo: nil)
        setTransformMatrix(current + (towards - current) * smoothingFactor, relativeTo: nil)
    }

    /// 手の追跡に必要なアンカーエンティティを作成し、コンテナにまとめます。
    static func makeHandTrackingEntities() -> Entity {
        let container = Entity()
        container.name = "HandTrackingEntitiesContainer"

        // 左手のひら、右手のひら、左人差し指の先端、左親指の先端のアンカーエンティティを作成し、
        // それぞれに`HandTrackingComponent`を設定します。
        let leftHand = AnchorEntity(.hand(.left, location: .palm))
        leftHand.components.set(HandTrackingComponent(location: .leftPalm))

        let rightHand = AnchorEntity(.hand(.right, location: .palm))
        rightHand.components.set(HandTrackingComponent(location: .rightPalm))

        let indexTip = AnchorEntity(.hand(.left, location: .indexFingerTip))
        indexTip.components.set(HandTrackingComponent(location: .leftIndexFingerTip))

        let thumbTip = AnchorEntity(.hand(.left, location: .thumbTip))
        thumbTip.components.set(HandTrackingComponent(location: .leftThumbTip))

        // 作成したアンカーエンティティをコンテナに追加します。
        container.addChild(leftHand)
        container.addChild(rightHand)
        container.addChild(indexTip)
        container.addChild(thumbTip)

        return container
    }
}

#endif