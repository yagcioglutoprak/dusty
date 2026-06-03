import Foundation

/// Run `operation` over `items` with at most `maxConcurrent` tasks in flight at once,
/// returning the outputs in input order.
///
/// This replaces an unbounded `TaskGroup` (one task per item) so a scan over ~30
/// targets does not start 30 simultaneous directory walks and saturate the disk.
/// The group is seeded with `maxConcurrent` tasks; each completion starts the next.
func runBounded<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    _ operation: @Sendable @escaping (Item) async -> Output
) async -> [Output] {
    guard !items.isEmpty else { return [] }
    let cap = max(1, maxConcurrent)
    var results = [Output?](repeating: nil, count: items.count)

    await withTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        let seed = min(cap, items.count)
        while next < seed {
            let index = next
            let item = items[index]
            group.addTask { (index, await operation(item)) }
            next += 1
        }
        for await (index, output) in group {
            results[index] = output
            if next < items.count {
                let nextIndex = next
                let nextItem = items[nextIndex]
                group.addTask { (nextIndex, await operation(nextItem)) }
                next += 1
            }
        }
    }

    return results.compactMap { $0 }
}
