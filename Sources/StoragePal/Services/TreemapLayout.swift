import Foundation
import SwiftUI

struct TreemapNode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let bytes: Int64
    let isDirectory: Bool
    var children: [TreemapNode]
    var rect: CGRect = .zero

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TreemapNode, rhs: TreemapNode) -> Bool {
        lhs.id == rhs.id
    }
}

enum TreemapBuilder {
    static func buildTree(for url: URL, maxDepth: Int = 2) -> TreemapNode {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return TreemapNode(id: url.path, name: url.lastPathComponent, url: url, bytes: 0, isDirectory: false, children: [])
        }

        if !isDir.boolValue {
            let size = Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
            return TreemapNode(id: url.path, name: url.lastPathComponent, url: url, bytes: size, isDirectory: false, children: [])
        }

        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return TreemapNode(id: url.path, name: url.lastPathComponent, url: url, bytes: 0, isDirectory: true, children: [])
        }

        var children: [TreemapNode] = []
        var totalBytes: Int64 = 0

        for item in contents {
            var itemIsDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &itemIsDir) {
                if itemIsDir.boolValue {
                    if maxDepth > 0 {
                        let childNode = buildTree(for: item, maxDepth: maxDepth - 1)
                        if childNode.bytes > 5_000_000 { // Skip tiny folders < 5 MB for clarity
                            children.append(childNode)
                            totalBytes += childNode.bytes
                        }
                    } else {
                        let size = measureSize(item)
                        if size > 5_000_000 {
                            let childNode = TreemapNode(id: item.path, name: item.lastPathComponent, url: item, bytes: size, isDirectory: true, children: [])
                            children.append(childNode)
                            totalBytes += size
                        }
                    }
                } else {
                    let size = Int64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    if size > 10_000_000 { // Skip tiny files < 10 MB in top-level view
                        let fileNode = TreemapNode(id: item.path, name: item.lastPathComponent, url: item, bytes: size, isDirectory: false, children: [])
                        children.append(fileNode)
                        totalBytes += size
                    }
                }
            }
        }

        let sortedChildren = children.sorted { $0.bytes > $1.bytes }
        return TreemapNode(id: url.path, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, url: url, bytes: totalBytes, isDirectory: true, children: sortedChildren)
    }

    private static func measureSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    static func layout(nodes: [TreemapNode], in rect: CGRect) -> [TreemapNode] {
        guard !nodes.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let total = Double(nodes.reduce(0) { $0 + $1.bytes })
        guard total > 0 else { return [] }

        var results: [TreemapNode] = []
        var remainingRect = rect
        var remainingWeight = total

        for (index, node) in nodes.enumerated() {
            guard remainingRect.width > 0, remainingRect.height > 0 else { break }
            let isLast = (index == nodes.count - 1) || (remainingWeight <= Double(node.bytes))
            let ratio = isLast ? 1.0 : min(max(Double(node.bytes) / remainingWeight, 0.01), 1.0)
            var nodeRect = CGRect.zero

            if remainingRect.width > remainingRect.height {
                let width = isLast ? remainingRect.width : remainingRect.width * CGFloat(ratio)
                nodeRect = CGRect(x: remainingRect.origin.x, y: remainingRect.origin.y, width: min(width, remainingRect.width), height: remainingRect.height)
                remainingRect.origin.x += nodeRect.width
                remainingRect.size.width = max(remainingRect.size.width - nodeRect.width, 0)
            } else {
                let height = isLast ? remainingRect.height : remainingRect.height * CGFloat(ratio)
                nodeRect = CGRect(x: remainingRect.origin.x, y: remainingRect.origin.y, width: remainingRect.width, height: min(height, remainingRect.height))
                remainingRect.origin.y += nodeRect.height
                remainingRect.size.height = max(remainingRect.size.height - nodeRect.height, 0)
            }

            remainingWeight = max(remainingWeight - Double(node.bytes), 0.001)
            var updatedNode = node
            updatedNode.rect = nodeRect
            results.append(updatedNode)
        }

        return results
    }
}
