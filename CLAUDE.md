# CLAUDE.md - pfQuest Repository

## Repository Management

This is an **independent git repository** for the pfQuest WoW Classic addon that must be managed separately from the claude_general repository.

**Repository Details:**
- **Remote**: https://github.com/rickoneeleven/pfQuest
- **Purpose**: WoW Classic quest helper addon for Turtle WoW servers
- **Independence**: This repo has its own commit history, branches, and deployment cycle

## Development Workflow

### Making Changes
1. Work directly in this repository (`pfquest_proper/` folder)
2. Test changes locally if possible
3. Commit changes with descriptive messages
4. Push to the remote repository for WoW client to pull

### Debug System
**Implementation**: SavedVariables-based file logging with comprehensive quest routing analysis
- **debug.lua**: Core module, event-driven initialization (VARIABLES_LOADED/ADDON_LOADED)
- **route.lua**: Quest log analysis, routing decisions, coordinate tracking
- **config.lua**: UI toggle integration with real-time enable/disable
- **Storage**: pfQuest_debuglog circular buffer (1000 entries max)
- **Output**: WTF\Account\ACCOUNTNAME\SavedVariables\pfQuest.lua only (no chat spam)
- **Analysis**: Shows all quests (routable vs skipped), exclusion reasons, routing decisions
- **Format**: [YYYY-MM-DD HH:MM:SS.mmm] [LEVEL] message

### Git Commands
```bash
# Navigate to this repository
cd /home/rick111/claude_general/pfquest_proper

# Check status
git status

# Add changes
git add .

# Commit with proper message
git commit -m "descriptive message"

# Push to remote (requires authentication)
git push origin master
```

## Important Notes
- **Never merge** this repository into claude_general
- **Always work** directly in this folder for addon changes  
- **Separate concerns**: claude_general tracks general tasks, this tracks addon development
- **WoW dependency**: Changes here directly affect in-game addon functionality

## Current Status
Debug logging system implemented and ready for testing in Turtle WoW environment.