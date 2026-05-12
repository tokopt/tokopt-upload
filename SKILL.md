---
name: tokopt-upload
description: Upload Claude Code conversation logs to a TokOpt server for LLM cost analysis and waste detection
---

## Quick Start

The standalone script at `tokopt-upload.sh` handles everything — session discovery, upload, and dashboard link display.

```bash
# Upload all sessions (including subagents)
bash tokopt-upload.sh

# Preview what would be uploaded
bash tokopt-upload.sh --dry-run

# Exclude subagent sessions
bash tokopt-upload.sh --no-subagents

# Add to existing project
bash tokopt-upload.sh --token <guest-token>

# Pass project name from skill arguments
bash tokopt-upload.sh --project "$ARGUMENTS"
```

The script can also be run directly via curl:
```bash
curl -fsSL https://tokopt.online/scripts/tokopt-upload.sh | bash
```

## Configuration

All uploads go to `https://tokopt.online`. No configuration needed.

**No authentication required.** The guest upload endpoint (`/api/v1/guest/upload/`) allows unauthenticated log uploads. A guest project is created automatically.

## What the Script Does

1. **Discovers sessions** — scans `~/.claude/projects/` for all `.jsonl` files, including subagent sessions by default
2. **Uploads with progress** — batch mode (20 files/batch) with single-file fallback
3. **Shows dashboard link** — prints the guest dashboard URL immediately after upload
4. **Exits** — analysis runs in the background on the server; the user refreshes the dashboard to see results

## API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/guest/upload/` | POST | Upload session files (multipart form) |
| `/api/v1/guest/upload/batch/` | POST | Upload multiple files at once |
| `/api/v1/guest/{token}/project/` | GET | Check import status |
| `/api/v1/guest/{token}/cli-summary/` | GET | Fetch formatted summary data |

## Script Options

| Flag | Description |
|------|-------------|
| `--server URL` | TokOpt server URL (default: `https://tokopt.online`) |
| `--project NAME` | Project name for this upload |
| `--token TOKEN` | Reuse existing guest token |
| `--no-subagents` | Exclude subagent sessions |
| `--dry-run` | Show sessions without uploading |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Connection refused | Server down | Retry in a few minutes or check https://tokopt.online status |
| 400 Bad Request | Invalid file format | Ensure the file is a valid Claude Code JSONL |
| 429 Too Many Requests | Rate limit (10 uploads/hour for guests) | Wait and retry, or register for higher limits |
| Empty session | No user messages | Skip and report — normal for sessions with only tool calls |

## Important Notes

- **Subagent sessions are included by default** — use `--no-subagents` to exclude them
- **Upload raw files** — the native `claude_code_jsonl` parser correctly handles token counting, cache tokens, and multi-turn context
- **No client-side conversion** — the script uploads raw JSONL files directly
- **No authentication needed** — guest uploads create a temporary project; results accessible via a shareable guest link
- **Rate limited** — guest uploads are throttled at 10/hour; register for higher limits
