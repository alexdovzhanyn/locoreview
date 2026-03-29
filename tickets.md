# review.nvim — Implementation Tickets

## Title

review.nvim v1 / v1.5 — Local Code Review Plugin for Neovim

## Goal

Implement a local-first Neovim plugin for capturing, browsing, and resolving structured code review comments stored in a human-readable markdown file inside a git repository.

## Assumptions / Open Questions

- Plugin targets Neovim (not Vim); nvim-lua APIs are available
- `plenary.nvim` is an allowed dependency for async/path helpers if needed
- No external test runner assumed; busted is the standard for Neovim Lua plugins
- `vim.ui.input` is the prompt mechanism unless a richer flow is needed
- Visual mode range capture uses `'<` / `'>` marks
- Atomic file writes are a best-effort concern; full rewrite per save is acceptable
- Picker fallback order: Telescope → fzf-lua → snacks → `vim.ui.select`
- Author defaults to `nil` if `default_author` not configured and cannot be inferred from git

---

## Ticket List

---

### T-01 — Repo Scaffold [DONE]

**Scope:** Create the repository directory structure, placeholder files, and plugin entrypoint guard.

**Files affected:**
- `plugin/review.lua`
- `lua/review/init.lua`
- `lua/review/config.lua`
- `lua/review/types.lua`
- `lua/review/util.lua`
- `README.md` (stub)
- `LICENSE`

**Acceptance criteria:**
- Directory layout matches schema section 3 exactly
- `plugin/review.lua` guards against double-load with a module-loaded flag
- `lua/review/init.lua` exposes a `setup(opts)` function that merges user opts with defaults and returns without error
- `lua/review/types.lua` defines status enum (`open`, `fixed`, `blocked`, `wontfix`) and severity enum (`low`, `medium`, `high`) as Lua tables
- `lua/review/util.lua` contains at least one generic helper (e.g. `trim`, `uuid`-free ID padding)
- Running `:lua require("review").setup({})` in a bare Neovim produces no errors

**Validation:**
- Manual: open Neovim, source the plugin, run `:lua require("review").setup({})`, confirm no errors
- Manual: source twice, confirm no double-init side effects

**Dependencies:** none

---

### T-02 — Config Module [DONE]

**Scope:** Implement the config module with defaults, validation, and normalized output.

**Files affected:**
- `lua/review/config.lua`
- `lua/review/init.lua` (wire up)

**Acceptance criteria:**
- Default values match schema section 4 exactly
- `review_file` defaults to `"review.md"`
- `keymaps` defaults to `true`
- `default_severity` defaults to `"medium"`
- `diffview.enabled` defaults to `true`
- `signs.enabled` defaults to `true`, `signs.priority` defaults to `20`
- `picker.enabled` defaults to `true`, `picker.backend` defaults to `"auto"`
- `diff_only` defaults to `false`
- `agent.enabled` defaults to `false`, `agent.cmd` defaults to `"agent"`, `agent.open_in_split` defaults to `true`
- Invalid `default_severity` value produces a `vim.notify` error and aborts setup
- Invalid `picker.backend` value produces a `vim.notify` error and aborts setup
- `config.get()` returns the normalized merged table

**Validation:**
- Unit: call `config.normalize({})` and assert all defaults present
- Unit: call with invalid severity, assert error returned
- Manual: `require("review").setup({ default_severity = "critical" })` shows notify error

**Dependencies:** T-01

---

### T-03 — Filesystem Helpers [DONE]

**Scope:** Implement `fs.lua` with repo-root detection, file existence, read/write helpers.

**Files affected:**
- `lua/review/fs.lua`

**Acceptance criteria:**
- `fs.repo_root()` returns absolute path string or `nil`
- `fs.review_file_path()` combines repo root and configured `review_file` into an absolute path
- `fs.exists(path)` returns boolean
- `fs.read(path)` returns file content string or `nil`
- `fs.write(path, content)` writes content atomically (write-then-rename or direct) and returns `true` on success
- `fs.ensure_file(path, initial_content)` creates file with header if missing, no-ops if present

