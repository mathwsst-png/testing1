# n4th

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZennJxD/n4th/refs/heads/main/n4th"))()
```

`n4th` is the stable loader. Every execution asks the public GitHub API for the current `main` commit, then downloads `n4th-main.lua` from that immutable commit URL. This avoids stale branch contents. A failed update check reports an error instead of silently running old code.

Publish main-script changes to `n4th-main.lua` on branch `main`. Updates apply when executed again; an already running session does not reload itself.

`n4th-diagnose.lua` prints read-only inventory and action-reference diagnostics and copies the report if the executor supports the clipboard. It performs no gameplay actions.
