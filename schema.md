
# review.nvim — v1 / v1.5 Schema Doc

## 1. Purpose

`review.nvim` is a Neovim plugin for capturing, browsing, and resolving lightweight code review comments inside a local git repository.

Primary goal:

* let a user attach structured review comments to files/lines in a repo
* store those comments in a human-readable repo-local file
* navigate and manage them from inside Neovim

Secondary goal:

* optionally integrate with diff tooling and external agent CLIs

Non-goals for v1/v1.5:

* remote PR platform sync
* threaded discussion model
* multi-user conflict resolution beyond simple file edits
* background daemons or servers
* database-backed persistence

TL;DR: local-first review comments for Neovim, with optional diff and agent integrations.

---

## 2. Release Scope

### v1

Core review workflow:

* setup/config API
* review file creation/opening
* add comment for current line
* add comment from visual selection
* parse/store structured review items
* stable item IDs
* list open comments into quickfix
* navigate next/previous open comment
* mark fixed
* reopen fixed comment
* optional default keymaps
* optional Diffview integration for diff/history
* optional external agent command

### v1.5

Usability + editor-native surfacing:

* edit existing review items
* delete review items
* blocked / wontfix statuses
* severity enum support in UI
* Telescope/fzf-style picker integration
* signs/extmarks for open comments in buffers
* diff-only comment mode for changed lines
* timestamps + author metadata
* requested change capture in add/edit flow
* filtering list by status/severity/file
* quickfix refresh command

TL;DR: v1 is workable and public; v1.5 makes it feel like a real Neovim-native review tool.

---

## 3. File Structure

```text
review.nvim/
  lua/
    review/
      init.lua
      config.lua
      commands.lua
      keymaps.lua
      fs.lua
      git.lua
      store.lua
      parser.lua
      formatter.lua
      ui.lua
      qf.lua
      signs.lua
      picker.lua
      agent.lua
      diffview.lua
      types.lua
      util.lua
  plugin/
    review.lua
  doc/
    review.txt
  tests/
    parser_spec.lua
    store_spec.lua
    commands_spec.lua
    qf_spec.lua
    fixtures/
      review_basic.md
      review_multiline.md
      review_mixed_status.md
  README.md
  LICENSE
```

### File responsibilities

#### `plugin/review.lua`

Thin runtime entrypoint.
Responsibilities:

* guard against double setup
* create commands
* optionally register default keymaps after setup

#### `lua/review/init.lua`

Public API.
Responsibilities:

* expose `setup(opts)`
* merge config
* initialize command layer
* initialize optional subsystems

#### `lua/review/config.lua`

Responsibilities:

* defaults
* option validation
* normalized config object

#### `lua/review/commands.lua`

Responsibilities:

* command registration
* command handlers calling lower-level modules

#### `lua/review/keymaps.lua`

Responsibilities:

* register optional default keymaps

#### `lua/review/fs.lua`

Responsibilities:

* repo root detection
* file existence checks
* file read/write helpers
* atomic write helper if implemented

#### `lua/review/git.lua`

Responsibilities:

* resolve repo root
* resolve default/base branch
* inspect changed lines/files
* diff-scoped helpers for v1.5

#### `lua/review/store.lua`

Responsibilities:

* load review file
* save review file
* insert/update/delete review items
* manage IDs
* status transitions

#### `lua/review/parser.lua`

Responsibilities:

* parse markdown-backed review file into typed Lua tables
* preserve stable field extraction
* support multiline fields safely

#### `lua/review/formatter.lua`

Responsibilities:

* serialize review items back to markdown format
* preserve deterministic ordering

#### `lua/review/ui.lua`

Responsibilities:

* prompt user for issue/requested change/severity
* display notifications
* open/edit item workflows

#### `lua/review/qf.lua`

Responsibilities:

* populate quickfix from items
* filter quickfix entries
* refresh quickfix list

