# Link rewriting and auto-delete

Rewrite the links an uploader returns and delete uploads from the server after a number of days.

## Overview

Both properties work with every kind of uploader that returns a link. They sit at the top level of the `.iscu` file, next to `name`.

### Link rewriting

Any uploader can rewrite the link it gets back, for example to serve uploads from a CDN in front of the upload server. Change parts of the URL with rules:

```json
"linkRewrite": {
  "host": "cdn.example.com",
  "scheme": "https",
  "pathPrefix": "/i",
  "stripQuery": true
}
```

or replace it with a template:

```json
"linkRewrite": { "template": "https://cdn.example.com/{{path}}" }
```

| Property | Required | Description |
| --- | --- | --- |
| `host` | no | Replaces the host, optionally with a port such as `cdn.example.com:8443`. No scheme or path. |
| `scheme` | no | `http` or `https`. |
| `pathPrefix` | no | Put in front of the path, so `/files/a.png` becomes `/i/files/a.png`. |
| `stripQuery` | no | `true` removes the query string, such as signing tokens. |
| `template` | no | Builds the whole link and ignores the other rules. Placeholders: `{{url}}`, `{{scheme}}`, `{{host}}`, `{{port}}`, `{{path}}` (without the leading slash), `{{filename}}`, `{{query}}` and `{{fragment}}`. It must produce an http or https URL. |
| `rewriteDeletionURL` | no | `true` applies the same rewrite to the deletion URL. |

At least one rule or a template is required. The uploader editor shows a live preview with the last link the uploader returned. The rewritten link is what ishare copies, shortens, records in the history and sends to webhooks.

### Auto-delete

Uploaders that can delete files (HTTP uploaders with a `deletionURL`, S3, WebDAV, SFTP, Dropbox, Google Drive, OneDrive and GitHub) can delete uploads from the server after a number of days:

```json
"autoDeleteAfterDays": 30
```

The value must be between 1 and 3650. ishare checks on launch, every hour and after your Mac wakes, deletes uploads whose time is up and shows a summary notification. Failed deletions are retried with an increasing delay. Uploads you mark **Keep Forever** in the history are never deleted. Expired uploads stay in the history marked "Expired — deleted from server" unless you turn off **Settings → Uploaders → Auto-Delete → Keep expired uploads in history**. Only the Mac that made an upload deletes it, and uploads made before you turned auto-delete on are kept.

## See Also

- <doc:ISCUFormat>
- <doc:HTTPUploaders>