**Validation:**
- Unit: `fs.exists` on a known path and a nonexistent path
- Unit: `fs.write` then `fs.read` round-trip returns same content
- Manual: call `fs.ensure_file` twice, confirm file not overwritten on second call

**Dependencies:** T-01

---

### T-04 — Git Helpers [DONE]

**Scope:** Implement `git.lua` for repo root resolution and base branch detection.

**Files affected:**
- `lua/review/git.lua`

**Acceptance criteria:**
- `git.repo_root()` uses `git rev-parse --show-toplevel`, falls back to cwd
- `git.base_branch(config)` resolves in order: config value → upstream default → `origin/main` → `origin/master`
- `git.changed_lines(file, base_branch)` returns a list of changed line ranges `{start, end}` for the given file vs base
- `git.is_line_changed(file, line, base_branch)` returns boolean
- All git calls use `vim.fn.system` or `io.popen`; errors surface via return value, not exceptions

**Validation:**
- Manual: run inside a git repo, confirm `git.repo_root()` returns correct path
- Manual: run outside a git repo, confirm fallback to cwd without crash
- Manual: on a modified file, confirm `git.is_line_changed` returns true for changed lines

**Dependencies:** T-01

---

### T-05 — Types and Data Model [DONE]

**Scope:** Finalize `types.lua` with the canonical `ReviewItem` shape and all enums.

**Files affected:**
- `lua/review/types.lua`

**Acceptance criteria:**
- `types.STATUS` table contains exactly `open`, `fixed`, `blocked`, `wontfix`
- `types.SEVERITY` table contains exactly `low`, `medium`, `high`
- `types.VALID_TRANSITIONS` table encodes allowed status transitions from schema section 5
- `types.new_item(fields)` returns a table conforming to `ReviewItem` with all required fields validated
- `types.is_valid_transition(from, to)` returns boolean

**Validation:**
- Unit: `types.is_valid_transition("open", "fixed")` → true
- Unit: `types.is_valid_transition("fixed", "blocked")` → false
- Unit: `types.new_item` with missing required field returns error

**Dependencies:** T-01

---

### T-06 — Parser [DONE]

**Scope:** Implement `parser.lua` to parse the canonical markdown review file into a list of `ReviewItem` tables.

**Files affected:**
- `lua/review/parser.lua`
- `tests/parser_spec.lua`
- `tests/fixtures/review_basic.md`
- `tests/fixtures/review_multiline.md`
- `tests/fixtures/review_mixed_status.md`

**Acceptance criteria:**
- Parses `# Review Comments` header
- Parses each `## RV-XXXX` block into a `ReviewItem` table
- Extracts all scalar fields: `file`, `line`, `end_line`, `severity`, `status`, `author`, `created_at`, `updated_at`
- Extracts multiline `issue:` block content correctly (no leading/trailing blank lines)
- Extracts multiline `requested_change:` block content correctly
- Returns actionable error for: duplicate IDs, unknown status, unknown severity, missing required fields (`file`, `line`, `issue`, `status`, `severity`)
- Tolerates trailing whitespace on field lines
- Tolerates blank `end_line:` and `author:` values (returns `nil` for those fields)
- Ignores extra blank lines between items

**Validation:**
- Unit: parse `review_basic.md` fixture, assert item count and field values
- Unit: parse `review_multiline.md`, assert multiline issue content preserved exactly
- Unit: parse `review_mixed_status.md`, assert statuses parsed correctly
- Unit: parse file with duplicate IDs, assert error returned
- Unit: parse file with missing `file:` field, assert error returned

**Dependencies:** T-05, T-03

---

### T-07 — Formatter [DONE]

**Scope:** Implement `formatter.lua` to serialize a list of `ReviewItem` tables back to canonical markdown.

**Files affected:**
- `lua/review/formatter.lua`
- `tests/parser_spec.lua` (round-trip tests)

**Acceptance criteria:**
- Output begins with `# Review Comments\n\n`
- Items sorted by numeric ID ascending
- Each item rendered in fixed field order matching schema section 6
- Blank optional values (`end_line`, `author`) emitted as `field:\n` (no trailing space)
- `issue:` and `requested_change:` emitted as block fields with content on following lines
- Items separated by `---\n`
- File ends with a final newline
- Round-trip: parse → format → parse produces identical item list