#### `lua/review/signs.lua`

Responsibilities:

* define signs
* place/remove signs and extmarks for open items
* refresh visible buffers

#### `lua/review/picker.lua`

Responsibilities:

* optional Telescope/fzf-lua/snacks picker integration
* graceful fallback when picker plugin missing

#### `lua/review/agent.lua`

Responsibilities:

* build external agent prompt
* shell out to configurable CLI
* optional terminal split execution

#### `lua/review/diffview.lua`

Responsibilities:

* optional integration wrapper for Diffview commands

#### `lua/review/types.lua`

Responsibilities:

* canonical field names / status enums / severity enums

#### `lua/review/util.lua`

Responsibilities:

* tiny generic helpers only

TL;DR: keep parsing/storage/core logic isolated from UI and integrations.

---

## 4. Public API

```lua
require("review").setup({
  review_file = "review.md",
  base_branch = nil,
  keymaps = true,
  default_severity = "medium",
  default_author = nil,
  diffview = {
    enabled = true,
  },
  signs = {
    enabled = true,
    priority = 20,
  },
  picker = {
    enabled = true,
    backend = "auto",
  },
  diff_only = false,
  agent = {
    enabled = false,
    cmd = "agent",
    open_in_split = true,
  },
})
```

### Config contract

#### `review_file: string`

Repo-relative path to review file.
Default: `"review.md"`

#### `base_branch: string|nil`

Branch used for diff/history commands. If `nil`, resolve automatically.

#### `keymaps: boolean|table`

* `true`: register defaults
* `false`: register none
* `table`: user-supplied mapping overrides

#### `default_severity: "low"|"medium"|"high"`

Default severity for newly created comments.

#### `default_author: string|nil`

Optional default author string.

#### `diffview.enabled: boolean`

Enable Diffview integration commands if available.

#### `signs.enabled: boolean`

Enable gutter signs/extmarks for open comments.

#### `signs.priority: number`

Neovim sign priority.

#### `picker.enabled: boolean`

Enable picker integrations.

#### `picker.backend: "auto"|"telescope"|"fzf_lua"|"snacks"|"none"`

Picker backend selection.

#### `diff_only: boolean`

If true, add commands can optionally enforce changed-line-only review mode.

#### `agent.enabled: boolean`

Enable external agent command.

#### `agent.cmd: string|function`

Shell command or function returning command string.

#### `agent.open_in_split: boolean`

Open execution in terminal split.

TL;DR: keep the public API small and centered on paths, UI behavior, and optional integrations.

---

## 5. Core Data Model

Canonical in-memory item schema:

```lua
---@class ReviewItem
---@field id string
---@field file string
---@field line integer
---@field end_line integer|nil
---@field severity "low"|"medium"|"high"
---@field status "open"|"fixed"|"blocked"|"wontfix"
---@field issue string
---@field requested_change string
---@field author string|nil
---@field created_at string
---@field updated_at string
```

### Field notes

* `id`: stable unique identifier, format `RV-0001`
* `file`: repo-relative path
* `line`: start line
* `end_line`: optional for visual/range comments
* `severity`: severity enum
* `status`: workflow state
* `issue`: reviewer concern text
* `requested_change`: optional requested remediation
* `author`: optional reviewer identifier
* `created_at`: ISO-8601 UTC timestamp
* `updated_at`: ISO-8601 UTC timestamp

### Status transition rules

* `open -> fixed`
* `open -> blocked`
* `open -> wontfix`
* `fixed -> open`
* `blocked -> open`
* `wontfix -> open`

Disallowed:

* deleting via status transition
* invalid enum writes

TL;DR: one structured item model, stable IDs, small status machine.

---

## 6. On-Disk File Format

The plugin stores comments in a markdown file with deterministic machine-readable blocks.

### Canonical format

