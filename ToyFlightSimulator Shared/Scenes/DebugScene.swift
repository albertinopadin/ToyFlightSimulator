//
//  DebugScene.swift
//  ToyFlightSimulator
//
//  Created for the missing-material draw check (2026-11-26)
//

/// The smallest scene that draws something: a free camera, a sun, one `Triangle` and one `Line`.
///
/// It is a deterministic check for draws that have no material of their own. The `Triangle`
/// model is built from a hand-made submesh (`Submesh.init(indices:)`), which has no material,
/// and it is the only opaque model here, so it is the first draw of the G-buffer stage on every
/// frame. A draw that binds no material fails Metal's validation in that position ("missing
/// Buffer binding at index 9 for material[0]"), where in a larger scene it usually reuses the
/// material of the model drawn before it and the failure depends on the draw order of the frame.
/// `DrawManager.drawSubmeshes` and `DrawManager.DrawLines` bind `Material()` for such draws.
///
/// Expected picture: a triangle in the default material's PINK_DEBUG_COLOR with a green line
/// under it. To check `DrawLines` alone, comment out `addChild(triangle)`: with no opaque model
/// the line is the first draw of the stage.
final class DebugScene: GameScene {
    var debugCamera = DebugCamera()
    var sun = Sun()

    override func buildScene() {
        // The camera looks down +Z, so it sees the origin from the -Z side.
        debugCamera.setPosition(0, 0, -5)
        addCamera(debugCamera)

        // Above and behind the camera, so it lights the faces that point toward -Z.
        sun.setPosition(0, 5, -5)
        // Explicit direction, as in the Flightbox scenes: the sun node then shifts with the
        // floating origin like any other node. Must come after setPosition: it reads the position.
        sun.setLightDirection(sun.getPosition())
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.4)
        sun.setLightDiffuseIntensity(0.5)
        addLight(sun)

        // The triangle's front face (clockwise winding, normal +Z) points toward +Z, away from
        // the camera, and the pass culls back faces. Half a turn about Y points it at the camera.
        let triangle = Triangle()
        triangle.rotateY(Float(180).toRadians)
        addChild(triangle)

        let line = Line(startPoint: [-2, -1.5, 0],
                        endPoint: [2, -1.5, 0],
                        color: GREEN_COLOR)
        addChild(line)
    }
}
