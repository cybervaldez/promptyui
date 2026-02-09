# Element Operation Dictionary

Shared reference for `/ux-review`, `/e2e`, and `/e2e-guard`. Classifies interactive elements discovered via `snapshot -i` into operation categories to prevent navigation testing from triggering data mutations.

**Problem:** `grep -oE '@e[0-9]+'` extracts only the ref, discarding the element's label. By click-time, we've lost all context about what the element does. A `button "Delete User" [ref=e5]` gets clicked just like `link "Dashboard" [ref=e2]`.

**Solution:** Classify element labels BEFORE extracting refs. Only click `[NAV]` and `[VIEW]` elements during navigation testing.

---

## Element Operation Categories

`snapshot -i` output format: `role "Label Text" [ref=e1]`

Both **role** and **label** are classification signals.

| Category | Tag | Safe to Auto-Click? | Keywords |
|----------|-----|---------------------|----------|
| **Navigation** | `[NAV]` | YES | home, dashboard, settings, view, details, back, next, previous, page, tab, menu, profile, about, help, docs, overview, list, browse, explore, history |
| **View Toggle** | `[VIEW]` | YES | expand, collapse, toggle, show, hide, sort, filter, search, minimize, maximize, zoom, fullscreen, open panel, close panel, refresh, scroll |
| **CRUD: Create** | `[CRUD:C]` | NO | create, new, add, insert, upload, import, clone, duplicate, copy |
| **CRUD: Update** | `[CRUD:U]` | NO | save, update, edit, modify, rename, apply, overwrite, merge, sync, patch |
| **CRUD: Delete** | `[CRUD:D]` | NO | delete, remove, destroy, clear, trash, discard, drop, purge, erase, wipe, reset |
| **Form Submit** | `[FORM]` | NO | submit, send, confirm, ok, yes, proceed, done, finish, continue, accept, approve |
| **Session** | `[SESSION]` | NO | login, logout, sign in, sign out, register, signup, disconnect |
| **Action Trigger** | `[ACTION]` | NO | run, start, stop, execute, generate, deploy, publish, export, download, print, share, notify, trigger, process, build, queue, cancel, dismiss |

**Default:** Elements not matching any keyword -> `[NAV]` (links without CRUD keywords are almost always navigational).

**Role-based overrides:** `link` role -> bias toward `[NAV]`. `button` role -> must check label keywords (buttons can be anything).

---

## Bash Annotation Function

Transforms raw `snapshot -i` output into category-tagged lines:

```bash
# Input:  button "Save Changes" [ref=e1]
# Output: [CRUD:U] button "Save Changes" [ref=e1]

annotate_elements() {
    local input="$1" output="$2"
    # Keywords per category (checked in priority order — first match wins)
    local CRUD_D='delete\|remove\|destroy\|trash\|purge\|drop\|erase\|wipe'
    local CRUD_U='save\|update\|edit\|modify\|rename\|apply\|overwrite\|merge\|sync\|patch'
    local CRUD_C='create\|new\|add\|insert\|upload\|import\|clone\|duplicate'
    local FORM='submit\|send\|confirm\| ok \|yes\|proceed\|done\|finish\|continue\|accept\|approve'
    local SESSION='login\|logout\|sign.in\|sign.out\|register\|signup\|disconnect'
    local ACTION='run\|start\|stop\|execute\|generate\|deploy\|publish\|export\|download\|print\|share\|trigger\|process\|build\|queue\|cancel\|dismiss'
    local VIEW='expand\|collapse\|toggle\|show\|hide\|sort\|filter\|search\|minimize\|maximize\|zoom\|fullscreen\|refresh'

    while IFS= read -r line; do
        lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        if echo "$lower" | grep -q "$CRUD_D"; then echo "[CRUD:D] $line"
        elif echo "$lower" | grep -q "$CRUD_U"; then echo "[CRUD:U] $line"
        elif echo "$lower" | grep -q "$CRUD_C"; then echo "[CRUD:C] $line"
        elif echo "$lower" | grep -q "$FORM"; then echo "[FORM] $line"
        elif echo "$lower" | grep -q "$SESSION"; then echo "[SESSION] $line"
        elif echo "$lower" | grep -q "$ACTION"; then echo "[ACTION] $line"
        elif echo "$lower" | grep -q "$VIEW"; then echo "[VIEW] $line"
        else echo "[NAV] $line"
        fi
    done < "$input" > "$output"
}
```

---

## Derived Filter: SKIP_MUTATE

All mutation-capable categories combined into one skip pattern for quick inline use. For SKILL.md code blocks that don't need the full annotator:

```bash
SKIP_MUTATE='create\|add\|save\|edit\|delete\|remove\|submit\|confirm\|login\|logout\|register\|run\|start\|stop\|generate\|export\|download\|cancel\|publish\|deploy'
```

**20 canonical verbs** — compact, deterministic, no sync drift. Guards enforce that only canonical verbs appear in element labels, so non-canonical synonyms (e.g., "destroy", "execute") never reach this filter.

