// FolderNode.swift
// ytsplayer

import Foundation

struct FolderNode: Identifiable {
    let id: String
    let name: String
    let isDirectory: Bool
    let url: URL
    var children: [FolderNode]?
    
    // Helper to scan a directory and build the tree
    static func scanDirectory(at url: URL) -> [FolderNode] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        
        var nodes: [FolderNode] = []
        
        for case let fileURL as URL in enumerator {
            let res = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = res?.isDirectory ?? false
            
            if isDir {
                let children = scanDirectory(at: fileURL)
                nodes.append(FolderNode(
                    id: fileURL.path,
                    name: fileURL.lastPathComponent,
                    isDirectory: true,
                    url: fileURL,
                    children: children.isEmpty ? nil : children // nil means empty or leaf
                ))
            } else if fileURL.pathExtension.lowercased() == "flac" {
                nodes.append(FolderNode(
                    id: fileURL.path,
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    isDirectory: false,
                    url: fileURL,
                    children: nil
                ))
            }
        }
        
        // Sort: Folders first, then files alphabetically
        nodes.sort { a, b in
            if a.isDirectory == b.isDirectory {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return a.isDirectory && !b.isDirectory
        }
        
        return nodes
    }
}