```md
# Review Comments

## RV-0001
file: lua/review/store.lua
line: 42
end_line:
severity: medium
status: open
author: peter
created_at: 2026-03-28T15:30:00Z
updated_at: 2026-03-28T15:30:00Z

issue:
This branch mixes parsing and persistence.

requested_change:
Split parsing into parser.lua and keep store.lua focused on mutation.

---

## RV-0002
file: lua/review/ui.lua
line: 18
end_line: 24
severity: low
status: fixed
author:
created_at: 2026-03-28T15:40:00Z
updated_at: 2026-03-28T16:10:00Z

issue:
The prompt text is too vague.

requested_change:
Ask for severity explicitly.

---
```

### Format rules

* top-level title required: `# Review Comments`
* each item begins with `## <ID>`
* scalar metadata fields appear in fixed order
* `issue:` and `requested_change:` are multiline block fields
* item separator is exactly `---`
* blank values allowed for `end_line` and `author`
* formatter rewrites file into canonical order

### Why this format

* easy to read/edit manually
* deterministic parsing
* diff-friendly in git
* no external dependency required for YAML/JSON parser

TL;DR: markdown shell, structured internals, deterministic serialization.

---

## 7. Commands

### v1 commands

#### `:ReviewOpen`

Open the review file, creating it if missing.

#### `:ReviewAdd`

Add a review item for the current cursor line.

#### `:ReviewAddRange`

Add a review item for visual selection start/end lines.

#### `:ReviewList`

Load review items and populate quickfix with open items.

#### `:ReviewNext`

Jump to the next open review item.

#### `:ReviewPrev`

Jump to the previous open review item.

#### `:ReviewMarkFixed`

Mark the targeted item as `fixed`.

#### `:ReviewReopen`

Reopen the targeted item by setting status to `open`.

#### `:ReviewDiff`

Open diff view against configured base branch.

#### `:ReviewFileHistory`

Open file history for current file.

#### `:ReviewFix`

Run external agent integration against open items.

### v1.5 commands

#### `:ReviewEdit`

Edit issue/requested_change/severity for selected item.

#### `:ReviewDelete`

Delete selected item.

#### `:ReviewMarkBlocked`

Mark selected item as `blocked`.

#### `:ReviewMarkWontfix`

Mark selected item as `wontfix`.

#### `:ReviewListAll`

Populate quickfix with all items, optionally filtered.

#### `:ReviewRefresh`

Refresh quickfix and signs/extmarks from disk.

#### `:ReviewPicker`

Open picker UI for review items.

#### `:ReviewToggleSigns`

Enable or disable signs for current session.

#### `:ReviewAddDiff`

Add a review item only if cursor is on a changed line.

TL;DR: v1 covers create/navigate/resolve; v1.5 adds edit/filter/surface ergonomics.

---

## 8. Keymaps

Default keymaps should be optional.

### v1 default keymaps

```text
<leader>ro  -> ReviewOpen
<leader>ra  -> ReviewAdd
<leader>rA  -> ReviewAddRange
<leader>rl  -> ReviewList
<leader>rn  -> ReviewNext
<leader>rp  -> ReviewPrev
<leader>rf  -> ReviewMarkFixed
<leader>rr  -> ReviewReopen
<leader>rd  -> ReviewDiff
<leader>rh  -> ReviewFileHistory
<leader>rx  -> ReviewFix
```

### v1.5 default keymaps

```text
<leader>re  -> ReviewEdit
<leader>rD  -> ReviewDelete
<leader>rb  -> ReviewMarkBlocked
<leader>rw  -> ReviewMarkWontfix
<leader>rR  -> ReviewRefresh
<leader>rk  -> ReviewPicker
<leader>rs  -> ReviewToggleSigns
```

TL;DR: provide sane defaults, but do not force them.

---

## 9. UX Flows

### Add review item