Apply via `grep -vi "$SKIP_MUTATE"` BEFORE extracting `@e` refs.

---

## Usage Patterns

### Full Annotation Flow

For `/e2e` Phase 3B which saves `interactive-map.txt`:

```bash
agent-browser snapshot -i > "$RUN_DIR/raw-interactive-map.txt"
annotate_elements "$RUN_DIR/raw-interactive-map.txt" "$RUN_DIR/interactive-map.txt"

# Click only NAV and VIEW elements
for REF in $(grep '^\[NAV\]\|^\[VIEW\]' "$RUN_DIR/interactive-map.txt" | grep -oE '@e[0-9]+' | head -10); do
    agent-browser click "$REF"
done
```

### Quick Inline Filter

For `/ux-review` ad-hoc exploration:

```bash
agent-browser snapshot -i > /tmp/ux-interactive-map.txt
for REF in $(grep -vi "$SKIP_MUTATE" /tmp/ux-interactive-map.txt | grep -oE '@e[0-9]+' | head -10); do
    agent-browser click "$REF"
done
```

---

## Test Naming Conventions

| Category | Test File Pattern | Example |
|----------|-------------------|---------|
| NAV | `test_navigation.sh` | Sidebar nav, URL state, back button |
| VIEW | `test_{component}_toggle.sh` | Expand/collapse, show/hide |
| CRUD:C | `test_{feature}_create.sh` | Form submission, item creation |
| CRUD:U | `test_{feature}_update.sh` | Edit flow, save verification |
| CRUD:D | `test_{feature}_delete.sh` | Delete confirmation, removal |
| FORM | `test_{form}_submit.sh` | Form validation and submission |
| SESSION | `test_auth.sh` | Login/logout flows |
| ACTION | `test_{feature}_action.sh` | Trigger, execute, generate |

---

## Element Naming Conventions

When mapping elements from `snapshot -i`, name them by category:

```
# Raw discovery
button "Save Changes" [ref=e1]     -> CRUD:U element, testid: settings-save-btn
link "Dashboard" [ref=e2]          -> NAV element, testid: nav-dashboard
button "Delete" [ref=e3]           -> CRUD:D element, testid: item-delete-btn
menuitem "Settings" [ref=e4]       -> NAV element, testid: nav-settings
button "Expand Details" [ref=e5]   -> VIEW element, testid: details-expand-btn
```

Follow existing testid conventions from `ui-patterns.md`:
- Navigation: `nav-{name}`
- Buttons: `{entity}-{action}-btn`
- Toggles: `{name}-toggle`

---

## Canonical Verbs

These are the ONLY verbs that should appear in element labels and testids. If a verb isn't in this table, use the canonical equivalent from the synonym mapping below.

| Category | Canonical Verbs | TestID `{action}` | Example Label | Example TestID |
|----------|----------------|-------------------|---------------|----------------|
| **NAV** | *(noun-based, no verb)* | — | "Dashboard", "Settings" | `nav-dashboard`, `nav-settings` |
| **VIEW** | expand, collapse, toggle, show, hide, sort, filter, search, refresh | expand, collapse, toggle, etc. | "Expand Details" | `details-expand-btn` |
| **CRUD:C** | create, add | create, add | "Create User", "Add Item" | `user-create-btn`, `item-add-btn` |
| **CRUD:U** | save, edit | save, edit | "Save Changes", "Edit Profile" | `settings-save-btn`, `profile-edit-btn` |
| **CRUD:D** | delete, remove | delete, remove | "Delete User", "Remove Item" | `user-delete-btn`, `item-remove-btn` |
| **FORM** | submit, confirm | submit, confirm | "Submit Form", "Confirm Action" | `form-submit-btn`, `action-confirm-btn` |
| **SESSION** | login, logout, register | login, logout, register | "Login", "Logout" | `login-btn`, `logout-btn` |
| **ACTION** | run, start, stop, generate, export, download, cancel, publish, deploy | run, start, stop, etc. | "Generate Report", "Publish Post", "Deploy App" | `report-generate-btn`, `post-publish-btn` |

---

## Non-Canonical Synonym Mapping

Map common non-canonical verbs to their canonical equivalents. `/coding-guard` and `/cli-first` enforce this mapping.

| Non-Canonical | Canonical Equivalent | Category |
|--------------|---------------------|----------|
| destroy, purge, wipe, trash, erase, drop | **delete** or **remove** | CRUD:D |
| update, modify, rename, apply, overwrite, merge, patch | **save** or **edit** | CRUD:U |
| new, insert, upload, import, clone, duplicate | **create** or **add** | CRUD:C |
| send, proceed, done, finish, accept, approve | **submit** or **confirm** | FORM |
| sign in, sign out, signup, disconnect | **login**, **logout**, or **register** | SESSION |
| execute, trigger, process, build, queue, dismiss | **run**, **start**, **stop**, **generate**, **export**, **download**, **cancel**, **publish**, or **deploy** | ACTION |
| share | **export** (if file-like) or omit (if opens dialog) | ACTION |
| print | **download** (if file output) or omit (if browser native) | ACTION |