**Validation:**
- Unit: format single item, compare output string to expected fixture
- Unit: format items out of ID order, assert output is sorted
- Unit: parse → format → parse round-trip produces identical item count and field values

**Dependencies:** T-06

---

### T-08 — Store [DONE]

**Scope:** Implement `store.lua` for loading, saving, inserting, updating, deleting, and transitioning items.

**Files affected:**
- `lua/review/store.lua`
- `tests/store_spec.lua`

**Acceptance criteria:**
- `store.load(path)` reads and parses the review file, returns item list or error
- `store.save(path, items)` formats and writes item list to file
- `store.next_id(items)` returns next unused `RV-XXXX` string, zero-padded to 4 digits
- `store.insert(items, item)` appends item with generated ID and timestamps, returns updated list
- `store.update(items, id, fields)` merges fields into item with matching ID, updates `updated_at`, returns updated list or error if ID missing
- `store.delete(items, id)` removes item by ID, returns updated list or error if ID missing
- `store.transition(items, id, new_status)` calls `types.is_valid_transition`, updates status and `updated_at`, returns updated list or error on invalid transition
- `store.find_by_location(items, file, line)` returns first open item matching file and line

**Validation:**
- Unit: `store.next_id` on empty list returns `"RV-0001"`
- Unit: `store.next_id` with existing `RV-0003` returns `"RV-0004"`
- Unit: insert, then load/save round-trip, assert item present with correct ID
- Unit: transition `open → fixed` succeeds; `fixed → blocked` returns error
- Unit: delete nonexistent ID returns error

**Dependencies:** T-06, T-07, T-05

---

### T-09 — Commands Layer (v1 core) [DONE]

**Scope:** Implement `commands.lua` with v1 command handlers and register them in `plugin/review.lua`.

**Files affected:**
- `lua/review/commands.lua`
- `plugin/review.lua`
- `lua/review/init.lua`

**Acceptance criteria:**
- Commands registered: `ReviewOpen`, `ReviewAdd`, `ReviewAddRange`, `ReviewList`, `ReviewNext`, `ReviewPrev`, `ReviewMarkFixed`, `ReviewReopen`
- Each command handler calls appropriate store/fs/ui functions
- `ReviewOpen` creates the review file if missing (using `fs.ensure_file`), opens it in a buffer
- `ReviewAdd` resolves repo-relative file and current line, prompts for issue/requested_change/severity, inserts item, saves
- `ReviewAddRange` captures `'<` and `'>` marks for `line`/`end_line`, follows normal add flow
- `ReviewMarkFixed` and `ReviewReopen` use `store.transition`; error if item not found
- `ReviewNext` and `ReviewPrev` jump to next/previous open item by file/line across all open items
- All commands use `vim.notify` with level `ERROR` on failure; never silently fail

**Validation:**
- Manual: `:ReviewOpen` on fresh repo creates `review.md` and opens it
- Manual: `:ReviewAdd` prompts, fills, and writes item to file
- Manual: `:ReviewMarkFixed` on a line with an open item transitions it
- Manual: `:ReviewMarkFixed` on a line with no item shows an error notification

**Dependencies:** T-08, T-03, T-04

---

### T-10 — UI Prompts [DONE]

**Scope:** Implement `ui.lua` for prompting and notifications.

**Files affected:**
- `lua/review/ui.lua`

**Acceptance criteria:**
- `ui.prompt_issue(callback)` opens `vim.ui.input` for issue text
- `ui.prompt_requested_change(callback)` opens `vim.ui.input` for requested change text
- `ui.prompt_severity(default, callback)` opens `vim.ui.select` with `low`/`medium`/`high` options, default pre-selected
- `ui.notify(msg, level)` wraps `vim.notify` with plugin prefix `[review]`
- All prompts call callback with `nil` if user cancels (empty input or abort)
- Cancellation at any prompt step aborts the add flow cleanly with no partial write

**Validation:**
- Manual: `:ReviewAdd`, cancel at issue prompt → no file change
- Manual: `:ReviewAdd`, cancel at severity prompt → no file change
- Manual: `:ReviewAdd`, complete all prompts → item written to file

