import Foundation

/// Tracks unique, half-open byte ranges from parallel and out-of-order reads.
struct ByteRangeCoverage {
    private(set) var coveredBytes: UInt64 = 0
    private var ranges: [(start: UInt64, end: UInt64)] = []

    mutating func add(start: UInt64, length: UInt64, limit: UInt64) {
        guard length > 0, limit > 0, start < limit else { return }
        let addition = start.addingReportingOverflow(length)
        let end = min(limit, addition.overflow ? limit : addition.partialValue)
        guard end > start else { return }

        var mergedStart = start
        var mergedEnd = end
        var merged: [(start: UInt64, end: UInt64)] = []
        merged.reserveCapacity(ranges.count + 1)
        var inserted = false

        for range in ranges {
            if range.end < mergedStart {
                merged.append(range)
            } else if mergedEnd < range.start {
                if !inserted {
                    merged.append((start: mergedStart, end: mergedEnd))
                    inserted = true
                }
                merged.append(range)
            } else {
                mergedStart = min(mergedStart, range.start)
                mergedEnd = max(mergedEnd, range.end)
            }
        }

        if !inserted {
            merged.append((start: mergedStart, end: mergedEnd))
        }

        ranges = merged
        coveredBytes = ranges.reduce(UInt64(0)) { $0 + ($1.end - $1.start) }
    }

    mutating func reset() {
        ranges.removeAll(keepingCapacity: true)
        coveredBytes = 0
    }
}
