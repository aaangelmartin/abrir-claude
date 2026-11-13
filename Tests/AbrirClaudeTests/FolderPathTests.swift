@testable import AbrirClaude
import Foundation
import Testing

@Suite struct FolderPathTests {
    let home = "/Users/test"

    @Test func emptyOpensHome() {
        #expect(FolderPath.resolve("", home: home) == home)
        #expect(FolderPath.resolve("   ", home: home) == home)
        #expect(FolderPath.resolve("~", home: home) == home)
    }

    @Test func relativeIsUnderHome() {
        #expect(FolderPath.resolve("proyectos/mi-app", home: home) == "/Users/test/proyectos/mi-app")
        #expect(FolderPath.resolve("  proyectos/mi-app  ", home: home) == "/Users/test/proyectos/mi-app")
        #expect(FolderPath.resolve("~/proyectos", home: home) == "/Users/test/proyectos")
    }

    @Test func absoluteStaysAbsolute() {
        #expect(FolderPath.resolve("/Volumes/disco/obra", home: home) == "/Volumes/disco/obra")
    }

    @Test func displayIsRelativeInsideHome() {
        #expect(FolderPath.display("/Users/test/a/b", home: home) == "a/b")
        #expect(FolderPath.display("/Users/test", home: home) == "")
        #expect(FolderPath.display("/Volumes/x", home: home) == "/Volumes/x")
        #expect(FolderPath.display("/Users/testing", home: home) == "/Users/testing")
    }

    @Test func commandQuotesForTheShell() {
        #expect(FolderPath.shellQuoted("it's here") == #"'it'\''s here'"#)
        #expect(FolderPath.command(for: "/Volumes/Mi Disco") == "cd '/Volumes/Mi Disco' && claude")
        #expect(FolderPath.command(for: "/x", args: ["--model", "opus"]) == "cd '/x' && claude --model opus")
        #expect(FolderPath.shellWord("a b") == "'a b'")
    }
}

@Suite struct SuggestionsTests {
    let root: String = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("abrir-claude-tests-\(UUID().uuidString)")
        for sub in ["proyectos/alfa", "proyectos/Beta", "proyectos/.oculta", "Documentos"] {
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("proyectos/archivo.txt").path, contents: Data())
        return dir.path
    }()

    @Test func matchesFoldersByPrefixIgnoringCase() {
        #expect(Suggestions.completions(for: "pro", home: root) == ["proyectos/"])
        #expect(Suggestions.completions(for: "proyectos/b", home: root) == ["proyectos/Beta/"])
    }

    @Test func listsOnlyVisibleFolders() {
        #expect(Suggestions.completions(for: "proyectos/", home: root) == ["proyectos/alfa/", "proyectos/Beta/"])
        #expect(Suggestions.completions(for: "proyectos/.", home: root) == ["proyectos/.oculta/"])
    }

    @Test func absolutePathsCompleteAbsolute() {
        #expect(Suggestions.completions(for: root + "/Doc", home: "/nowhere") == [root + "/Documentos/"])
    }

    @Test func nothingForEmptyOrMissing() {
        #expect(Suggestions.completions(for: "", home: root).isEmpty)
        #expect(Suggestions.completions(for: "no/existe/", home: root).isEmpty)
    }
}

@MainActor
@Suite struct DefaultSelectionTests {
    let root: String = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("abrir-claude-sel-\(UUID().uuidString)")
        for sub in ["Developer/app", "Desktop"] {
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return dir.path
    }()

    @Test func emptyLightsNothing() {
        #expect(PaletteModel.defaultSelection(text: "", rows: ["Developer"], home: root) == nil)
    }

    @Test func partialLightsTheFirstMatch() {
        #expect(PaletteModel.defaultSelection(text: "de", rows: ["Desktop/", "Developer/"], home: root) == 0)
    }

    @Test func existingFolderNameLightsItself() {
        #expect(PaletteModel.defaultSelection(text: "Developer", rows: ["Developer/"], home: root) == 0)
    }

    @Test func existingFolderWithSubfoldersLightsNothing() {
        #expect(PaletteModel.defaultSelection(text: "Developer/", rows: ["Developer/app/"], home: root) == nil)
    }
}

@Suite struct LaunchOptionsTests {
    @Test func defaultsAddNothing() {
        #expect(LaunchOptions.args(for: [0, 0, 0, 0]).isEmpty)
    }

    @Test func picksBecomeFlagsInOrder() {
        // opus, high effort, plan, continue
        #expect(LaunchOptions.args(for: [2, 3, 3, 1]) == ["--model", "opus", "--effort", "high", "--permission-mode", "plan", "--continue"])
        // max effort, bypass permissions
        #expect(LaunchOptions.args(for: [0, 5, 6, 0]) == ["--effort", "max", "--permission-mode", "bypassPermissions"])
    }

    @Test func rememberedPicksSurviveAndOutOfRangeFallsBack() {
        let defaults = UserDefaults(suiteName: "abrir-claude-tests-\(UUID().uuidString)")!
        LaunchOptions.save([1, 5, 2, 2], defaults)
        #expect(LaunchOptions.load(defaults) == [1, 5, 2, 2])
        defaults.set("Gone", forKey: "option.model.label")
        #expect(LaunchOptions.load(defaults)[0] == 0)
    }

    @Test func oldIndexPicksStillLoad() {
        let defaults = UserDefaults(suiteName: "abrir-claude-tests-\(UUID().uuidString)")!
        defaults.set(3, forKey: "option.effort")
        defaults.set(99, forKey: "option.model")
        #expect(LaunchOptions.load(defaults)[1] == 3)
        #expect(LaunchOptions.load(defaults)[0] == 0)
    }
}

@Suite struct ModelVersionsTests {
    @Test func keepsTheNewestOfEachFamily() {
        let text = "x claude-opus-4-8 y claude-opus-5-5 claude-opus-5 claude-sonnet-4-5-20250929 claude-sonnet-5-5 claude-haiku-4-5-20251001 claude-fable-5-1 claude-fable-5-2 claude-fable-5 claude-3-5-sonnet"
        let v = ModelVersions.newest(in: Data(text.utf8))
        #expect(v == ["opus": "5.5", "sonnet": "5.5", "haiku": "4.5", "fable": "5.2"])
    }

    @Test func aWholeNumberHasNoDot() {
        #expect(ModelVersions.newest(in: Data("claude-opus-6 claude-opus-5-5".utf8)) == ["opus": "6"])
    }

    @Test func aDateIsNotAMinor() {
        #expect(ModelVersions.newest(in: Data("claude-opus-4-20250514".utf8)) == ["opus": "4"])
    }
}

@Suite struct InstalledClaudeTests {
    /// on a mac with claude installed, its own binary names a number for every family
    @Test func installedClaudeNamesEveryFamily() throws {
        guard let binary = ModelVersions.binary() else { return }
        let start = Date()
        let found = ModelVersions.scan(binary)
        print("model versions:", found, "in", Date().timeIntervalSince(start), "s")
        #expect(Set(found.keys) == Set(ModelVersions.families))
    }
}