**Dependencies:** T-01

---

### T-11 — Quickfix Integration [DONE]

**Scope:** Implement `qf.lua` to populate and refresh the quickfix list from review items.

**Files affected:**
- `lua/review/qf.lua`
- `lua/review/commands.lua` (wire `:ReviewList`)
- `tests/qf_spec.lua`

**Acceptance criteria:**
- `qf.populate(items, filter)` calls `vim.fn.setqflist` with entries for all items matching filter
- Default filter for `:ReviewList` is `status == "open"`
- Each quickfix entry contains `filename` (absolute path), `lnum`, `end_lnum` when set, `text` formatted as `[RV-XXXX][severity][status] issue preview`
- Issue preview truncated to ~80 chars
- `qf.refresh()` reloads file from disk and repopulates without changing window focus
- `:ReviewList` opens quickfix window after populating

**Validation:**
- Unit: `qf.populate` with two items returns correct entry count and text format
- Manual: `:ReviewList` with 3 open items opens quickfix with 3 entries
- Manual: after `:ReviewMarkFixed`, `:ReviewList` shows one fewer entry

**Dependencies:** T-08, T-09

---

### T-12 — Default Keymaps [DONE]

**Scope:** Implement `keymaps.lua` and register v1 default keymaps conditionally.

**Files affected:**
- `lua/review/keymaps.lua`
- `lua/review/init.lua` (call after setup)

**Acceptance criteria:**
- Keymaps only registered when `config.keymaps == true` or `config.keymaps` is a table
- When `config.keymaps == false`, no keymaps registered
- When `config.keymaps` is a table, user-supplied mappings override defaults (merge, not replace)
- All v1 default keymaps from schema section 8 registered correctly
- Keymaps use `vim.keymap.set` with `noremap = true` and `silent = true`
- `<leader>ro` → `:ReviewOpen<CR>`
- `<leader>ra` → `:ReviewAdd<CR>`
- `<leader>rA` → `:ReviewAddRange<CR>`
- `<leader>rl` → `:ReviewList<CR>`
- `<leader>rn` → `:ReviewNext<CR>`
- `<leader>rp` → `:ReviewPrev<CR>`
- `<leader>rf` → `:ReviewMarkFixed<CR>`
- `<leader>rr` → `:ReviewReopen<CR>`
- `<leader>rd` → `:ReviewDiff<CR>`
- `<leader>rh` → `:ReviewFileHistory<CR>`
- `<leader>rx` → `:ReviewFix<CR>`

**Validation:**
- Manual: `setup({ keymaps = true })`, confirm `<leader>ra` triggers ReviewAdd
- Manual: `setup({ keymaps = false })`, confirm `<leader>ra` does nothing
- Manual: `setup({ keymaps = { add = "<leader>ca" } })`, confirm custom key works

**Dependencies:** T-09

---

### T-13 — v1.5 Status Commands (blocked / wontfix) [DONE]

**Scope:** Add `:ReviewMarkBlocked` and `:ReviewMarkWontfix` commands.

**Files affected:**
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `:ReviewMarkBlocked` transitions targeted item `open → blocked` via `store.transition`
- `:ReviewMarkWontfix` transitions targeted item `open → wontfix` via `store.transition`
- Both commands surface errors via `ui.notify` when item not found or transition invalid
- Both commands save file and trigger signs/quickfix refresh after successful transition

**Validation:**
- Manual: `:ReviewMarkBlocked` on open item → status changes to `blocked` in file
- Manual: `:ReviewMarkBlocked` on fixed item → error notification shown

**Dependencies:** T-08, T-09, T-11

---

### T-14 — Edit and Delete Commands [DONE]

**Scope:** Implement `:ReviewEdit` and `:ReviewDelete` commands.

**Files affected:**
- `lua/review/commands.lua`
- `lua/review/ui.lua` (edit prompts)
- `plugin/review.lua`

