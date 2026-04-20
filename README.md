# tokopt-upload

A Claude Code skill that uploads your conversation logs to [TokOpt](https://tokopt.online) for LLM cost analysis and waste detection.

## What it does

Scans your `~/.claude/projects/` directory for Claude Code conversation sessions (`.jsonl` files) and uploads them to a TokOpt server. The server analyzes token usage, cache efficiency, and spending patterns to identify waste and deliver actionable cost-saving recommendations.

No account required — guest uploads create a temporary project with shareable results.

## Installation

### Option 1: Claude Code CLI (recommended)

```bash
claude skill add --repo git@github.com:tokopt/tokopt-upload.git
```

### Option 2: Git submodule

From your project root:

```bash
git submodule add git@github.com:tokopt/tokopt-upload.git .claude/skills/tokopt-upload
```

### Option 3: Manual

Copy `SKILL.md` into your project's `.claude/skills/tokopt-upload/` directory.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TOKOPT_URL` | `https://tokopt.online` | Base URL of the TokOpt server |

Set via environment variable:
```bash
export TOKOPT_URL=https://tokopt.online
```

## Usage

In Claude Code:

```
/tokopt-upload
```

Optionally pass a project name:

```
/tokopt-upload my-project-name
```

The skill will:
1. Scan your Claude Code projects for conversation sessions
2. Let you pick which sessions to upload (all, specific numbers, or a range)
3. Upload them in parallel to the TokOpt server
4. Return a guest link to view your cost analysis results

## Rate Limits

Guest uploads are throttled at 10 per hour. Register at [tokopt.online](https://tokopt.online) for higher limits.

## License

MIT
