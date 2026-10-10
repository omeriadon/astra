# AI account limits research

_Research date: 2026-10-07_

## Codex

The supported app-server route is `account/rateLimits/read`. Its response exposes a backward-compatible `rateLimits` view and, when available, `rateLimitsByLimitId`; each bucket reports `usedPercent`, `windowDurationMins`, `resetsAt`, and optional plan or credit data. The documented endpoint requires Codex-backed authentication and does not work with API-key-only authentication. [OpenAI Codex app-server documentation](https://learn.chatgpt.com/docs/app-server)

For a browser session, the practical web route used by the primary-source CodexBar implementation is `GET https://chatgpt.com/backend-api/wham/usage`, with the browser's ChatGPT cookies. If that request returns `401`, it calls `GET https://chatgpt.com/api/auth/session` with the same cookie header, extracts the session `accessToken`, and retries the usage request with `Authorization: Bearer ...`; the returned user email binds the bearer retry to that cookie session. [CodexBar session authorization](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher%2BSessionAuthorization.swift), [CodexBar dashboard fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift)

The app should treat this as an undocumented ChatGPT web API, separate from the public API's token/RPM limits. A browser implementation can import the user's existing ChatGPT cookies in memory, request the usage JSON, and show unavailable or authentication errors without inventing zero values.

## Claude

Claude Code publicly exposes subscription windows through its statusline JSON after the first API response. `rate_limits.five_hour` and `rate_limits.seven_day` each provide `used_percentage` (0–100) and Unix `resets_at`; windows may be independently absent, and expired windows are removed. The documented statusline examples explicitly handle missing values with nullable access. This is for claude.ai Pro/Max subscriptions (or a gateway spend limit), not Anthropic API-key RPM/TPM limits. [Claude Code statusline documentation](https://code.claude.com/docs/en/statusline)

For browser-cookie retrieval, the primary-source CodexBar implementation uses Claude session cookies, calls `GET https://claude.ai/api/organizations` to select an organization UUID, then calls `GET https://claude.ai/api/organizations/{org_id}/usage`. Its usage model keeps nullable session and weekly windows, reset times, and an explicit live-window flag; a missing `five_hour` object must not be rendered as real `0%`. [CodexBar Claude web fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift)

## Astra integration boundary

The integration adds a manual developer-mode toggle while preserving automatic activation on localhost, and a `None`/`Codex`/`Claude` menu in Developer settings. The top-bar button polls the selected provider every 120 seconds while eligible. Private windows are excluded, browser session cookies remain in memory, and failed requests display unavailable, expired-session, or network-error states. These findings describe the routes and data contracts; live provider access was not verified.