**Acceptance criteria:**
- `:ReviewEdit` finds item by current file/line, prompts to re-enter issue, requested_change, and severity with current values pre-filled, calls `store.update`, saves
- Pre-filling uses `vim.ui.input` `default` parameter where supported
- `:ReviewDelete` finds item by current file/line, asks for confirmation via `vim.ui.select` ("Delete?" yes/no), calls `store.delete`, saves
- Both commands refresh signs and quickfix after mutation
- `:ReviewEdit` and `:ReviewDelete` surface `ui.notify` errors when item not found

**Validation:**
- Manual: `:ReviewEdit` on existing item → prompts appear with current values, updated item written to file
- Manual: `:ReviewEdit` on line with no item → error notification
- Manual: `:ReviewDelete` confirm yes → item removed from file
- Manual: `:ReviewDelete` confirm no → file unchanged

**Dependencies:** T-08, T-09, T-10

---

### T-15 — Signs and Extmarks [DONE]

**Scope:** Implement `signs.lua` to place gutter signs and optional virtual text for open items.

**Files affected:**
- `lua/review/signs.lua`
- `lua/review/commands.lua` (wire refresh after mutations)
- `lua/review/init.lua` (initialize signs namespace)

**Acceptance criteria:**
- `signs.setup()` defines `ReviewOpenSign` and `ReviewBlockedSign` via `vim.fn.sign_define`
- `signs.refresh(items)` places signs on all currently-open buffers for matching `open` and `blocked` items
- Signs only placed for `open` and `blocked` items; `fixed` and `wontfix` items get no sign
- One sign per line even with multiple items on same line
- `signs.clear()` removes all signs placed by this plugin
- `signs.toggle()` flips enabled state for current session
- Signs disabled when `config.signs.enabled == false`
- Optional virtual text preview (`"review: <issue truncated>"`) controlled by a sub-option, default off

**Validation:**
- Manual: add review item, open its file → gutter sign appears on correct line
- Manual: `:ReviewMarkFixed` → sign disappears after refresh
- Manual: `setup({ signs = { enabled = false } })` → no signs placed
- Manual: `:ReviewToggleSigns` → signs disappear, run again → signs reappear

**Dependencies:** T-08, T-09

---

### T-16 — Refresh Command [DONE]

**Scope:** Implement `:ReviewRefresh` to reload file, update signs, and update quickfix.

**Files affected:**
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `:ReviewRefresh` reloads items from disk via `store.load`
- Calls `signs.refresh(items)` and `qf.refresh()` without changing window focus
- Emits `ui.notify` info message on completion
- Handles parse errors gracefully (notify, do not crash)

**Validation:**
- Manual: externally edit `review.md` to add an item, run `:ReviewRefresh` → new sign appears and quickfix updates

**Dependencies:** T-11, T-15

---

### T-17 — Diffview Integration [DONE]

**Scope:** Implement `diffview.lua` wrapper and `:ReviewDiff` / `:ReviewFileHistory` commands.

**Files affected:**
- `lua/review/diffview.lua`
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `diffview.is_available()` returns true only if `diffview` plugin is loadable
- `:ReviewDiff` calls `DiffviewOpen <base_branch>...HEAD` when diffview available
- `:ReviewFileHistory` calls `DiffviewFileHistory %` for current file when available
- When diffview not available, both commands emit a clear `vim.notify` error and do nothing else
- Integration only active when `config.diffview.enabled == true`

**Validation:**
- Manual (diffview present): `:ReviewDiff` opens diff view
- Manual (diffview absent): `:ReviewDiff` shows error notification, no crash
- Manual: `setup({ diffview = { enabled = false } })`, `:ReviewDiff` shows disabled notification

**Dependencies:** T-09, T-04

---

### T-18 — Picker Integration [DONE]

**Scope:** Implement `picker.lua` with Telescope / fzf-lua / snacks / `vim.ui.select` backends and `:ReviewPicker` command.

**Files affected:**
- `lua/review/picker.lua`
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `picker.open(items)` selects backend based on `config.picker.backend`
- `auto` mode tries Telescope, then fzf-lua, then snacks, then falls back to `vim.ui.select`
- Each picker entry shows: ID, file, line, severity, status, issue preview
- Selecting an entry jumps to the item's file and line
- When `config.picker.enabled == false`, `:ReviewPicker` emits a notify and exits
- Graceful notify when no backend is found (no crash)

