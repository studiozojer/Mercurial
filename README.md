# Mercurial

A Swift physics library for natural momentum, friction, spring, and rubber-band effects in scroll and pan gestures.

## Features

- **Pure physics functions** - Stateless, composable, easy to test
- **1D and 2D support** - Use with scroll views or pan gestures
- **Frame-rate independent** - Works correctly on 60Hz and 120Hz displays
- **iOS-like feel** - Tuned defaults that match native scroll physics
- **Configurable** - Adjust friction, spring stiffness, damping, and more

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pageofswrds/Mercurial.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Package Dependencies > Enter the repository URL.

## Quick Start

### Pure Physics Functions

Use `Physics` directly for custom animation loops:

```swift
import Mercurial

// Rubber-band resistance (for overscroll)
let visualOffset = Physics.rubberBand(offset: 150, limit: 100, coefficient: 0.55)
// Result: ~60pt (approaches but never exceeds limit)

// Friction-based velocity decay
var velocity: CGFloat = 500
velocity = Physics.applyFriction(velocity: velocity, friction: 0.95)
// Result: 475pt/s

// Spring force for boundary bounce
let force = Physics.springForce(
    displacement: 50,    // 50pt past boundary
    velocity: 0,
    stiffness: 200,
    damping: 30
)
// Result: negative force pulling back toward boundary

// Position integration
let newPosition = Physics.integrate(position: 100, velocity: 500, deltaTime: 1.0/60.0)
// Result: 108.33pt
```

### 2D Physics (for Pan Gestures)

All physics functions have 2D variants for `CGPoint`:

```swift
// 2D rubber band
let offset = Physics.rubberBand(
    offset: CGPoint(x: 100, y: 200),
    limit: 150,
    coefficient: 0.55
)

// 2D friction
let newVelocity = Physics.applyFriction(
    velocity: CGPoint(x: 300, y: 400),
    friction: 0.95
)

// Speed (magnitude) of velocity vector
let speed = Physics.speed(CGPoint(x: 3, y: 4))  // 5.0
```

### Momentum Animator

For common use cases, use the pre-built animator classes:

```swift
import Mercurial

// 1D Momentum (vertical scroll)
let animator = Momentum1DAnimator()
animator.bounds = (min: 0, max: contentHeight - viewportHeight)
animator.start(velocity: -gestureVelocity)

// In your frame loop (e.g., TimelineView):
if animator.isActive {
    animator.update()
    scrollOffset = animator.position
}

// 2D Momentum (pan gesture)
let panAnimator = Momentum2DAnimator()
panAnimator.bounds = PhysicsBounds(
    min: CGPoint(x: -maxPanX, y: -maxPanY),
    max: .zero
)
panAnimator.start(velocity: gestureVelocity)
```

## API Reference

### Physics

Pure physics functions - all are `static` and stateless.

#### Rubber Band

```swift
// 1D
static func rubberBand(offset: CGFloat, limit: CGFloat, coefficient: CGFloat) -> CGFloat

// 2D
static func rubberBand(offset: CGPoint, limit: CGFloat, coefficient: CGFloat) -> CGPoint
static func rubberBand(offset: CGPoint, limits: CGPoint, coefficient: CGFloat) -> CGPoint
```

Creates the "stretchy" feel when dragging past boundaries. Higher coefficient = less resistance.

#### Spring Force

```swift
// 1D
static func springForce(displacement: CGFloat, velocity: CGFloat, stiffness: CGFloat, damping: CGFloat) -> CGFloat

// 2D
static func springForce(displacement: CGPoint, velocity: CGPoint, stiffness: CGFloat, damping: CGFloat) -> CGPoint
```

Damped harmonic oscillator for boundary bounce. High damping = no oscillation.

#### Friction

```swift
// 1D
static func applyFriction(velocity: CGFloat, friction: CGFloat) -> CGFloat

// 2D
static func applyFriction(velocity: CGPoint, friction: CGFloat) -> CGPoint
```

Velocity decay per frame. At 0.95, velocity decays to ~5% after 60 frames.

#### Integration

```swift
// 1D
static func integrate(position: CGFloat, velocity: CGFloat, deltaTime: CGFloat) -> CGFloat

// 2D
static func integrate(position: CGPoint, velocity: CGPoint, deltaTime: CGFloat) -> CGPoint
```

Euler integration: `position += velocity * deltaTime`

### Configuration

#### MomentumConfiguration

```swift
MomentumConfiguration(
    friction: CGFloat = 0.95,          // Velocity decay per frame
    minimumVelocity: CGFloat = 50,     // Stop threshold (pt/s)
    maxDeltaTime: CGFloat = 1.0/30.0   // Frame time clamp
)

// Presets
.default  // Standard iOS feel
.snappy   // friction: 0.90
.smooth   // friction: 0.97
```

#### SpringConfiguration

```swift
SpringConfiguration(
    stiffness: CGFloat = 200,  // Spring constant (k)
    damping: CGFloat = 30      // Damping coefficient (c)
)

// Presets
.default  // Overdamped, no bounce
.bouncy   // stiffness: 300, damping: 15
.soft     // stiffness: 100, damping: 20
```

#### RubberBandConfiguration

```swift
RubberBandConfiguration(
    coefficient: CGFloat = 0.55,  // Resistance (0-1, higher = less)
    limit: CGFloat = 240          // Maximum visual offset
)

// Presets
.default  // iOS-like
.tight    // coefficient: 0.3, limit: 150
.loose    // coefficient: 0.7, limit: 300
```

#### PhysicsBounds

