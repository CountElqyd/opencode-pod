# Dependencies

## External Tool Dependencies

### Fabric (Required)
- **Purpose**: AI pattern execution engine
- **Installation**: `pipx install fabric-ai`
- **Configuration**: `fabric --setup` (required)
- **Used for**: Running patterns, listing patterns, YouTube transcripts

### yt-dlp (Optional)
- **Purpose**: YouTube video transcript extraction
- **Installation**: `brew install yt-dlp` (macOS) or `pip install yt-dlp`
- **Used for**: `get_youtube_transcript` and `analyze_youtube_video` tools
- **Note**: Fabric also uses yt-dlp internally for `--youtube` flag

## Runtime Dependencies (npm)

### @modelcontextprotocol/sdk (^1.0.4)
- **Purpose**: Implements the MCP (Model Context Protocol) to communicate with Claude Desktop
- **Size**: ~49MB including all transitive dependencies
- **Required**: Yes - this is the core library that enables the extension to work

**What it includes:**
- MCP protocol implementation
- Server/client transport layers
- Type definitions for tools, resources, prompts
- JSON-RPC handling
- Various utilities

### Node.js Built-ins Used
- `child_process.spawn` - To execute the `fabric` and `yt-dlp` CLI commands
- `fs` - To check if executables exist at common paths, read local files
- `https`/`http` - To fetch content from URLs

## Development Dependencies

### typescript (^5.7.2)
- **Purpose**: Compiles TypeScript to JavaScript
- **Required**: Only for building, not included in bundle

### @types/node (^22.10.2)
- **Purpose**: TypeScript type definitions for Node.js APIs
- **Required**: Only for building, not included in bundle

## Bundle Size Breakdown

```
Total bundle size: ~9.3MB (compressed)
  ├── node_modules/     ~40MB (compressed to ~9MB)
  ├── dist/index.js     ~12KB
  ├── manifest.json     ~1KB
  ├── package.json      ~0.5KB
  ├── package-lock.json ~40KB
  ├── icon.png          ~5KB
  └── README.md         ~9KB
```

## Why Bundle node_modules?

The `.mcpb` bundle includes `node_modules` to ensure:
1. **Zero installation friction** - Works immediately after extraction
2. **Consistent versions** - Everyone uses the exact same dependencies
3. **Offline support** - No internet needed after download
4. **Reliability** - No npm registry downtime issues

## Could It Be Smaller?

We could potentially:
- Use `npm prune --production` to remove dev dependencies (already done)
- Exclude certain files with `.npmignore` (minimal gain)
- Tree-shake unused code (MCP SDK is already minimal)

However, at 9.3MB compressed, the bundle is already reasonable for a desktop extension.
