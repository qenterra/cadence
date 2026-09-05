import Foundation
import simd

struct CadenceModeGradientVertex: Equatable, Sendable {
    let position: SIMD3<Float>
    let textureCoordinate: SIMD2<Float>
}

struct CadenceModeGradientMesh: Sendable {
    let vertices: [CadenceModeGradientVertex]
    let indices: [UInt32]
}

enum CadenceModeGradientReference {
    static let planeSize: Float = 1.5
    static let segmentCount = 200
    static let noiseFrequency = SIMD2<Float>(3, 6)
    static let noiseAmount: Float = 0.2
    static let noiseSpeed: Float = 0.02
    static let cameraFieldOfView: Float = 35
    static let cameraNearPlane: Float = 0.1
    static let cameraFarPlane: Float = 100
    static let cameraPosition = SIMD3<Float>(0, 0.5, 0.4)

    static var modelMatrix: simd_float4x4 {
        let angle = -Float.pi / 2
        let cosine = cos(angle)
        let sine = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, cosine, sine, 0),
            SIMD4(0, -sine, cosine, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func viewProjectionMatrix(
        aspectRatio: Float
    ) -> simd_float4x4 {
        projectionMatrix(aspectRatio: aspectRatio) * viewMatrix
    }

    static func makeMesh() -> CadenceModeGradientMesh {
        let verticesPerSide = segmentCount + 1
        let vertexCount = verticesPerSide * verticesPerSide
        let indexCount = segmentCount * segmentCount * 6
        let halfSize = planeSize / 2
        let step = planeSize / Float(segmentCount)

        var vertices: [CadenceModeGradientVertex] = []
        vertices.reserveCapacity(vertexCount)
        for row in 0 ... segmentCount {
            let rowOffset = Float(row) * step - halfSize
            for column in 0 ... segmentCount {
                let columnOffset = Float(column) * step - halfSize
                vertices.append(
                    CadenceModeGradientVertex(
                        position: SIMD3(
                            columnOffset,
                            -rowOffset,
                            0
                        ),
                        textureCoordinate: SIMD2(
                            Float(column) / Float(segmentCount),
                            1 - Float(row) / Float(segmentCount)
                        )
                    )
                )
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        for row in 0 ..< segmentCount {
            for column in 0 ..< segmentCount {
                let topLeft = UInt32(column + verticesPerSide * row)
                let bottomLeft = UInt32(
                    column + verticesPerSide * (row + 1)
                )
                let bottomRight = bottomLeft + 1
                let topRight = topLeft + 1
                indices.append(contentsOf: [
                    topLeft,
                    bottomLeft,
                    topRight,
                    bottomLeft,
                    bottomRight,
                    topRight,
                ])
            }
        }

        return CadenceModeGradientMesh(
            vertices: vertices,
            indices: indices
        )
    }

    static func shaderColors(
        for palette: RhythmAccentPalette
    ) -> [SIMD3<Float>] {
        expandedColors(for: palette).map { color in
            SIMD3(
                linearComponent(color.red),
                linearComponent(color.green),
                linearComponent(color.blue)
            )
        }
    }

    private static func expandedColors(
        for palette: RhythmAccentPalette
    ) -> [RhythmPulseColor] {
        let colors = palette.colors.isEmpty
            ? RhythmAccentPalette.cadenceFallback.colors
            : Array(palette.colors.prefix(5))
        switch colors.count {
        case 1:
            let color = colors[0]
            return [
                color.scaledForGradient(by: 0.45),
                color.scaledForGradient(by: 0.7),
                color,
                color.scaledForGradient(by: 1.12),
                color.scaledForGradient(by: 0.58),
            ]
        case 2:
            return [
                colors[0],
                colors[0].mixedForGradient(with: colors[1], amount: 0.35),
                colors[1],
                colors[1].mixedForGradient(with: colors[0], amount: 0.35),
                colors[0].scaledForGradient(by: 0.55),
            ]
        case 3:
            return [
                colors[0],
                colors[0].mixedForGradient(with: colors[1], amount: 0.5),
                colors[1],
                colors[1].mixedForGradient(with: colors[2], amount: 0.5),
                colors[2],
            ]
        case 4:
            return colors + [
                colors[3].mixedForGradient(with: colors[0], amount: 0.5),
            ]
        default:
            return colors
        }
    }

    private static func linearComponent(_ component: Double) -> Float {
        let clamped = min(max(component, 0), 1)
        if clamped <= 0.040_45 {
            return Float(clamped / 12.92)
        }
        return Float(pow((clamped + 0.055) / 1.055, 2.4))
    }

    private static var viewMatrix: simd_float4x4 {
        let target = SIMD3<Float>.zero
        let up = SIMD3<Float>(0, 1, 0)
        let backward = simd_normalize(cameraPosition - target)
        let right = simd_normalize(simd_cross(up, backward))
        let cameraUp = simd_cross(backward, right)
        return simd_float4x4(columns: (
            SIMD4(right.x, cameraUp.x, backward.x, 0),
            SIMD4(right.y, cameraUp.y, backward.y, 0),
            SIMD4(right.z, cameraUp.z, backward.z, 0),
            SIMD4(
                -simd_dot(right, cameraPosition),
                -simd_dot(cameraUp, cameraPosition),
                -simd_dot(backward, cameraPosition),
                1
            )
        ))
    }

    private static func projectionMatrix(
        aspectRatio: Float
    ) -> simd_float4x4 {
        let safeAspectRatio = max(aspectRatio, 0.000_001)
        let radians = cameraFieldOfView * .pi / 180
        let verticalScale = 1 / tan(radians / 2)
        let horizontalScale = verticalScale / safeAspectRatio
        let depthScale = cameraFarPlane
            / (cameraNearPlane - cameraFarPlane)
        return simd_float4x4(columns: (
            SIMD4(horizontalScale, 0, 0, 0),
            SIMD4(0, verticalScale, 0, 0),
            SIMD4(0, 0, depthScale, -1),
            SIMD4(0, 0, cameraNearPlane * depthScale, 0)
        ))
    }
}

struct CadenceModeGradientPaletteTransition: Sendable {
    static let duration: TimeInterval = 0.8

    private var sourceColors: [SIMD3<Float>]
    private var targetColors: [SIMD3<Float>]
    private var startedAt: TimeInterval
    private var transitionDuration: TimeInterval

    init(palette: RhythmAccentPalette) {
        let colors = CadenceModeGradientReference.shaderColors(for: palette)
        sourceColors = colors
        targetColors = colors
        startedAt = 0
        transitionDuration = 0
    }

    mutating func retarget(
        to palette: RhythmAccentPalette,
        at timestamp: TimeInterval,
        reduceMotion: Bool
    ) {
        let nextColors = CadenceModeGradientReference.shaderColors(
            for: palette
        )
        if nextColors == targetColors {
            if reduceMotion {
                sourceColors = nextColors
                startedAt = timestamp
                transitionDuration = 0
            }
            return
        }

        let visibleColors = colors(at: timestamp)
        sourceColors = reduceMotion ? nextColors : visibleColors
        targetColors = nextColors
        startedAt = timestamp
        transitionDuration = reduceMotion ? 0 : Self.duration
    }

    func colors(at timestamp: TimeInterval) -> [SIMD3<Float>] {
        guard transitionDuration > 0 else {
            return targetColors
        }
        let progress = Float(
            min(
                max((timestamp - startedAt) / transitionDuration, 0),
                1
            )
        )
        let easedProgress = progress * progress * (3 - 2 * progress)
        return zip(sourceColors, targetColors).map { source, target in
            source + (target - source) * easedProgress
        }
    }
}

private extension RhythmPulseColor {
    func mixedForGradient(
        with other: RhythmPulseColor,
        amount: Double
    ) -> RhythmPulseColor {
        RhythmPulseColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    func scaledForGradient(by amount: Double) -> RhythmPulseColor {
        RhythmPulseColor(
            red: min(max(red * amount, 0), 1),
            green: min(max(green * amount, 0), 1),
            blue: min(max(blue * amount, 0), 1)
        )
    }
}

enum CadenceModeBackgroundContrast {
    private static let minimumOpacity = 0.10
    private static let maximumOpacity = 0.22
    private static let activeCombinedOpacity = 0.62
    private static let lowerLuminance = 0.15
    private static let upperLuminance = 0.85
    private static let tintScale = 0.28

    static func opacity(for palette: RhythmAccentPalette) -> Double {
        let peakLuminance = colors(for: palette)
            .map(\.relativeLuminance)
            .max() ?? lowerLuminance
        let progress = min(
            max(
                (peakLuminance - lowerLuminance)
                    / (upperLuminance - lowerLuminance),
                0
            ),
            1
        )
        return minimumOpacity
            + (maximumOpacity - minimumOpacity) * progress
    }

    static func activeTintOpacity(
        for palette: RhythmAccentPalette
    ) -> Double {
        let idleOpacity = opacity(for: palette)
        return (activeCombinedOpacity - idleOpacity) / (1 - idleOpacity)
    }

    static func tint(for palette: RhythmAccentPalette) -> RhythmPulseColor {
        let darkestColor = colors(for: palette).min {
            $0.relativeLuminance < $1.relativeLuminance
        } ?? RhythmPulseColor(red: 0, green: 0, blue: 0)
        return darkestColor.scaledForGradient(by: tintScale)
    }

    static func transitionDuration(
        hasLiveEffects _: Bool,
        reduceMotion: Bool
    ) -> TimeInterval {
        if reduceMotion {
            return 0.1
        }
        return 1.4
    }

    private static func colors(
        for palette: RhythmAccentPalette
    ) -> [RhythmPulseColor] {
        palette.colors.isEmpty
            ? RhythmAccentPalette.cadenceFallback.colors
            : palette.colors
    }
}

struct CadenceModeBackgroundAppearance: Equatable, Sendable {
    let isAnimated: Bool
    let maximumAnimationFramesPerSecond: Int

    static func resolve(
        reduceMotion: Bool,
        reduceTransparency _: Bool,
        increasedContrast _: Bool
    ) -> CadenceModeBackgroundAppearance {
        CadenceModeBackgroundAppearance(
            isAnimated: !reduceMotion,
            maximumAnimationFramesPerSecond: 60
        )
    }
}
