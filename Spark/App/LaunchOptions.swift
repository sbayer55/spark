import Foundation

/// Launch arguments for automated testing, read from the `UserDefaults` argument domain, e.g.
/// `open Spark.app --args -SparkEphemeralSecrets YES -SparkShowPanelOnLaunch YES`.
/// Arguments aren't persisted, so they only affect that launch.
enum LaunchOptions {
    /// Keep secrets in memory instead of the Keychain, so a test run never touches (or prompts for) the
    /// user's real keys. Seed secrets with `SPARK_SECRET_*` environment variables (see `Keychain`).
    /// Also on whenever XCTest is loaded.
    static let ephemeralSecrets = UserDefaults.standard.bool(forKey: "SparkEphemeralSecrets")
        || NSClassFromString("XCTestCase") != nil

    /// Keep chat history in memory instead of Application Support, so a test run neither reads nor writes the
    /// user's saved chats (and never remembers which chats were open). Also on whenever XCTest is loaded.
    static let ephemeralHistory = UserDefaults.standard.bool(forKey: "SparkEphemeralHistory")
        || NSClassFromString("XCTestCase") != nil

    /// Show the chat panel as soon as the app launches (scripts can't press the global hotkey).
    static let showPanelOnLaunch = UserDefaults.standard.bool(forKey: "SparkShowPanelOnLaunch")
}
