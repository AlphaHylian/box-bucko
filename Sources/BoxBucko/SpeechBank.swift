import Foundation

/// Random flavor text for the speech bubble. Nothing scientific -- just enough
/// variety that BoxBucko feels alive instead of reading the same line twice in a row.
enum SpeechBank {
    private static let greetings = [
        "hi!", "hey there!", "sup", ":)", "boop", "hello!", "yo!", "hiya", "*waves*",
    ]

    private static let idleThoughts = [
        "mining for cookies", "block by block", "is it lunch yet?", "brb, respawning",
        "just vibing", "diamonds are nice", "watching your CPU", "beep boop", "loading...",
        "do you have any wood?", "creepers aw man", "I like your desktop", "got any emeralds?",
        "who needs a hotbar", "render distance: unlimited",
    ]

    private static let dragReactions = [
        "wheee!", "put me down!", "onward!", "heck yeah", "flying!",
    ]

    static func randomGreeting() -> String { greetings.randomElement()! }
    static func randomIdleThought() -> String { idleThoughts.randomElement()! }
    static func randomDragReaction() -> String { dragReactions.randomElement()! }
}
