import Foundation

// masklab-heal compiles SkimPlate.swift alone; SkimPlate.patchName goes through SkimExport.safeName (the patch is not
// written here), so a stand-in keeps the file compiling without the rest of Skim's export code.
nonisolated enum SkimExport {
    static func safeName(_ suggested: String, allowed: Set<String> = []) -> String? { suggested }
}
