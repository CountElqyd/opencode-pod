# Changelog

## Version 1.0.0 - CLI-Based Implementation

### Major Changes

**Switched from REST API to Direct CLI Execution**

The MCP server now calls the `fabric` binary directly instead of using the REST API. This provides several benefits:

#### Benefits:
- ✅ **Simpler**: No need to manage a Fabric server process
- ✅ **Faster**: Direct execution, no HTTP overhead
- ✅ **More Reliable**: No port conflicts or connection issues
- ✅ **Cleaner**: No configuration needed (host/port/API key removed)
- ✅ **Standard**: Uses Fabric the way it's meant to be used

#### Architecture Change:

**Before:**
```
Claude Desktop → MCP Server → HTTP → Fabric REST API → AI Provider
```

**After:**
```
Claude Desktop → MCP Server → fabric CLI → AI Provider
```

### Technical Changes

1. **Removed REST API dependencies**
   - No longer starts/manages `fabric --serve`
   - Removed HTTP fetch calls
   - Removed server process management

2. **Added direct CLI execution**
   - `runFabric()` - Spawns fabric process and captures stdout
   - Passes input via stdin
   - Returns output from stdout

3. **Removed configuration fields**
   - Removed `fabric_host` config
   - Removed `fabric_port` config
   - Removed `fabric_api_key` config
   - No user configuration needed!

4. **Updated commands**
   - `fabric --list` to get patterns
   - `fabric --pattern <name>` to run patterns
   - `fabric --youtube <url>` for transcripts

### Migration Notes

If upgrading from a previous version:
1. Uninstall the old extension
2. Install the new `.mcpb` bundle
3. No configuration needed - just works!

### Requirements

- Fabric must be installed: `pipx install fabric-ai`
- Fabric must be configured: `fabric --setup`
- `fabric` command must be in PATH

That's it! No server management, no ports, no API keys.
