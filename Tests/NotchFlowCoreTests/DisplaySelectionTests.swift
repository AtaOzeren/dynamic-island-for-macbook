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
}