**Validation:**
- Manual (Telescope present, `backend = "auto"`): `:ReviewPicker` opens Telescope picker
- Manual (no picker plugins): `:ReviewPicker` falls back to `vim.ui.select` without error
- Manual: selecting item in picker jumps to correct file and line

**Dependencies:** T-08, T-09

---

### T-19 — Agent Integration [DONE]

**Scope:** Implement `agent.lua` and `:ReviewFix` command.

**Files affected:**
- `lua/review/agent.lua`
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `agent.build_prompt(items, repo_root, review_file_path)` returns a string prompt summarizing open items
- `:ReviewFix` calls configured `agent.cmd` with the generated prompt
- When `agent.open_in_split == true`, opens a terminal split with the command
- When `agent.open_in_split == false`, runs command silently and notifies on completion
- `agent.cmd` can be a string or a function returning a string
- When `config.agent.enabled == false`, `:ReviewFix` emits a notify and does nothing

**Validation:**
- Manual: `setup({ agent = { enabled = true, cmd = "echo", open_in_split = true } })`, `:ReviewFix` opens terminal split with echo output
- Manual: `agent.enabled = false` → `:ReviewFix` shows disabled notification

**Dependencies:** T-08, T-09

---

### T-20 — Diff-Only Add Command [DONE]

**Scope:** Implement `:ReviewAddDiff` command that restricts adding to changed lines only.

**Files affected:**
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `:ReviewAddDiff` checks `git.is_line_changed` for current file and line
- If line is not changed, emits `ui.notify` error and exits without prompting
- If line is changed, follows normal add flow identical to `:ReviewAdd`
- Works correctly even when `config.diff_only == false` (`:ReviewAddDiff` is always diff-restricted)
- When `config.diff_only == true`, `:ReviewAdd` also enforces diff-only behavior

**Validation:**
- Manual: cursor on unchanged line, `:ReviewAddDiff` → error notification, no prompt
- Manual: cursor on changed line, `:ReviewAddDiff` → normal add flow

**Dependencies:** T-09, T-04

---

### T-21 — v1.5 Keymaps [DONE]

**Scope:** Add v1.5 default keymaps to `keymaps.lua`.

**Files affected:**
- `lua/review/keymaps.lua`

**Acceptance criteria:**
- `<leader>re` → `:ReviewEdit<CR>`
- `<leader>rD` → `:ReviewDelete<CR>`
- `<leader>rb` → `:ReviewMarkBlocked<CR>`
- `<leader>rw` → `:ReviewMarkWontfix<CR>`
- `<leader>rR` → `:ReviewRefresh<CR>`
- `<leader>rk` → `:ReviewPicker<CR>`
- `<leader>rs` → `:ReviewToggleSigns<CR>`
- All subject to same `config.keymaps` gating as v1 keymaps

**Validation:**
- Manual: `<leader>re` triggers `:ReviewEdit`
- Manual: `<leader>rD` triggers `:ReviewDelete`

**Dependencies:** T-12, T-13, T-14, T-15, T-16, T-18

---

### T-22 — ListAll Command and Filtering [DONE]

**Scope:** Implement `:ReviewListAll` with optional status/severity/file filtering.

**Files affected:**
- `lua/review/qf.lua`
- `lua/review/commands.lua`
- `plugin/review.lua`

**Acceptance criteria:**
- `:ReviewListAll` populates quickfix with all items regardless of status
- Optional args accepted: `status=open`, `severity=high`, `file=lua/review/store.lua`
- Multiple filters are ANDed
- Opens quickfix window after populating
- `:ReviewListAll` with no args shows all items

**Validation:**
- Manual: `:ReviewListAll` shows both open and fixed items
- Manual: `:ReviewListAll status=open` shows only open items
- Manual: `:ReviewListAll severity=high` shows only high-severity items

**Dependencies:** T-11

---

### T-23 — Unit Tests [DONE]

**Scope:** Write busted unit tests for parser, store, formatter, and quickfix modules.

**Files affected:**
- `tests/parser_spec.lua`
- `tests/store_spec.lua`
- `tests/commands_spec.lua`
- `tests/qf_spec.lua`
- `tests/fixtures/review_basic.md`
- `tests/fixtures/review_multiline.md`
- `tests/fixtures/review_mixed_status.md`