```swift
PhysicsBounds(min: CGPoint, max: CGPoint)
PhysicsBounds(rect: CGRect)
PhysicsBounds.unbounded  // Infinite in all directions

// Methods
func contains(_ point: CGPoint) -> Bool
func clamp(_ point: CGPoint) -> CGPoint
func displacement(from point: CGPoint) -> CGPoint
```

### Momentum Animators

#### Momentum1DAnimator

```swift
let animator = Momentum1DAnimator(
    configuration: PhysicsConfiguration = .default,
    initialPosition: CGFloat = 0
)

// Properties
animator.position: CGFloat      // Current position
animator.velocity: CGFloat      // Current velocity
animator.state: MomentumState   // .idle, .momentum, .bouncing, .settling
animator.isActive: Bool         // Whether animation is running
animator.bounds: (min: CGFloat, max: CGFloat)?

// Methods
animator.start(velocity: CGFloat)   // Start momentum
animator.stop()                     // Stop immediately
animator.setPosition(_ position: CGFloat)  // Set position (e.g., during drag)
animator.update() -> Bool           // Update physics, returns isActive
```

#### Momentum2DAnimator

```swift
let animator = Momentum2DAnimator(
    configuration: PhysicsConfiguration = .default,
    initialPosition: CGPoint = .zero
)

// Properties (same as 1D but with CGPoint)
animator.position: CGPoint
animator.velocity: CGPoint
animator.bounds: PhysicsBounds?

// Methods
animator.start(velocity: CGPoint)
animator.stop()
animator.setPosition(_ position: CGPoint)
animator.update() -> Bool
animator.rubberBandOffset(_ rawOffset: CGPoint) -> CGPoint  // For drag rubber-banding
```

## Pan/Zoom with GestureCoordinator

The `GestureCoordinator` provides a complete solution for pan and zoom gestures:

```swift
import Mercurial

@MainActor
class CanvasViewModel {
    let coordinator = GestureCoordinator(configuration: .init(
        transform: TransformConfiguration(minScale: 0.5, maxScale: 5.0),
        contentBounds: PhysicsBounds(
            min: CGPoint(x: -500, y: -500),
            max: CGPoint(x: 500, y: 500)
        )
    ))

    // Handle pan gesture
    func onPanChanged(_ translation: CGPoint, center: CGPoint) {
        coordinator.panChanged(translation, center: center)
    }

    func onPanEnded(velocity: CGPoint, center: CGPoint) {
        coordinator.panEnded(velocity: velocity, center: center)
    }

    // Handle zoom gesture
    func onZoomChanged(scale: CGFloat, anchor: CGPoint, center: CGPoint) {
        coordinator.zoomChanged(scale: scale, anchor: anchor, center: center)
    }

    func onZoomEnded(center: CGPoint) {
        coordinator.zoomEnded(center: center)
    }
}
```

### Transform for Coordinate Conversion

Use `Transform` for viewport ↔ canvas coordinate conversion:

```swift
let transform = Transform(scale: 2.0, offset: CGPoint(x: 100, y: 50))
let center = CGPoint(x: 200, y: 200)

// Convert tap location to canvas space for hit testing
let canvasPoint = transform.toCanvas(tapLocation, center: center)

// Convert canvas point to viewport space for rendering
let viewportPoint = transform.toViewport(nodePosition, center: center)

// Element scaling (scales slower than content for usability)
let textSize = baseFontSize * transform.textScale()   // At 3x: 1.8x
let hitRadius = baseRadius * transform.hitAreaScale() // At 3x: 1.6x
```

### Hit Testing

Transform-aware hit testing for interactive elements:

```swift
struct MapPin: Hittable {
    let id: String
    var position: CGPoint
    var hitRadius: CGFloat { 22 }  // 44pt touch target
}

let pins = [MapPin(id: "home", x: 100, y: 200), ...]

// Hit test with transform
let result = HitTest.test(
    at: tapLocation,
    in: pins,
    transform: coordinator.transform,
    center: center
)

if let closest = result.closest {
    print("Tapped: \(closest.id)")
}

// Or use coordinator convenience method
let result = coordinator.hitTest(at: tapLocation, in: pins, center: center)
```

## Usage with SwiftUI

### TimelineView Pattern

```swift
struct MomentumScrollView: View {
    @State private var offset: CGFloat = 0
    @State private var animator = Momentum1DAnimator()

    var body: some View {
        TimelineView(.animation(paused: !animator.isActive)) { timeline in
            content
                .offset(y: -offset)
                .gesture(dragGesture)
                .onChange(of: timeline.date) { _, _ in
                    if animator.isActive {
                        animator.update()
                        offset = animator.position
                    }
                }
        }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                animator.stop()  // Catch momentum on touch
                animator.setPosition(offset + value.translation.height)
            }
            .onEnded { value in
                animator.start(velocity: -value.velocity.height)
            }
    }
}
```

## Roadmap

- [x] **2D Panning** - Full canvas panning with momentum and boundaries
- [x] **Zooming** - Pinch-to-zoom with min/max scale limits, anchor point math
- [x] **Hit Testing** - Transform-aware hit detection with configurable hit radii
- [ ] **Trackpad Support** - macOS trackpad gestures (scroll, pinch, rotate)

### Free-body primitive

`Pose` + `FreeBodyAnimator` model a free object with a transform (position +
rotation) and momentum (linear + angular), coasting to rest with contained walls
(`PhysicsBounds`) and an optional angular detent (`AngularSettleConfiguration`).
Distinct from the viewport `Transform`/`GestureCoordinator` (pan/zoom) — additive,
not a retrofit.

**Evolution:** a future `FreeBodySimulation` (id-keyed, multi-body, stepping all
bodies in one `update()` — the home for inter-body collision) is reached by having
the simulation *own* a collection of `FreeBodyAnimator`s, not by replacing them.

## License

MIT License
