# Cursor Mobile companion protocol

LAN WebSocket between the iOS app and the desktop companion. JSON text frames.

Service type: `_cursormobile._tcp`

First client message must be `hello` with the 6-digit pairing code shown on the computer. The companion never sends Cursor API keys to the phone.

## Envelope

```json
{ "type": "string", "id": "optional-request-id", "payload": {} }
```

## Client → server

| type | payload |
| --- | --- |
| `hello` | `{ "pairingCode": "123456", "client": "ios", "version": "1.0.0" }` |
| `chats.open` | `{ "id": "composer-or-session-id" }` |
| `followup` | `{ "threadId": "...", "text": "...", "mode": "agent\|plan\|ask\|debug\|multitask", "model": { "id": "...", "params": [] } }` |
| `cancel` | `{ "threadId": "..." }` |
| `permission.decide` | `{ "requestId": "...", "optionId": "allow-once\|allow-always\|reject-once" }` |
| `permission.setMode` | `{ "mode": "allowlist\|auto-review\|unrestricted", "sandbox": false }` |
| `mode.set` | `{ "threadId": "...", "mode": "agent\|plan\|ask\|debug\|multitask" }` |
| `plan.decide` | `{ "requestId": "...", "outcome": "accepted\|rejected", "build": "agent\|multitask" }` |
| `question.answer` | `{ "requestId": "...", "answers": [{ "questionId": "...", "selectedOptionIds": [] }] }` |
| `models.refresh` | `{}` |
| `login.status` | `{}` |

## Server → client

| type | payload |
| --- | --- |
| `hello.ok` | `{ "computerName": "...", "user": { "email": "", "name": "" }, "approvalMode": "auto-review" }` |
| `hello.denied` | `{ "reason": "bad-code" }` |
| `chats.catalog` | `{ "workspaces": Workspace[], "threads": ThreadSummary[], "counts": Counts }` |
| `chats.upserted` | `ThreadSummary` |
| `chats.removed` | `{ "id": "..." }` |
| `chats.thread` | `ThreadDetail` |
| `subagent.upserted` | `Subagent` |
| `permission.request` | `PermissionRequest` |
| `permission.resolved` | `{ "requestId": "..." }` |
| `context.usage` | `ContextUsage` |
| `models.list` | `{ "items": Model[] }` |
| `me` | `{ "email": "", "name": "", "plan": "" }` |
| `usage` | `{ "totalTokens": 0, "localAgents": 0, "cloudAgents": 0 }` |
| `stream.delta` | `{ "threadId": "...", "subagentId": null, "event": {} }` |
| `plan.request` | `{ "requestId": "...", "threadId": "...", "name": "", "overview": "", "plan": "", "todos": [] }` |
| `question.request` | `{ "requestId": "...", "threadId": "...", "title": "", "questions": [] }` |
| `compaction` | `{ "threadId": "...", "percent": 85 }` |
| `error` | `{ "message": "..." }` |
