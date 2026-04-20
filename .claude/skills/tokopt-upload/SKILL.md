---
name: tokopt-upload
description: Upload Claude Code conversation logs to a TokOpt server for LLM cost analysis and waste detection
---

## Configuration

Before running, check for the `TOKOPT_URL` environment variable:
- `TOKOPT_URL` — Base URL of the TokOpt server (e.g., `https://tokopt.online` or `http://localhost:8000`)

If `TOKOPT_URL` is missing, default to `https://tokopt.online`.

**No authentication required.** The guest upload endpoint (`/api/v1/guest/upload/`) allows unauthenticated log uploads. A guest project is created automatically.

You can also accept `$ARGUMENTS` as an optional project name.

## Process

### Step 1: Discover Sessions

Scan the user's Claude Code projects directory for conversation sessions:

```bash
find ~/.claude/projects/ -name "*.jsonl" -not -path "*/subagents/*" -type f 2>/dev/null
```

For each file, get metadata:

```bash
for f in $(find ~/.claude/projects/ -name "*.jsonl" -not -path "*/subagents/*" -type f 2>/dev/null); do
  size=$(du -h "$f" | cut -f1)
  modified=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1)
  user_msgs=$(grep -c '"type":"user"' "$f" 2>/dev/null || echo 0)
  echo "$f | ${size} | ${modified} | ${user_msgs} user messages"
done
```

Present the list numbered and ask the user which sessions to upload:
- "all" — upload all sessions
- Specific numbers (e.g., "1, 3, 5")
- A range (e.g., "1-5")

### Step 2: Upload Raw Files (Guest)

Upload each session file directly to the guest endpoint with `format=claude_code_jsonl`. No authentication needed — the backend creates a guest project automatically.

```bash
curl -s -X POST "$TOKOPT_URL/api/v1/guest/upload/" \
  -F "file=@$SESSION_FILE" \
  -F "format=claude_code_jsonl" \
  -F "name=$PROJECT_NAME"
```

The response includes:
```json
{
  "guest_token": "uuid-for-accessing-results",
  "project_id": "uuid-of-created-project",
  "project_name": "...",
  "import_batch": { "id": "...", "status": "queued|processing|completed", ... }
}
```

For the first upload, capture the `guest_token` from the response and reuse it for all subsequent uploads in the same batch (so all sessions land in the same project). On subsequent uploads, include the guest token:

```bash
curl -s -X POST "$TOKOPT_URL/api/v1/guest/upload/" \
  -F "file=@$SESSION_FILE" \
  -F "format=claude_code_jsonl" \
  -F "guest_token=$GUEST_TOKEN"
```

Upload in parallel batches for speed (4-8 concurrent uploads).

### Step 3: Report

Show a summary:
- Sessions scanned vs uploaded
- Import batch status per session (completed / processing / failed)
- Total file size uploaded
- **Guest access link**: `$TOKOPT_URL/results/$GUEST_TOKEN` — user can view results immediately, no account needed
- Note: user can claim the project later by registering at `$TOKOPT_URL`

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Connection refused | Wrong URL or server down | Check TOKOPT_URL and that TokOpt is running |
| 400 Bad Request | Invalid file format | Ensure the file is a valid Claude Code JSONL |
| 429 Too Many Requests | Rate limit (10 uploads/hour for guests) | Wait and retry, or register for higher limits |
| Empty session | No user messages | Skip and report — normal for sessions with only tool calls |

## Important Notes

- **Never upload subagent sessions** — skip paths containing `/subagents/`
- **Upload raw files** — the native `claude_code_jsonl` parser correctly handles token counting, cache tokens, and multi-turn context
- **No client-side conversion** — previous versions converted to `anthropic_jsonl` which lost data; this is no longer needed
- **No authentication needed** — guest uploads create a temporary project; results accessible via a shareable guest link
- **Rate limited** — guest uploads are throttled at 10/hour; register for higher limits
- A typical 1.7MB session file contains 5-15 user→assistant pairs with full token usage data
