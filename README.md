# tokopt-upload

Upload your Claude Code conversation logs for cost analysis and waste detection. No account needed.

## Quick Start

```bash
# One-liner — upload and get your dashboard link
curl -fsSL https://tokopt.online/scripts/tokopt-upload.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/tokopt/tokopt-upload.git
cd tokopt-upload
bash tokopt-upload.sh
```

## What It Does

1. Discovers all Claude Code session files in `~/.claude/projects/`
2. Uploads them (with subagent sessions) to TokOpt for analysis
3. Prints a dashboard link — analysis runs in the background on the server

Your data stays local until you run the script. Nothing is sent without your action.

## Options

| Flag | Description |
|------|-------------|
| `--server URL` | TokOpt server URL (default: `https://tokopt.online`) |
| `--project NAME` | Project name for this upload |
| `--token TOKEN` | Reuse an existing guest token |
| `--no-subagents` | Exclude subagent sessions |
| `--dry-run` | Show sessions without uploading |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

## Examples

```bash
# Preview what would be uploaded
bash tokopt-upload.sh --dry-run

# Skip subagent conversations
bash tokopt-upload.sh --no-subagents

# Add to an existing project
bash tokopt-upload.sh --token abc-123-def

# Use a custom server
bash tokopt-upload.sh --server https://my-tokopt.example.com
```

## Requirements

- `curl`
- `python3` (for JSON parsing)

Both are pre-installed on macOS and most Linux distributions.

## How It Works

- Uploads raw `.jsonl` files — no client-side conversion
- Creates a guest project automatically (no account needed)
- Supports batch uploads (20 files per batch) with single-file fallback
- Includes command history (`~/.claude/history.jsonl`) for context

## Privacy

- Only you decide when to upload — the script never runs automatically
- Guest uploads are rate-limited to 10/hour
- No authentication required for basic usage
- Register at [tokopt.online](https://tokopt.online) for ongoing tracking and alerts

## License

MIT