1. user runs `:ReviewAdd`
2. plugin resolves repo-relative file and current line
3. plugin prompts for issue
4. plugin prompts for requested change
5. plugin prompts for severity with default prefilled
6. plugin inserts new item with generated ID and timestamps
7. plugin writes file
8. plugin refreshes signs and quickfix if active

### Add range review item

1. user selects lines in visual mode
2. user runs `:ReviewAddRange`
3. plugin captures start/end line
4. rest follows normal add flow

### Mark fixed

1. user runs command on current file/line context or selected picker item
2. plugin finds matching item
3. plugin updates status and `updated_at`
4. plugin writes file
5. plugin refreshes signs and quickfix

### Quickfix listing

1. user runs `:ReviewList`
2. plugin parses file
3. plugin filters by `status = open`
4. plugin pushes entries into quickfix
5. user navigates using native quickfix motions

### Picker flow

1. user runs `:ReviewPicker`
2. plugin loads items
3. picker shows ID, file, line, severity, status, issue preview
4. on selection, jump to item or run action

TL;DR: all flows should be simple file mutation plus editor refresh.

---

## 10. Optional Integrations

### Diffview integration

Enabled if plugin is installed and config allows it.
Used for:

* `:ReviewDiff`
* `:ReviewFileHistory`

Behavior when missing:

* notify clearly
* core plugin continues functioning

### Picker integration

Supported backends in priority order when `auto`:

1. Telescope
2. fzf-lua
3. snacks picker
4. fallback to quickfix / `vim.ui.select`

### Agent integration

External shell command receives generated prompt pointing at repo and review file.
Requirements:

* completely optional
* configurable command string
* no hard dependency on one CLI

TL;DR: integrations should enhance workflow, not define it.

---

## 11. Signs / Extmarks (v1.5)

### Goals

* visually mark lines with open review items
* avoid noise for fixed items
* refresh cheaply on open buffers

### Sign behavior

* place signs only for `open` and optionally `blocked`
* no signs for `fixed` or `wontfix` by default
* one sign per line even if multiple items exist; extmark details can contain count

### Suggested sign definitions

* `ReviewOpenSign`
* `ReviewBlockedSign`

### Extmark behavior

* optional virtual text preview such as `review: branch too large`
* default off if too noisy

TL;DR: signs should surface unresolved comments without clutter.

---

## 12. Quickfix Schema

Quickfix entries should include:

* `filename`
* `lnum`
* `end_lnum` when available
* `text` formatted as `[RV-0001][medium][open] issue preview`
* `type` optionally derived from severity (`W` or `E` style if desired)

Example text:

```text
[RV-0003][high][open] Split parser from store logic
```

TL;DR: quickfix is the main native list UI and should carry enough context to work alone.

---

## 13. Parser Rules

Parser must:

* accept canonical formatter output
* tolerate trailing whitespace
* tolerate missing optional scalar values
* preserve multiline `issue` and `requested_change`
* reject malformed IDs or required fields with actionable errors
* ignore repeated blank lines where possible

Parser may assume:

* one header per file
* deterministic field order once file has been written by formatter

Error cases:

* duplicate IDs
* unknown status
* unknown severity
* missing file/line/issue/status/severity

TL;DR: parser should be strict enough to keep data sane, but not brittle about whitespace.

---

## 14. Formatter Rules

Formatter should:

* sort items by numeric ID ascending
* emit canonical field order always
* normalize blank optional values as empty scalars
* preserve final newline
* rewrite whole file from parsed model, not patch text in place

This full rewrite approach is acceptable because the file is expected to remain small.

TL;DR: prefer deterministic full serialization over fragile text patching.

---

## 15. Git Rules

### Repo root

Use `git rev-parse --show-toplevel`, fallback to cwd.

### Base branch

Resolution order:

1. configured `base_branch`
2. upstream default branch if resolvable
3. `origin/main`
4. `origin/master`

### Diff-only mode

For `ReviewAddDiff` or `diff_only = true` behavior:

* verify current file is changed against base branch
* verify current line intersects changed hunks
* reject with clear notification if not on changed line

TL;DR: git support should improve review relevance, not complicate core behavior.

---

## 16. Error Handling Policy

Use `vim.notify` with explicit messages.

Expected handled errors:

* no file path for current buffer
* review file parse failure
* not inside git repo
* item not found for status transition
* external dependency missing
* no changed line in diff-only mode

Do not silently fail.

TL;DR: explicit local errors are enough; no fancy error framework needed.

---

## 17. Testing Plan

### Unit tests

Cover:

* parse canonical file
* parse multiline fields
* add item
* edit item
* delete item
* mark fixed/reopen/blocked/wontfix
* ID generation
* formatter canonical output
* quickfix entry generation

### Integration-ish tests

Cover:

* create review file if missing
* add from current line
* add from visual range input abstraction
* diff-only validation helper

### Manual validation checklist

* fresh repo, file missing
* existing review file with 10+ items
* multiline issue text
* item edit roundtrip
* signs refresh after file change
* picker works or falls back cleanly
* Diffview absent
* agent command absent

TL;DR: parser/store/formatter correctness matters most; integrations can be lightly tested.

---

## 18. README Contents

README should include:

* short purpose statement
* screenshot or gif later if desired
* installation examples for lazy.nvim
* minimal setup example
* commands table
* config table
* sample review file
* optional integrations section
* roadmap section for post-v1.5

TL;DR: README should optimize for install + first successful use in under 2 minutes.

---

## 19. Help Doc Contents

`doc/review.txt` should include:

* overview
* installation
* configuration
* commands
* keymaps
* review file format
* integrations
* troubleshooting

Help tags to provide:

* `*review.nvim*`
* `*review-setup*`
* `*review-commands*`
* `*review-file-format*`

TL;DR: public Neovim plugins should ship proper `:help` docs, not just README text.

---

## 20. Concrete v1.5 Feature Decision

Recommended supported feature set for first public release:

### Ship now

* setup/config
* structured markdown file format
* add/open/list/next/prev
* mark fixed/reopen/blocked/wontfix
* edit/delete
* quickfix integration
* signs/extmarks
* timestamps + author
* optional Diffview integration
* optional external agent integration
* picker integration with graceful fallback
* diff-only add command

### Defer

* GitHub PR sync
* threaded comments
* multiple review files per repo
* comment replies
* background file watchers
* collaborative locking

TL;DR: ship one polished local-first workflow instead of chasing remote platform features.

---

## 21. Example Lazy.nvim Setup

```lua
{
  "yourname/review.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "sindrets/diffview.nvim", optional = true },
  },
  opts = {
    review_file = "review.md",
    default_severity = "medium",
    diffview = { enabled = true },
    signs = { enabled = true, priority = 20 },
    picker = { enabled = true, backend = "auto" },
    agent = {
      enabled = false,
      cmd = "agent",
      open_in_split = true,
    },
  },
}
```

TL;DR: public install should be one block, optional extras, no project-specific assumptions.

---

## 22. Build Order

### Phase 1

* repo scaffold
* setup/config
* file format decision
* parser + formatter + store

### Phase 2

* open/add/add-range/list
* mark fixed/reopen
* quickfix integration

### Phase 3

* blocked/wontfix/edit/delete
* signs/extmarks
* refresh command

### Phase 4

* Diffview wrapper
* picker backend wrapper
* agent command wrapper
* diff-only add

### Phase 5

* tests
* README
* help docs
* polish/release

TL;DR: data model first, UI second, integrations third, docs/tests last.

---

## 23. Release Criteria

Ready for public release when:

* install works via lazy.nvim
* help docs exist
* parser/store tests pass
* commands behave on missing dependencies gracefully
* file format is stable and documented
* no hardcoded personal paths or branch names remain

TL;DR: publish when the plugin is configurable, documented, and not tied to your machine or workflow.
