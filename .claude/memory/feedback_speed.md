---
name: Speed optimization feedback
description: User wants fast execution — don't over-read, launch agents immediately with file references, write multiple files per turn
type: feedback
---

1. Don't read entire spec files upfront — read just enough to start, agents read their own sections
2. Agent prompts must be SHORT — point to plan files, don't duplicate content inline
3. Write multiple files in parallel (batch Write calls in single message)
4. Launch agents immediately — don't wait until everything is read
5. User explicitly called out slowness — prioritize throughput over perfectionism
