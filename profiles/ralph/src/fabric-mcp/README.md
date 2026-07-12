# Fabric MCP Server

Model Context Protocol (MCP) server for [Fabric](https://github.com/danielmiessler/Fabric) - Daniel Miessler's AI-powered content processing framework.

This MCP server allows Claude (via Claude Desktop or Warp CLI) to use Fabric's extensive collection of AI patterns for content analysis, summarization, learning, coding, security analysis, and more.

## Quick Start

1. **Install Fabric** (if not already installed):
   
   See the [official Fabric installation guide](https://github.com/danielmiessler/Fabric#installation) for detailed instructions.

2. **Install yt-dlp** (optional, for YouTube transcripts):
   ```bash
   # macOS
   brew install yt-dlp
   
   # Linux/Windows
   pip install yt-dlp
   ```

3. **Download and Install**:
   - Download `fabric-mcp.mcpb` from [Releases](https://github.com/mpzarde/fabric-mcp/releases/latest)
   - Double-click the file
   - Click "Install" in Claude Desktop
   - Restart Claude Desktop

4. **Try it**:
   Ask Claude: "List all fabric patterns"

## Features

- 🚀 **Direct CLI Integration**: Uses Fabric CLI directly (no REST API server needed)
- 🔧 **19 Pre-configured Tools**: Direct access to commonly-used Fabric patterns plus combined analysis tools
- 🎯 **Generic Pattern Runner**: Run any Fabric pattern with `run_fabric_pattern`
- 📺 **YouTube Support**: Fetch video transcripts directly (requires yt-dlp)
- 🔍 **Pattern Discovery**: List all available patterns dynamically
- 📁 **File & URL Analysis**: Process files and web content with Fabric patterns
- 🏥 **Health Check**: Verify dependencies and configuration

## Prerequisites

### 1. Install Fabric

If you don't have Fabric installed, follow the [official Fabric installation guide](https://github.com/danielmiessler/Fabric#installation).

### 2. Install yt-dlp (Optional)

Required only if you want to fetch YouTube transcripts:

```bash
# macOS
brew install yt-dlp

# Linux
pip install yt-dlp
# Or: sudo apt install yt-dlp (on Ubuntu/Debian)

# Windows
pip install yt-dlp
```

### 3. Verify Installation

```bash
# Test Fabric
fabric --version
fabric --listpatterns

# Test yt-dlp (optional)
yt-dlp --version
```

## Installation

### Option 1: Download and Install (Recommended) 🎉

The easiest way to install:

1. **Download** the latest `fabric-mcp.mcpb` from [Releases](https://github.com/mpzarde/fabric-mcp/releases/latest)
2. **Double-click** the downloaded file
3. Claude Desktop will open and prompt you to install
4. Click **Install**
5. **Restart** Claude Desktop
6. Done!

The `.mcpb` file is a self-contained bundle that includes everything needed.

### Option 2: Build from Source

If you want to build from source:

```bash
git clone https://github.com/mpzarde/fabric-mcp.git
cd fabric-mcp
npm install
npm run build
```

Then either:
- **Build the `.mcpb` bundle**: `./build-mcpb.sh` (creates `fabric-mcp.mcpb` you can install)
- **Configure manually**: See Configuration section below for manual setup

## Configuration

### For Claude Desktop

> **Note**: If you installed using the `.mcpb` bundle (Option 1), Claude Desktop configures this automatically. This section is only needed for manual builds.

Add to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

**Windows**: `%APPDATA%/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "fabric": {
      "command": "node",
      "args": ["/absolute/path/to/fabric-mcp/dist/index.js"]
    }
  }
}
```

**Replace `/absolute/path/to/fabric-mcp/` with your actual project path.**

**Optional environment variables** (if needed):
```json
"env": {
  "FABRIC_PATH": "/custom/path/to/fabric",
  "YTDLP_PATH": "/custom/path/to/yt-dlp"
}
```

### For Warp CLI

> **Note**: Manual configuration is required for Warp. Build from source or extract the `.mcpb` bundle first.

Add to your Warp MCP configuration file:

**macOS/Linux**: `~/.warp/mcp_config.json`

```json
{
  "mcpServers": {
    "fabric": {
      "command": "node",
      "args": ["/absolute/path/to/fabric-mcp/dist/index.js"]
    }
  }
}
```

**Replace `/absolute/path/to/fabric-mcp/` with your actual project path.**

**Optional environment variables** (if needed):
```json
"env": {
  "FABRIC_PATH": "/custom/path/to/fabric",
  "YTDLP_PATH": "/custom/path/to/yt-dlp"
}
```

### Restart Claude/Warp

After configuration:
- **Claude Desktop**: Restart the application
- **Warp**: Restart the terminal or run `warp mcp reload`

## Available Tools

### Core Tools

1. **`health_check`** - Check if Fabric, yt-dlp, and other dependencies are installed and configured
2. **`list_fabric_patterns`** - List all available Fabric patterns
3. **`run_fabric_pattern`** - Run any Fabric pattern with custom input
4. **`get_youtube_transcript`** - Fetch transcript from YouTube video

### Combined Analysis Tools

These tools streamline common workflows by fetching content and applying patterns in one step. Benefits:
- ✅ **No truncation**: Complete content is passed directly to Fabric
- ✅ **More efficient**: Single tool call instead of multiple
- ✅ **Better results**: Fabric processes the full content without context window limits

1. **`analyze_youtube_video`** - Fetch YouTube transcript and apply a pattern in one step
2. **`analyze_file`** - Read a file and apply a pattern in one step
3. **`analyze_url`** - Fetch URL content and apply a pattern in one step

### Pre-configured Pattern Tools

These patterns are exposed as dedicated tools with the `fabric_` prefix:

#### Content Analysis
- `fabric_extract_wisdom` - Extract key insights and quotes from content
- `fabric_summarize` - Create concise summaries
- `fabric_analyze_claims` - Analyze and fact-check claims
- `fabric_analyze_paper` - Analyze academic papers

#### Learning
- `fabric_create_quiz` - Generate quiz questions
- `fabric_to_flashcards` - Convert content to flashcards

#### Development
- `fabric_summarize_git_diff` - Summarize git diffs for reviews
- `fabric_create_coding_project` - Generate project structure from ideas
- `fabric_explain_code` - Explain code in simple terms

#### Security & Operations
- `fabric_analyze_logs` - Analyze log files
- `fabric_analyze_incident` - Analyze security incidents

#### Writing
- `fabric_improve_writing` - Improve writing quality

## Usage Examples

### With Claude Desktop

**Extract wisdom from a YouTube video:**
```
User: Can you extract the key insights from this video? 
      https://www.youtube.com/watch?v=dQw4w9WgXcQ

Claude: [Uses get_youtube_transcript + fabric_extract_wisdom]
```

**Summarize an article:**
```
User: Summarize this article: [paste article text]

Claude: [Uses fabric_summarize]
```

**Create flashcards from lecture notes:**
```
User: Convert these lecture notes into flashcards: [paste notes]

Claude: [Uses fabric_to_flashcards]
```

**Analyze a git diff:**
```
User: Review this git diff and summarize the changes:
      [paste git diff output]

Claude: [Uses fabric_summarize_git_diff]
```

### Combined Analysis Tools

For efficiency, use the combined tools that fetch and analyze in one step:

```
User: Extract wisdom from this YouTube video:
      https://www.youtube.com/watch?v=example

Claude: [Uses analyze_youtube_video with pattern='extract_wisdom']
```

```
User: Summarize this article:
      https://example.com/article

Claude: [Uses analyze_url with pattern='summarize']
```

```
User: Explain the code in /path/to/script.py

Claude: [Uses analyze_file with pattern='explain_code']
```

### Chaining Patterns

Claude can chain multiple patterns together:

```
User: Get the transcript from this video, extract the wisdom, 
      then create flashcards from it.
      https://www.youtube.com/watch?v=example

Claude: 
[1. Uses get_youtube_transcript]
[2. Uses fabric_extract_wisdom on transcript]
[3. Uses fabric_to_flashcards on extracted wisdom]
```

## Use Cases

Based on Daniel Miessler's Fabric patterns:

### Content Processing
- YouTube video → extract wisdom / summarize
- Article / blog post → summarize, analyze claims
- Podcast transcript → extract wisdom, pull quotes

### Writing & Development
- Idea → essay (via `create_coding_project` or similar patterns)
- Code diff → PR description (via `summarize_git_diff`)
- Meeting notes → user stories (via `run_fabric_pattern` with `agility_story`)

### Learning
- Any content → flashcards (via `to_flashcards`)
- Dense docs → glossary with analogies
- Video/article → quiz (via `create_quiz`)

### Security Analysis
- Malware samples → analysis (via `analyze_malware`)
- Log files → threat interpretation (via `analyze_logs`)
- Security scans → rules (via `run_fabric_pattern`)

## Troubleshooting

### Check server health

Ask Claude: "Run a health check" - this will verify:
- Fabric installation and version
- Fabric configuration (API keys, patterns)
- yt-dlp installation (for YouTube support)
- Provide installation instructions if anything is missing

### Common Issues

#### Fabric not found

**Error**: `Failed to spawn fabric: ENOENT`

**Solutions**:
1. Install Fabric following the [official installation guide](https://github.com/danielmiessler/Fabric#installation)
2. Verify installation: `which fabric` and `fabric --version`
3. If using a custom Fabric location, set `FABRIC_PATH` in your MCP config

#### Pattern not found

**Error**: `Pattern not found: pattern_name`

**Solutions**:
1. Ask Claude to list all patterns: "List all fabric patterns"
2. Update patterns: `fabric --updatepatterns`
3. Check spelling - use underscores (e.g., `extract_wisdom` not `extractWisdom`)

#### YouTube transcripts not working

**Error**: `Failed to fetch YouTube transcript`

**Solutions**:
1. Install yt-dlp: `brew install yt-dlp` (macOS) or `pip install yt-dlp`
2. Verify: `yt-dlp --version`
3. If using custom location, set `YTDLP_PATH` in your MCP config

#### MCP server not appearing in Claude

**Solutions**:
1. Verify config file location:
   - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Windows: `%APPDATA%/Claude/claude_desktop_config.json`
2. Check JSON syntax with a validator
3. Ensure path to `dist/index.js` is absolute
4. Restart Claude Desktop completely
5. Check logs: `~/Library/Logs/Claude/mcp-server-fabric.log`

#### Pattern execution timeout

**Error**: `Fabric command timed out`

**Solutions**:
- Large patterns may take time (default: 5 minutes)
- Check your Fabric API keys and quota
- Try with a smaller input first

## Development

### Build

```bash
# Build TypeScript only
npm run build

# Build complete .mcpb bundle
./build-mcpb.sh
```

### Watch mode

```bash
npm run watch
```

### Testing locally

```bash
# Build the project
npm run build

# Test the MCP server
node dist/index.js
# Server will run on stdio and wait for MCP protocol messages

# Or use the health check to verify dependencies
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_check","arguments":{}}}' | node dist/index.js
```

## Architecture

```
┌─────────────────┐
│  Claude/Warp    │
└────────┬────────┘
         │ MCP Protocol (stdio)
         ▼
┌─────────────────┐
│  MCP Server     │ ← This project
│  (Node.js)      │
└────────┬────────┘
         │ Direct CLI calls
         ▼
┌─────────────────┐
│  Fabric CLI     │
│  (fabric cmd)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AI Patterns    │
│  OpenAI/etc.    │
└─────────────────┘
```

The MCP server:
1. Exposes Fabric patterns as MCP tools
2. Calls Fabric CLI directly with pattern names and input
3. Returns results back to Claude/Warp
4. No REST API server needed - uses CLI interface

## Resources

- **Fabric**: https://github.com/danielmiessler/Fabric
- **yt-dlp**: https://github.com/yt-dlp/yt-dlp
- **MCP Documentation**: https://modelcontextprotocol.io
- **MCP SDK**: https://github.com/modelcontextprotocol/typescript-sdk

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

## Credits

- **Fabric** by [Daniel Miessler](https://github.com/danielmiessler)
- **MCP** by [Anthropic](https://www.anthropic.com)