**Acceptance criteria:**
- `parser_spec.lua` covers: canonical parse, multiline fields, duplicate IDs error, unknown status error, missing required field errors
- `store_spec.lua` covers: next_id, insert, update, delete, transition (valid and invalid), find_by_location
- `commands_spec.lua` covers: add from line (mocked prompt), add from range, mark fixed/reopen
- `qf_spec.lua` covers: entry format, open filter, all-items mode
- All fixtures match schema section 6 canonical format
- All tests pass with `busted` or `nvim --headless -l` test runner

**Validation:**
- CI: `busted tests/` exits 0

**Dependencies:** T-06, T-07, T-08, T-11

---

### T-24 — README [DONE]

**Scope:** Write the final README.md.

**Files affected:**
- `README.md`

**Acceptance criteria:**
- Contains: short purpose statement, installation example for lazy.nvim, minimal `setup()` example, commands table (all v1 + v1.5 commands), config table with types and defaults, sample review file block, optional integrations section (diffview/picker/agent), roadmap section for post-v1.5 deferred features
- Installation example matches schema section 21 lazy.nvim block exactly
- No hardcoded personal paths, usernames, or branch names

**Validation:**
- Manual: follow README install instructions on a clean Neovim config, plugin loads and `:ReviewOpen` works

**Dependencies:** T-21, T-22

---

### T-25 — Help Docs [DONE]

**Scope:** Write `doc/review.txt` with full Neovim help documentation.

**Files affected:**
- `doc/review.txt`

**Acceptance criteria:**
- Contains sections: overview, installation, configuration, commands, keymaps, review file format, integrations, troubleshooting
- Help tags defined: `*review.nvim*`, `*review-setup*`, `*review-commands*`, `*review-file-format*`
- `:help review.nvim` navigates to the plugin overview
- `:helptags doc/` generates tags without error

**Validation:**
- Manual: `:helptags doc/`, then `:help review-commands` opens correct section

**Dependencies:** T-21, T-22

---

### T-26 — Release Polish [DONE]

**Scope:** Final cleanup before public release.

**Files affected:**
- All files

**Acceptance criteria:**
- No hardcoded personal paths, branch names, or author strings anywhere in plugin source
- `plugin/review.lua` double-load guard confirmed working
- All `vim.notify` messages include `[review]` prefix
- `:ReviewDiff` and `:ReviewFix` behave correctly when their optional dependencies are absent
- `setup()` can be called with `{}` and all commands work with defaults
- Passes manual validation checklist from schema section 17:
  - fresh repo with missing review file
  - existing file with 10+ items
  - multiline issue text
  - item edit round-trip
  - signs refresh after file change
  - picker works or falls back
  - diffview absent
  - agent command absent

**Validation:**
- Manual: full checklist from schema section 17 passes
- Manual: install via lazy.nvim on a clean machine using README instructions

**Dependencies:** T-23, T-24, T-25

---

## Dependency Graph Summary

```
T-01 (scaffold)
 └─ T-02 (config)
 └─ T-03 (fs)
 └─ T-04 (git)
 └─ T-05 (types)
     └─ T-06 (parser)
         └─ T-07 (formatter)
             └─ T-08 (store)
                 └─ T-09 (commands v1 core)
                 │   └─ T-10 (ui prompts)  [also feeds T-09]
                 │   └─ T-11 (quickfix)
                 │   └─ T-12 (keymaps v1)
                 │   └─ T-13 (blocked/wontfix)
                 │   └─ T-14 (edit/delete)
                 │   └─ T-15 (signs)
                 │       └─ T-16 (refresh)
                 │   └─ T-17 (diffview)
                 │   └─ T-18 (picker)
                 │   └─ T-19 (agent)
                 │   └─ T-20 (diff-only add)
                 │   └─ T-21 (keymaps v1.5)
                 │   └─ T-22 (listall/filter)
                 └─ T-23 (tests)
                     └─ T-24 (README)
                     └─ T-25 (help docs)
                         └─ T-26 (release polish)
```
