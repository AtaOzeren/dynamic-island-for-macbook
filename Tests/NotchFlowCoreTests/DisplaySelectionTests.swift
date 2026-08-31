import Testing

@testable import NotchFlowCore

@Suite("DisplaySelection")
struct DisplaySelectionTests {
    private let builtIn = DisplayDescription(name: "Built-in Retina Display", isBuiltIn: true)
    private let studioDisplay = DisplayDescription(name: "Studio Display", isBuiltIn: false)

    @Test("selects the built-in display in automatic mode when it is the only screen")
    func automaticWithBuiltInOnly() {
        #expect(selectDisplay(from: [builtIn], preference: .automatic) == builtIn)
    }

    @Test("selects the built-in display automatically or when explicitly chosen")
    func builtInWithExternal() {
        #expect(selectDisplay(from: [studioDisplay, builtIn], preference: .automatic) == builtIn)
        #expect(selectDisplay(from: [studioDisplay, builtIn], preference: .builtIn) == builtIn)
        #expect(
            selectDisplay(from: [studioDisplay, builtIn], preference: .named(builtIn.name)) == builtIn
        )
    }

    @Test("selects a connected named external display")
    func connectedNamedExternal() {
        #expect(
            selectDisplay(from: [builtIn, studioDisplay], preference: .named(studioDisplay.name))
                == studioDisplay
        )
    }

    @Test("falls back to the built-in display when the named external disconnects")
    func disconnectedNamedExternal() {
        #expect(
            selectDisplay(from: [builtIn], preference: .named(studioDisplay.name)) == builtIn
        )
    }

    @Test("selects the sole external display in automatic clamshell mode")
    func automaticClamshell() {
        #expect(selectDisplay(from: [studioDisplay], preference: .automatic) == studioDisplay)
    }

    @Test("falls back to the connected external display in named clamshell mode")
    func namedClamshellFallback() {
        #expect(
            selectDisplay(from: [studioDisplay], preference: .named("Disconnected Display"))
                == studioDisplay
        )
    }

    @Test("returns to the built-in display in automatic mode after the lid reopens")
    func automaticAfterLidReopens() {
        #expect(selectDisplay(from: [studioDisplay, builtIn], preference: .automatic) == builtIn)
    }

    @Test("selects no display while no screens are available")
    func noScreensAvailable() {
        #expect(selectDisplay(from: [], preference: .automatic) == nil)
        #expect(selectDisplay(from: [], preference: .named(studioDisplay.name)) == nil)
    }

    @Test("stable identity distinguishes two displays with the same model name")
    func duplicateNamesUseIdentity() {
        let left = DisplayDescription(identifier: "101", name: "Studio Display", isBuiltIn: false)
        let right = DisplayDescription(identifier: "202", name: "Studio Display", isBuiltIn: false)

        #expect(
            selectDisplay(
                from: [left, right],
                preference: .identified(id: right.identifier, name: right.name)
            ) == right
        )
    }

    @Test("all-displays mode selects every connected display")
    func allDisplaysSelectsEveryScreen() {
        #expect(
            selectDisplays(
                from: [studioDisplay, builtIn],
                preference: .allDisplays
            ) == [studioDisplay, builtIn]
        )
    }

    @Test("all-displays mode degrades to the sole connected display")
    func allDisplaysWithOneScreen() {
        #expect(selectDisplays(from: [builtIn], preference: .allDisplays) == [builtIn])
        #expect(selectDisplays(from: [], preference: .allDisplays).isEmpty)
        #expect(normalizeDisplayPreference(.allDisplays, availableDisplayCount: 1) == .automatic)
        #expect(normalizeDisplayPreference(.allDisplays, availableDisplayCount: 0) == .automatic)
        #expect(normalizeDisplayPreference(.allDisplays, availableDisplayCount: 2) == .allDisplays)
    }

    @Test("single-display preferences still produce one target")
    func singleDisplayPreferenceProducesOneTarget() {
        #expect(selectDisplays(from: [studioDisplay, builtIn], preference: .automatic) == [builtIn])
        #expect(
            selectDisplays(
                from: [studioDisplay, builtIn],
                preference: .identified(id: studioDisplay.identifier, name: studioDisplay.name)
            ) == [studioDisplay]
        )
    }
}
