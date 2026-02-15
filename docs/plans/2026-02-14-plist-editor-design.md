# Plist Editor Design

## Summary

A structured plist viewer/editor presented as a sheet over the main window. All launch item types are viewable; only user agents are editable. Combines a form-based editor for common launchd keys with a read-only raw XML tab.

## Decisions

- **Scope**: View all types, edit user agents only
- **UX**: Structured form with named fields and type-appropriate controls
- **Presentation**: Sheet over main window (modal, one item at a time)
- **Save behavior**: Prompt to reload if the agent is currently running
- **Raw view**: Read-only pretty-printed XML tab alongside the form editor
- **Dependencies**: None — pure SwiftUI using system frameworks only

## Data Model

`PlistDocument` struct parses a plist file into structured fields:

| Field | Type | Notes |
|-------|------|-------|
| label | String | Read-only identity |
| program | String? | Single executable path |
| programArguments | [String] | Ordered list |
| runAtLoad | Bool | |
| keepAlive | Bool | |
| startInterval | Int? | Seconds between runs |
| startCalendarInterval | [CalendarInterval] | Hour/Minute/Weekday/Day/Month per entry |
| watchPaths | [String] | |
| environmentVariables | [String: String] | |
| workingDirectory | String? | |
| standardOutPath | String? | |
| standardErrorPath | String? | |
| throttleInterval | Int? | |
| nice | Int? | |
| processType | String? | |
| otherKeys | [String: Any] | Unmodeled keys preserved for round-trip |
| rawXML | String | For the Raw tab |

Round-trip safety: on save, structured fields are merged back with `otherKeys` so nothing is lost.

## View Architecture

### PlistEditorView (sheet)

- Title bar shows the item's display name
- `Picker` with "Editor" / "Raw" segments at top
- **Editor tab**: SwiftUI `Form` with grouped sections in a `ScrollView`
- **Raw tab**: Pretty-printed XML (`plutil -convert xml1`), read-only, text-selectable
- **Save button**: Only visible for user agents, enabled when dirty
- **Read-only mode**: All fields disabled for system agents/daemons

### Form Sections

1. **Identity** — Label (read-only text)
2. **Program** — ProgramArguments (ListEditorView), Program (text field)
3. **Schedule** — RunAtLoad (toggle), StartInterval (number field), StartCalendarInterval (CalendarIntervalEditorView), WatchPaths (ListEditorView)
4. **Environment** — EnvironmentVariables (KeyValueEditorView), WorkingDirectory (path field)
5. **I/O Paths** — StandardOutPath, StandardErrorPath (path fields)
6. **Other Keys** — DisclosureGroup, collapsed by default, read-only display

## Sub-components

### ListEditorView
- Reusable for any `[String]` field (ProgramArguments, WatchPaths)
- Ordered list with text fields, add/remove buttons, drag-to-reorder

### KeyValueEditorView
- For EnvironmentVariables
- Two-column table (key, value), add/remove rows

### CalendarIntervalEditorView
- Table of rows with optional Weekday (picker with day names), Hour (0-23), Minute (0-59)
- Add/remove rows

### OtherKeysView
- Collapsible DisclosureGroup for unmodeled keys
- Read-only key-value display, prevents data loss

## Interaction Flow

### Opening
- Double-click a row in the list → `.sheet` presents PlistEditorView
- PlistDocument initialized by reading the plist file at `item.path`

### Editing
- Dirty state tracked by comparing current document to original snapshot
- Save button enables only when changes exist
- Cmd+S keyboard shortcut

### Save Flow
1. Serialize PlistDocument back to dictionary (structured fields + otherKeys)
2. Write via PropertyListSerialization to the file path
3. Validate with `plutil -lint` after write
4. If agent is running, prompt: "Reload it now for changes to take effect?"
   - "Reload" → bootout + bootstrap
   - "Later" → dismiss
5. Refresh main list

### Error Handling
- File read failure → alert, dismiss sheet
- Save failure → inline error, keep sheet open
- Reload failure → show error (save already succeeded)

### Cancel
- If dirty → confirm discard
- If clean → dismiss
