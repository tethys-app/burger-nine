---
name: edit-menu
description: Edit a restaurant menu catalog interactively. Fetches the live catalog, applies described changes, shows before/after preview links, then saves to DB on confirmation. Use when the user says "edit [restaurant] menu", "change X on [slug]", "rename category", "update price", etc.
allowed-tools: Bash, Read, Edit, Write, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_take_screenshot
---

# Menu Editor

Edit restaurant catalogs locally, preview in browser, save to DB on confirmation.

## Workflow

### 1. Fetch & snapshot

```bash
SLUG=burger-nine-roussillon
ORIG=/tmp/${SLUG}-catalog.json
V1=/tmp/${SLUG}-catalog.v1.json

# Always fetch fresh from source (bypasses any stored edits)
curl -s "http://localhost:3000/api/catalog/${SLUG}?fresh=true" | jq . > $ORIG
cp $ORIG $V1
```

`$ORIG` is the pristine original — never edit it. All changes go into `.v1.json`, `.v2.json`, etc.

### 2. Apply changes

Edit `$V1` with the Edit tool. Keep JSON pretty-printed (python3 -m json.tool after edits).

Common edits:
- **Rename category**: find in `categories[]`, change `name`
- **Rename product**: find in `products[]`, change `name` or `description`
- **Change price**: find in `products[]`, change `price` (number, no currency symbol)
- **Reorder categories**: reorder entries in `categories[]` array
- **Hide product**: remove from `products[]` (or set a flag if supported)

### 3. Validate

```bash
curl -s "http://localhost:3000/api/menu/${SLUG}?catalog=${V1}" | jq '{source,sections_count:(.sections|length),error,issues}'
```

If `error` is present the JSON failed schema validation — `issues` shows exactly which fields. Fix before proceeding.

### 4. Give preview links

Always provide both links so the user can compare:

- **Before**: `http://localhost:3000/{slug}`
- **After**: `http://localhost:3000/{slug}?catalog={v_file}&focus=category:{ref}` (focus on the edited section)

Take a screenshot of the "after" URL and show it inline.

### 5. Diff summary

```bash
diff <(jq . $ORIG) <(jq . $V1)
```

Show the diff to the user so changes are explicit.

### 6. On "save" / confirmation

```bash
curl -s -X POST "http://localhost:3000/api/catalog/${SLUG}" \
  -H "Content-Type: application/json" \
  -d @${V1}
```

Confirm with: `{ "ok": true }`. Tell the user the catalog is now live and the `?catalog=` param is no longer needed.

### 7. Versioning for next round

If the user wants more edits after saving:
```bash
cp $V1 /tmp/${SLUG}-catalog.v2.json
# edit v2, preview, save
```

## Rules

- Never edit `$ORIG` — it's the reset point
- Always pretty-print JSON (python3 -m json.tool) so diffs are readable
- Always show the diff before asking for save confirmation
- Focus param uses section/category `ref` from `categories[]`, or product `ref` from `products[]`
- Price is a **float** (e.g. `9.50`), never a string
- After saving, verify by hitting `/api/menu/{slug}` (no catalog param) and confirming source is no longer "local"
