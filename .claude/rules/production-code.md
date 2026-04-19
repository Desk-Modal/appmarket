# Production Code Rules
- No TODO, FIXME, HACK comments in shipped code
- No console.log — use structured logging service
- No placeholder data, demo modes, or stub implementations
- Error handling on every async operation
- Loading states for every async UI
- Graceful degradation when DeskModal APIs unavailable
