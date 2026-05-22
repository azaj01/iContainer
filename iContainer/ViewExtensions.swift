import SwiftUI

extension View {
    /// Conditionally applies a modifier chain to this view.
    ///
    /// Use it to opt in to a modifier only when some runtime condition
    /// is true, for example a `.searchable` field that should only
    /// appear when a service is running.
    ///
    /// ```swift
    /// List { ... }
    ///     .applyIf(isServiceRunning) { view in
    ///         view.searchable(text: $query)
    ///     }
    /// ```
    ///
    /// The transform sees this view as `Self`, so any modifier valid on
    /// the original chain (including ones that change the concrete
    /// return type, like `.searchable`) works inside the closure.
    @ViewBuilder
    func applyIf<Transform: View>(
        _ condition: Bool,
        _ transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
