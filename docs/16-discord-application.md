# Discord Application

The Discord integration shows a voice call on the island from the microphone alone, and — once the user presses **Connect** in the Integrations pane and approves KerNotch inside Discord — names the channel and leaves it. That connection goes through one Discord application: KerNotch's own. This document covers where its Client ID lives, how to change it, what forks should do, and what Discord's approval changes.

## Where the Client ID lives

| Step | Where |
|---|---|
| Source of truth | `KERNOTCH_DISCORD_CLIENT_ID` in `Config/Discord.xcconfig`, the base configuration of every `KerNotch` app build configuration |
| Build | `KerNotch/Info.plist` key `KerNotchDiscordClientID` = `$(KERNOTCH_DISCORD_CLIENT_ID)` |
| Runtime | `DiscordApplication.builtInClientID(infoDictionary:)`, read once at launch by `KerNotchApp` and handed to `DiscordIntegration` |

There is no settings field for another application, on purpose: the prompt a user approves must always name the application Discord reviewed. A build with no usable Client ID — an empty value, an unexpanded placeholder, or a SwiftPM build that has no `Info.plist` — hides the connection section and still shows calls from the microphone. `CompositionRootWiringTests` checks the whole chain.

A Client ID is a public identifier. Authorization uses PKCE with the application's **Public Client** switch on, so no client secret is needed, stored, or committed. Never add one to the repository.

## Changing it

Edit the one line in `Config/Discord.xcconfig` and ship a new build. Two consequences:

- **Users connect once more.** Stored tokens belong to the application that issued them (`FileDiscordCredentialStore` keeps one file per Client ID), so after the change each user presses Connect and approves again.
- **Approval does not move.** Discord approves an application, not a project. Switching to a different application means applying again.

## Forks and redistributed builds

Replace the value with the Client ID of a Discord application you own, or leave it empty. Shipping a fork with KerNotch's Client ID puts KerNotch's name on your users' approval prompt, and ties anything that build does to KerNotch's application.

## Discord's RPC approval

The scopes the connection needs — `rpc` (for `GET_CHANNEL`, `GET_GUILD`, `SELECT_VOICE_CHANNEL`) and `rpc.voice.read` (selected channel, mute state) — are available only to applications Discord has approved. Until then:

- The application's owner can connect.
- Up to 50 testers listed on the application in the Developer Portal can connect.
- Everyone else sees Discord fail to complete the connection. The Integrations pane says the connection may not be available for their account yet, and the microphone badge keeps working.

Before applying, have ready:

- The application's name and icon as users should see them in the approval prompt.
- A public website, privacy policy URL (`docs/PRIVACY.md` is its source) and terms of service URL.
- A description of the use: read the selected voice channel and mute state, and leave the channel on the user's request, all on the user's own Mac. No messages are read, no bot, no data leaves the device other than the OAuth2 token exchange.
- A note that KerNotch is open source and the Client ID is public in its repository, and a question of whether that raises any condition.
- The redirect URI registered on the application. The RPC flow does not send one, but the Developer Portal expects at least one; `http://localhost` is what the current application has.
