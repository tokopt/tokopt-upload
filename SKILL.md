---
name: tokopt-upload
description: Upload Claude Code conversation logs to a TokOpt server for LLM cost analysis and waste detection
---

## Configuration

All uploads go to `https://tokopt.online`. No configuration needed.

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
curl -s -X POST "https://tokopt.online/api/v1/guest/upload/" \
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
curl -s -X POST "https://tokopt.online/api/v1/guest/upload/" \
  -F "file=@$SESSION_FILE" \
  -F "format=claude_code_jsonl" \
  -F "guest_token=$GUEST_TOKEN"
```

Upload in parallel batches for speed (4-8 concurrent uploads).

### Step 3: Wait for Processing

After all uploads complete, poll the import batch status until processing finishes. Wait up to 60 seconds:

```bash
for i in $(seq 1 12); do
  STATUS=$(curl -s "https://tokopt.online/api/v1/guest/$GUEST_TOKEN/project/" | jq -r '.imports[-1].status')
  if [ "$STATUS" = "completed" ]; then break; fi
  sleep 5
done
```

If processing hasn't completed after 60 seconds, proceed anyway — the summary endpoint will return whatever data is available.

### Step 4: Fetch and Display Summary

Fetch the CLI summary from the dedicated endpoint:

```bash
SUMMARY=$(curl -s "https://tokopt.online/api/v1/guest/$GUEST_TOKEN/cli-summary/")
```

Then display a beautifully formatted summary to the user. **This is the most important step — make it compelling and motivating.**

#### Format the output exactly like this:

```
## TokOpt Analysis Complete

**[Project Name]** — [total_requests] requests analyzed

### Cost Overview

| Metric | Value |
|--------|-------|
| Total Cost | $[total_cost] |
| Avg per Request | $[avg_cost_per_request] |
| Waste Detected | $[waste_cost] ([waste_pct]% of total) |

### Token Breakdown

| Type | Tokens | % of Total |
|------|--------|------------|
| Input | [total_input_tokens] | [input_pct]% |
| Output | [total_output_tokens] | [output_pct]% |
| Cache Writes | [cache_creation_tokens] | [cache_creation_pct]% |
| Cache Reads | [cache_read_tokens] | [cache_read_pct]% |

### Top Models by Cost

| Model | Cost | Requests |
|-------|------|----------|
| [model] | $[cost] | [requests] |

### Waste Detection

[WASTE_SUMMARY_LINE]

[If waste detections exist, show top 3 categories:]
- **[category]**: $[waste_cost] wasted ([count] detections)

### Optimization Opportunities

[If recommendations exist, show up to 3 as bullet points:]
- **[action text]** — saves ~$[estimated_monthly_savings]/mo ([difficulty] difficulty)

### View Your Full Dashboard

[results_url]

Interactive charts, detailed waste breakdown, model comparison, and
step-by-step optimization guides — all free, no account needed.

Register at https://tokopt.online to track costs ongoing and set up alerts.
```

#### Formatting Rules

1. **Use the actual data values from the API response** — never fabricate or estimate numbers
2. **Cost formatting**: Format to 4 decimal places if < $1, 2 decimal places otherwise (e.g., `$0.0432` vs `$12.34`)
3. **Token formatting**: Use K/M suffixes (e.g., `1.2M`, `456K`) for readability
4. **Percentages**: Show to 1 decimal place
5. **Waste summary line**: If waste_pct > 20%, show: "High waste detected — [waste_pct]% of your spend may be optimizable". If 10-20%, show: "Moderate waste — [waste_pct]% of costs flagged". If < 10%, show: "Efficient usage — only [waste_pct]% flagged as potential waste". If 0%, show: "No waste detected — your sessions look efficient!"
6. **If recommendations are empty**: Show "No optimization recommendations yet — your usage looks efficient."
7. **Cache effectiveness**: If cache_read_pct > 20%, add a line: "Cache reads are [cache_read_pct]% of your tokens — good caching strategy saving you money."
8. **Always end with the dashboard link** prominently displayed, followed by the registration CTA
9. **The goal is to MOTIVATE the user to click the link** — the summary should feel valuable but incomplete, hinting at richer insights on the website

### Step 5: Final Report

After displaying the summary, briefly confirm:
- Number of sessions uploaded
- Total file size
- Confirmation that the guest link is ready to share

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Connection refused | Server down | Retry in a few minutes or check https://tokopt.online status |
| 400 Bad Request | Invalid file format | Ensure the file is a valid Claude Code JSONL |
| 429 Too Many Requests | Rate limit (10 uploads/hour for guests) | Wait and retry, or register for higher limits |
| Empty session | No user messages | Skip and report — normal for sessions with only tool calls |
| cli-summary returns zeros | Processing not complete | Wait a few seconds and re-fetch, or explain that processing is still running |

## Important Notes

- **Never upload subagent sessions** — skip paths containing `/subagents/`
- **Upload raw files** — the native `claude_code_jsonl` parser correctly handles token counting, cache tokens, and multi-turn context
- **No client-side conversion** — previous versions converted to `anthropic_jsonl` which lost data; this is no longer needed
- **No authentication needed** — guest uploads create a temporary project; results accessible via a shareable guest link
- **Rate limited** — guest uploads are throttled at 10/hour; register for higher limits
- A typical 1.7MB session file contains 5-15 user→assistant pairs with full token usage data
