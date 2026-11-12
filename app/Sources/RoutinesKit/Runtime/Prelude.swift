import Foundation

/// The bundled `packages/prelude` that runs first in each plugin context.
enum Prelude {
    static let source: String = Bundle.module.url(forResource: "prelude", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
}
