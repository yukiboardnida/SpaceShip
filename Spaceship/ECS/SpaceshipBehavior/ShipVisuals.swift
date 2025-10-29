/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Component and System for updating spaceship's appearance and partciles.
*/

import RealityKit

final class ShipVisualsSystem: System {

    static let query = EntityQuery(where: .has(ThrottleComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {

            guard let throttleComponent = entity.components[ThrottleComponent.self] else {
                print("ThrottleComponent not found for entity \(entity.name)")
                continue
            }
            let throttle = throttleComponent.throttle

            for engineName in ["LeftEngine", "RightEngine"] {
                if let engine = entity.findEntity(named: engineName) {
                    if let exhaust = engine.findEntity(named: "Exhaust") {
                        updateExhaust(exhaust, throttle: throttle)
                    } else {
                        print("Exhaust not found in engine \(engineName)")
                    }
                    if let particles = engine.findEntity(named: "ParticleEmitter") {
                        updateVaporTrail(particles, throttle: throttle)
                    } else {
                        print("ParticleEmitter not found in engine \(engineName)")
                    }
                    if let physicsMotion = entity.components[PhysicsMotionComponent.self] {
                        let forwardVelocity = dot(physicsMotion.linearVelocity, entity.transform.matrix.forward)
                        if let wingTip = engine.findEntity(named: "WingTip") {
                            updateWingTip(wingTip, forwardVelocity: forwardVelocity)
                        } else {
                            print("WingTip not found in engine \(engineName)")
                        }
                    }
                } else {
                    print("Engine \(engineName) not found in entity \(entity.name)")
                }
            }
        }
    }

    func updateExhaust(_ exhaust: Entity, throttle: Float) {
        exhaust.transform.scale.z = (throttle / 5) + 0.4
    }

    func updateVaporTrail(_ vaporTrail: Entity, throttle: Float) {
        if var particleEmitter = vaporTrail.components[ParticleEmitterComponent.self] {
            particleEmitter.mainEmitter.lifeSpan = Double(throttle) * 0.1
            vaporTrail.components.set(particleEmitter)
        } else {
            print("ParticleEmitterComponent not found for vaporTrail entity \(vaporTrail.name)")
        }
    }

    func updateWingTip(_ wingTip: Entity, forwardVelocity: Float) {
        guard var particleEmitter = wingTip.components[ParticleEmitterComponent.self] else { return }
        particleEmitter.mainEmitter.birthRate = sqrt(forwardVelocity) * 500
        particleEmitter.mainEmitter.lifeSpan = Double(forwardVelocity * 0.1)
        wingTip.components.set(particleEmitter)
    }
}

struct ShipVisualsComponent: Component {
    init() {
        ShipVisualsSystem.registerSystem()
    }
}
