import Foundation

enum StepDirection: Equatable, Sendable {
    case up
    case down
}

enum StepSize: Equatable, Sendable {
    /// 1/16, the system's normal step.
    case normal
    /// 1/64, the system's ⇧⌥ step.
    case fine

    var grid: Double {
        switch self {
        case .normal: return 16
        case .fine: return 64
        }
    }
}

enum StepMath {
    /// Moves one step on the grid, snapping first:
    /// `clamp((round(current × grid) ± 1) / grid, 0…1)`.
    ///
    /// Snapping means a level between grid points lands on a grid point after
    /// one press, and float noise from the hardware (0.18750001) never drifts.
    static func step(_ current: Double, _ direction: StepDirection, _ size: StepSize) -> Double {
        let grid = size.grid
        let start = current.isFinite ? min(max(current, 0), 1) : 0
        let snapped = (start * grid).rounded()
        let next = direction == .up ? snapped + 1 : snapped - 1
        return min(max(next / grid, 0), 1)
    }
}
