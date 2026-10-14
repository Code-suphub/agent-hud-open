# Command line

## Overview

Launch options, read-only probes, adapter commands and the MCP server of the standalone application. The same switches work on `build/Agent HUD Open.app/Contents/MacOS/Agent HUD Open` (after `make build`), on `swift run AgentHUDOpen`, and through Launch Services as `open "build/Agent HUD Open.app" --args …`. Unknown switches are ignored; probes and adapter commands run before the application object exists and never show a window. Applications that embed the libraries document their own parameters.

## Launch and display

| Switch | Effect |
| --- | --- |
| `--demo` | Use the sample data (`DemoUsageProvider`, `DemoData`) instead of installed clients; see [The sample](#the-sample). Preferences live in the separate `app.agenthud.open.demo` defaults domain, no report cache is written, and no adapters are installed. A demo saved with rows the sample no longer has starts over from the sample's rows and keeps its other preferences. |
| `--lang zh\|en\|system` | Force the interface language for this launch (`zh`, `zh-hans` and `cn` select Simplified Chinese). The choice is saved to the preferences in use. |
| `--show-settings` | Open the settings window after start. |
| `--show-stats` | Open the statistics window after start. |
| `--open-panel` | Start with the notch panel expanded. |
| `--show-onboarding` | Show the first-launch window even when onboarding is complete. |
| `--reset-defaults` | Remove the application's stored preferences before starting. |
| `--snapshot <dir>` | Render every screen at 2× to PNG files in `<dir>` from sample data, then quit; only a debug build renders, and a release build says so and quits. `AGENTHUD_SNAPSHOT_PREFIX=<name>` limits rendering to snapshots whose name starts with the prefix, for example `settings-`. |
| `--demo-script <name\|file>` | Play a timed scenario in the demo, and turn the demo on. `showcase` is built in: two agents start work, Claude asks to run the tests and is answered, Claude replies, Claude's session window crosses nine tenths used, the panel opens and closes, Codex replies, then it starts over. Any other value is the path of a JSON file; see [Recording](#recording). |
| `--demo-clock <time>` | Start the demo at this moment instead of now, and turn the demo on: an ISO 8601 date and time such as `2026-10-12T09:41`, local unless it names an offset (`Z`, `+08:00`), seconds optional. The demo's time runs on from there, so its dates, hours and "today" are the same whenever it is run. With `--snapshot` the stills are rendered at that moment. A value that does not read as a time is logged and the wall clock stays. |
| `--record <file.mov>` | Record the main display's HUD, and nothing else on screen, to a ProRes 4444 movie with a transparent background. `--record-seconds <n>` finishes the file and quits after that long; without it the file is finished when the application quits. `--record-fps <n>` sets the frame rate (60). `--record-region <x,y,width,height>` records part of the display, in points from its top left. |

`make demo` runs `--demo --show-settings`; `make snapshot` runs `--snapshot build/snapshots` (override the directory with `SNAPSHOT_DIR=…`).

Only one Agent HUD runs at a time, whichever application built on these libraries it is. A launch while another copy runs shows an alert naming the application that runs and quits before it reads preferences, opens the ledger or touches a client's settings. The lock is `~/Library/Caches/app.agenthud/instance.lock`, released by the system when its holder quits or crashes; a lock that cannot be created lets the launch run. Snapshots, probes and adapter commands run beside the running copy, and so does `--demo`; a launch with `--reset-defaults` does not, since the preferences it removes may be in use.

## The sample

`--demo` shows one sample, the same one the iPhone and Watch apps show in their demo, so a Mac and a phone recorded side by side agree. It is shaped as the providers shape real data: quota windows that belong to an account, models as token consumers, sessions that name the model they spend on.

| Part | What it holds |
| --- | --- |
| Claude, account Personal on Max | Current session 12% used, resets in 1 h 12 min; Weekly limit · All models 79%, resets in 5 days; Weekly limit · Fable 60% |
| Codex, account Personal on Pro | Weekly limit 49%, resets in 6 days; GPT-5.3-Codex-Spark 5h limit 18% and weekly limit 24%; two earned resets |
| DeepSeek | Balance ¥8.85, ¥0.01239 spent in the last day |
| Sessions | `s1` Build the iOS dashboard (Fable 5.1, running), `s2` Review App Store sandbox support (gpt-6-astra, running), `s3` Refine settings and colors (Opus 5.5), `s4` Run the regression suite (gpt-6.1-sol), `s5` Update the documentation (Sonnet 5.5), `s6` Package the Mac release (Opus 5.5), `s7` Check the release scripts (gpt-6.1-sol), `s8` Review the API integration (deepseek-v4-pro), `s9` Draft the release notes (gpt-6.1-sol, a day ago) |
| Tokens | 15 million a day before cache reads for thirty days, across Fable 5.1, Opus 5.5, Sonnet 5.5, codex-auto-review, gpt-6.1-sol and deepseek-v4-flash |

The running demo adds a row and a reading for every other vendor the app has artwork for, so the HUD carries a full queue. A figure changed in `DemoData` is changed in the iPhone's `DemoFleet` too, and the other way round; `DemoDataTests` pins the figures both show.

## Recording

`--demo-script` and `--record` together give the same take every time: `--demo-script showcase --record ~/Movies/hud.mov --record-seconds 45`. Add `--demo-clock 2026-10-12T09:41` and the statistics window's dates and hours are the same too, whatever the hour of the take; the menu bar's own clock and a permission card's count of seconds waited stay on the wall clock.

A script changes what the demo's own sources report, and the HUD reacts as it does to real ones; nothing is drawn by the script. Its JSON has `steps`, each with `at` in seconds from the start and `do`:

| `do` | Fields | What happens |
| --- | --- | --- |
| `work` | `session` | A demo session, `s1` to `s9` (see [The sample](#the-sample)), starts running, so its mark is at work. |
| `rest` | `session` | It stops with nothing to say. |
| `reply` | `session`, optional `message` | Its turn ends, which raises the reply reminder; the message is the reply's last paragraph. |
| `ask` | `request` | One of the demo's permission requests arrives: `demo-tests` (the test run the iPhone's demo asks about), `demo-edit`, `demo-build`, `demo-ticket`, `demo-read`. |
| `answer` | `request` | The client takes it back, as when it was answered in the client's own window. One answered on the HUD stays answered. |
| `quota` | `agent`, `used` | A window now reads this percentage used, named by its key: `claude-session`, `claude-weekly`, `claude-weekly-fable`, `codex`, `codex:spark:primary`, `codex:spark:secondary`, or another vendor's row by its id (`cursor`). The quota alert follows the usual rule, so a window the forecast already warns about raises nothing new. |
| `panel` | `open` | The usage panel opens or closes on the display the pointer is on. |

Beside `steps`, `running` lists the sessions already at work when the script starts (none by default), `used` sets readings that differ from the demo's own, and `repeatAfter` is the pause in seconds before the script starts over; without it the script plays once.

The recording is drawn in the application from the HUD's own windows as they are being shown, animations in flight included, so it needs no screen recording permission and no other window can appear in it. The picture has the display's pixel size, or the region's, and premultiplied alpha. A whole 2056 × 1329 pt display at 60 frames a second writes about 14 MB a second.

Core Animation's software renderer draws the frames, and `--snapshot` stills too, where the window server draws the screen; along curved edges the two differ by fractions of a pixel. The software renderer also adds something the screen never shows: an outline with continuous corners on a shape too short for them, a capsule above all, gets a straight line along each short side that runs past the tips. A reply's pill beside a separated dock, a Simple panel on the top or bottom edge and a plan badge are such shapes. Neither a recording nor a still shows the line: a still is drawn with those outlines' corners circular, and a recording draws the few points where a line would be that way, everything else as it is being shown.

## Read-only probes

| Command | Output |
| --- | --- |
| `--probe` | Prints where Claude Code's engine, Codex's engine and home, DeepSeek Harness's home and Node.js are, the agents in the settings and one step of reading Claude Code's transcripts; then one real account refresh (48 h of history) and one report with how long each took, `Quota windows: n; sessions: n; live: n; billing accounts: n`, the plans and notice, the discovered rows, each window's share used and reset, sessions by client, DeepSeek Harness's sessions and tokens, each balance and its estimated cost, the five newest sessions with their tokens and the values the vendor catalog does not name. Exits 0, or prints the error and exits 1. It issues the same provider requests as the running application and nothing else, and keeps what it reads in memory: it writes nothing to the usage ledger, removes or imports no earlier version's files and remembers no account identity. No conversation text and no credential is printed. |
| `--probe-open-agents` | Indexes the last seven days of local OpenCode, Kimi and Pi sessions and prints, per client, the session count, running count, distinct usage events, In / Out / Cache totals and the read status. No network requests, no transcript text, no credentials in the output. |
| `AGENT_HUD_PROBE_ADDITIONAL=1 swift test --filter AdditionalProviderTests/testInstalledSourcesReadOnlyProbe` | Read-only probe of the installed Antigravity, Cursor and Grok sources from the test suite; the test is skipped unless the variable is set. |
| `AGENT_HUD_PROBE_ANTIGRAVITY=1 swift test --filter AntigravityPermissionsTests/testInstalledAntigravityPermissionsReadOnlyProbe` | Reads Antigravity's native waiting permissions and prints their count. Sends no approval or rejection and prints no command, conversation text or credential. |

## Adapter commands

| Command | Effect |
| --- | --- |
| `--install-pi-observer` | Write or update the Agent HUD extension `extensions/agent-hud.ts` under the Pi directory (`PI_CODING_AGENT_DIR`, default `~/.pi/agent`), then exit. Existing Pi sessions need `/reload` once. A same-named file that is not Agent HUD's is left alone and the command fails. |
| `--attention-hook claude` | The handler Claude Code invokes for a notification: reads the payload from standard input, records the session's pending request, prints `{}` and exits 0 even when recording fails. |
| `--session-origin-hook codex\|claude` | Records the native session ID, host type, observation time and optional terminal destination at session start or prompt submission. Prints `{}` and exits 0 even when recording fails; it produces no completion, starts no interface and queries no account. |
| `--permission-hook claude\|codex\|qoder\|qoderCN\|qoderWork\|codebuddy\|workbuddy\|zcode\|qwen` | The handler the client invokes when it is about to ask whether a tool may run: forwards the payload to the running application and waits, prints back the decision the user gave, and exits 0. Codex CLI and Desktop share the `codex` handler. Prints nothing — leaving the client's own permission flow untouched — when the application is not running, the payload cannot be read, nobody answers before the client stops waiting, or Claude Code's session record shows the call was answered in Claude Code itself. It never initializes the interface or queries an account. |
| `--install-completion-hook antigravity\|cursor\|copilot\|codebuddy\|qwen` | Point the client's stop hook at this executable, adding it when it is missing; an Agent HUD handler already there, whichever copy wrote it, is taken over. Other hooks in the client's configuration are preserved. Fails, changing nothing, when this executable runs from a disk image or a translocated copy. |
| `--completion-hook antigravity\|cursor\|copilot\|codebuddy\|qwen` | The handler the clients invoke: reads the hook payload from standard input, stores a completion record when the payload describes a successful stop, prints `{"decision":"stop"}` for Antigravity or `{}` for the others, and exits 0 even when recording fails. It never initializes the interface or queries an account. |
| `--mcp` | Agent HUD's MCP server on standard input and output, one JSON-RPC message a line each way; see [MCP server](#mcp-server). A client starts it and keeps it running, and it exits 0 when its input ends. It must be the only argument. It starts no interface, takes no instance lock, queries no account and never starts the application. |

Normal start-up already runs `SessionObservers.configure(executable:enabled:)` for installed clients with the `clientHooks` setting — pointing every Agent HUD handler at this executable when it is on, whichever copy wrote it, and removing them all when it is off — which also installs Claude Code's notification hook and each supported client's approval hook ([approvals](hud.md#approvals)). Moving the application, or starting another build of it, therefore moves the hooks at the next start. Codex requires the user to review and trust a new or changed hook through `/hooks` before it runs; the HUD does not change hook trust or enable disabled hooks. The install commands exist for a first setup without launching the application ([notification hook](session-lifecycle.md#notification-hook), [completion hooks](session-lifecycle.md#completion-hooks)).

## MCP server

`--mcp` is how an AI agent reads the hover panel and proposes a layout for it ([panel layout](hud.md#panel-layout)). The client that starts the process keeps it for as long as it wants the tools. The process answers the protocol itself, in revisions 2024-11-05 to 2025-11-25, which open with a handshake, and 2026-07-28, which has none, and hands each tool call to the running application over `mcp.sock` in the data directory: one connection a call, at most 10 s for the answer. With no application running a call comes back as an error result that says "Agent HUD is not running. Open Agent HUD and try again." A `--demo` launch serves no calls and leaves the socket to the real copy.

| Tool | Effect |
| --- | --- |
| `get_panel` | Returns the panel as JSON and changes nothing: `revision`, `unsaved`, `hasPrevious`, the `layout` in effect, each section with whether the layout shows it and whether Settings has it on, and every block the panel has, the shown ones first in the panel's order, with its `key`, `kind` (`quota` or `billing`), name, `widget`, `measure`, the `widgets` and `measures` it accepts, and the latest readings of its rows or balances. A row's name is the window's as the panel writes it, in the application's language; keys, notes and refusals are the same in both. It takes no arguments. |
| `set_panel_layout` | Proposes a layout as [it is stored](hud.md#interfaces-and-configuration): `blocks`, `order`, `sections` and `hiddenSections`, the whole layout wanted, with anything left out at its default. What the layout `get_panel` returned holds for a block or a row that is away can be sent back as it is. `from` set to `default` or `previous` proposes the default view or the layout saved before the current one instead. With `revision`, the call is refused when the layout has changed, or Agent HUD has restarted, since the `get_panel` that returned it. The proposal is drawn at once as an unsaved draft, kept as what it changes; one that draws what the saved layout draws clears the draft. Returns the panel as `get_panel` does, with a `note`. |
| `discard_panel_draft` | Drops the draft, so the panel shows the saved layout, and returns the panel. It takes no arguments. |

No tool saves: a person keeps a draft with Save in the panel. A proposal the panel cannot do as asked changes nothing and is refused whole, with every reason: an argument or a block property it does not have, a value of the wrong type, a widget, measure or section name it does not know, a block or row key the panel does not have now, a widget the block's kind does not accept, a measure its widget does not offer, `from` beside a layout, or `previous` while there is none. A key the layout in effect or the saved layout already holds for a block or a row that is away is no such reason, as long as what is held for an away block comes back unchanged: the panel has nothing to weigh a change to it against. The two other tools refuse any argument. A result is one block of JSON text and a refusal an error result in English sentences; a request or a reply is at most 1 MiB.

Agent HUD does not register the server with any client yet. A person adds it to a client by hand, as a stdio server whose command is the application's executable, by its full path, with `--mcp`. From this repository after `make build`:

```sh
claude mcp add agent-hud -- "$PWD/build/Agent HUD Open.app/Contents/MacOS/Agent HUD Open" --mcp
codex mcp add agent-hud -- "$PWD/build/Agent HUD Open.app/Contents/MacOS/Agent HUD Open" --mcp
```

`agent-hud` is the name the client lists the server under, and everything after `--` is the command. Claude Code's `--scope local|user|project` chooses where the entry is kept, `local` unless given. The entry is the client's own: Agent HUD neither writes nor updates it, so a moved application needs the command changed there. What a connected agent can read and change is in [data access](data-access.md#agent-tools).

## Environment

| Variable | Meaning |
| --- | --- |
| `SWIFT_SCRATCH_PATH` | Passed to `swift build` as `--scratch-path` by the build script |
| `AGENTHUD_SNAPSHOT_PREFIX` | Limits `--snapshot` to snapshots whose name starts with the prefix |
| `AGENT_HUD_PROBE_ADDITIONAL` | Enables the read-only probe test above |
| `AGENT_HUD_PROBE_ANTIGRAVITY` | Enables the read-only native permission probe above |
| Client home overrides and provider keys (`CODEX_HOME`, `DSH_HOME`, `PI_CODING_AGENT_DIR`, …) | Read from the process environment ([providers](providers.md)); a directory variable that is empty or only whitespace counts as unset. An application started from Finder or Launch Services inherits the login session's environment, not the exports of a terminal shell. |

## Code map

| Concept | Code |
| --- | --- |
| Switch parsing | `Sources/AgentHUDDesktop/App/LaunchOptions.swift` |
| One copy at a time | `Sources/AgentHUDCore/System/InstanceLock.swift`, `Sources/AgentHUDDesktop/App/SingleInstance.swift` |
| Adapter commands and hook handlers | `Sources/AgentHUDCore/Hooks/HookEntry.swift` |
| MCP server: the process, the protocol, the tool list and the calls to the application | `Sources/AgentHUDCore/MCP/MCPStdio.swift`, `MCPServer.swift`, `MCPProtocol.swift`, `MCPTools.swift`, `MCPToolCall.swift`, `MCPAppClient.swift` |
| What the tools do in the application, and the socket it answers on | `Sources/AgentHUDCore/PanelLayout/PanelTools.swift`, `Sources/AgentHUDCore/MCP/MCPAppChannel.swift` |
| Probes | `Sources/AgentHUDCore/Store/UsageProbe.swift`, `Sources/AgentHUDOpenApp/main.swift` |
| Demo script, stage and clock | `Sources/AgentHUDCore/Demo/DemoScript.swift`, `DemoStage.swift`, `DemoClock.swift`; `Sources/AgentHUDDesktop/App/DemoScriptRunner.swift` |
| HUD recording | `Sources/AgentHUDDesktop/Recording/HUDRecorder.swift` |
| Snapshot rendering | `Sources/AgentHUDDesktop/Debug/SnapshotRunner.swift` |
| Real-window interaction tests | `Tests/AgentHUDDesktopTests/Notch/Island/IslandAnimationTests.swift`, `IslandHoverTests.swift`, `Settings/AgentSettingsInteractionTests.swift` |
| Build script and targets | `scripts/build-app.sh`, `Makefile` |

## Related

[session-lifecycle.md](session-lifecycle.md) completion hooks and the observers · [providers.md](providers.md) per-client environment variables · [architecture.md](architecture.md) host integration · [hud.md](hud.md#panel-layout) the panel's layout · [data-access.md](data-access.md#agent-tools) what the MCP tools read and change
