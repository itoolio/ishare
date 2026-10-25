---
layout: ../../layouts/Doc.astro
title: Custom uploaders
description: The ishare custom uploader (.iscu) specification for HTTP services, S3-compatible storage, WebDAV, SFTP, Dropbox, Google Drive, OneDrive and GitHub.
---

# Custom uploaders

ishare opens `.iscu` files, which are JSON documents that describe where and how to upload captures. Double-click one to import it, drop it on the import sheet in **Settings → Uploaders**, or build one in the editor there. On Macs with Apple Intelligence, the **Assistant** button creates an uploader from a few answers.

Property names are case-insensitive, and trailing commas and comments are accepted.

## HTTP uploaders

```json
{
  "name": "My server",
  "requestURL": "https://uploader.example.com/upload",
  "headers": { "Authorization": "Bearer YOUR_TOKEN" },
  "formData": { "album": "screenshots" },
  "fileFormName": "file",
  "requestBodyType": "multipartFormData",
  "responseURL": "{{files[0].url}}",
  "deletionURL": "{{files[0].deleteUrl}}",
  "deleteRequestType": "DELETE"
}
```

| Property | Required | Description |
| --- | --- | --- |
| `name` | yes | Shown in the menu and settings. |
| `requestURL` | yes | The http or https URL the file is POSTed to. |
| `headers` | no | Extra request headers, such as API keys. |
| `formData` | no | Extra multipart text fields. |
| `fileFormName` | no | The multipart field that carries the file. Defaults to `file`. |
| `requestBodyType` | no | `multipartFormData` (default) or `binary` to send the raw file as the body. |
| `responseURL` | yes | Template for the public URL of the upload. |
| `deletionURL` | no | Template for a URL that deletes the upload. |
| `deleteRequestType` | no | `GET` (default) or `DELETE`. |

### Response templates

Wrap JSON paths from the response in double braces. Nested objects use dots and arrays use indexes, for example `{{url}}`, `{{data.link}}` or `{{files[0].url}}`. Templates can mix text and placeholders, such as `https://cdn.example.com/{{id}}.{{ext}}`. When a service answers with the URL as plain text, use `{{response}}`.

Every upload also sends an `x-file-name` header with the original file name.

### Password-protected and expiring links

Services that can protect a link with a password or delete it after a while describe that with an optional `linkOptions` block. ishare then lets you pick a password and an expiry for each upload: set the defaults in the uploader editor, or turn on **Ask every time** to choose them in a prompt before every upload to that uploader. The default password is stored in your Keychain, never in the `.iscu` file.

```json
{
  "name": "Zipline",
  "requestURL": "https://zipline.example.com/api/upload",
  "headers": { "Authorization": "API_KEY" },
  "responseURL": "{{files[0].url}}",
  "linkOptions": {
    "password": { "field": "x-zipline-password", "location": "header" },
    "expiry": { "field": "x-zipline-deletes-at", "location": "header", "format": "iso8601", "template": "date={{value}}" }
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `password.field`, `expiry.field` | yes | Name of the form field, header or query parameter. |
| `location` | no | `form` (default, multipart field), `header` or `query`. `form` needs a multipart body. |
| `expiry.format` | no | `seconds` (default, seconds from now), `minutes` (minutes from now, rounded up), `iso8601` (UTC date such as `2026-10-23T12:00:00Z`) or `timestamp` (Unix seconds). |
| `template` | no | Wraps the value, for example `date={{value}}` or `{{value}}m`. Must contain `{{value}}`. |

Either `password` or `expiry` can be left out. Nothing is sent when you upload without a password or with links that never expire.

## S3-compatible storage

Set `uploaderType` to `s3` to upload with AWS Signature Version 4. This works with AWS S3, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, MinIO and other S3-compatible services.

```json
{
  "name": "Cloudflare R2",
  "uploaderType": "s3",
  "s3": {
    "endpoint": "https://ACCOUNT_ID.r2.cloudflarestorage.com",
    "region": "auto",
    "bucket": "screenshots",
    "accessKeyId": "ACCESS_KEY_ID",
    "secretAccessKey": "SECRET_ACCESS_KEY",
    "pathStyle": true,
    "keyTemplate": "{{date}}/{{uuid}}.{{ext}}",
    "publicURL": "https://img.example.com/{{key}}"
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `endpoint` | yes | The service endpoint. `https://` is added when the scheme is missing. |
| `region` | no | Signing region. Defaults to `us-east-1`; R2 uses `auto`. |
| `bucket` | yes | The bucket to upload into. |
| `accessKeyId`, `secretAccessKey` | yes | Credentials with permission to put (and optionally delete) objects. |
| `pathStyle` | no | `true` (default) for `endpoint/bucket/key`, `false` for `bucket.endpoint/key`. |
| `keyTemplate` | no | Object key. Defaults to `{{filename}}`. |
| `acl` | no | Sent as `x-amz-acl`, for example `public-read`. |
| `publicURL` | no | Template for the shared link. Defaults to the object URL. |

Key templates support `{{filename}}`, `{{name}}`, `{{ext}}`, `{{uuid}}`, `{{random}}`, `{{timestamp}}`, `{{date}}` (`yyyy/MM/dd`), `{{year}}`, `{{month}}` and `{{day}}`. Public URL templates support `{{key}}`, `{{rawkey}}`, `{{bucket}}`, `{{region}}`, `{{host}}` and `{{endpoint}}`.

Deleting an S3 upload from the history window sends a signed `DELETE` for its key.

## WebDAV

Set `uploaderType` to `webdav` to `PUT` files on Nextcloud, ownCloud, Synology, Apache `mod_dav`, nginx, rclone and other WebDAV servers.

```json
{
  "name": "Nextcloud",
  "uploaderType": "webdav",
  "webdav": {
    "url": "https://cloud.example.com/remote.php/dav/files/USERNAME/ishare",
    "username": "USERNAME",
    "password": "APP_PASSWORD",
    "authentication": "basic",
    "pathTemplate": "{{date}}/{{uuid}}.{{ext}}",
    "createDirectories": true,
    "publicURL": "https://files.example.com/ishare/{{path}}"
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `url` | yes | The WebDAV collection uploads go into. |
| `username`, `password` | no | Credentials. The password is moved to your Keychain when you import the file. |
| `authentication` | no | `basic` (default, sent with every request) or `digest` (answered when the server asks). |
| `pathTemplate` | no | Path below `url`. Defaults to `{{date}}/{{filename}}` and supports the same placeholders as S3 key templates. |
| `createDirectories` | no | `true` (default) creates missing folders with `MKCOL` before uploading. |
| `publicURL` | no | Link to copy. Supports `{{path}}`, `{{rawpath}}`, `{{filename}}`, `{{rawfilename}}` and `{{directory}}`. Without it, ishare copies the WebDAV URL of the file. |

Deleting the upload from the history sends a `DELETE` for the file.

## SFTP

Set `uploaderType` to `sftp` to copy files to a server over SSH. ishare signs in with a password or an OpenSSH Ed25519 or RSA private key.

```json
{
  "name": "My server",
  "uploaderType": "sftp",
  "sftp": {
    "host": "files.example.com",
    "port": 22,
    "username": "deploy",
    "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----\n…\n-----END OPENSSH PRIVATE KEY-----",
    "passphrase": "optional",
    "directory": "/var/www/i.example.com",
    "pathTemplate": "{{year}}/{{month}}/{{random}}.{{ext}}",
    "createDirectories": true,
    "publicURL": "https://i.example.com/{{path}}",
    "hostKeyFingerprint": "SHA256:…"
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `host` | yes | Host name or address. An `sftp://user@host:port/folder` URL also works, as `host` or `url`. |
| `port` | no | Defaults to `22`. |
| `username` | yes | The SSH user. |
| `password` or `privateKey` | yes | One of them. `privateKey` is the full OpenSSH key text; `passphrase` unlocks an encrypted key. All three are moved to your Keychain. |
| `directory` | no | Remote folder the path template is relative to. Without it, paths are relative to the login folder. |
| `pathTemplate` | no | Defaults to `{{date}}/{{filename}}`. |
| `createDirectories` | no | `true` (default) creates missing folders like `mkdir -p`. |
| `publicURL` | no | Link to copy, with the same placeholders as WebDAV. Without it, the upload is kept in the history but no link is copied. |
| `hostKeyFingerprint` | no | The SHA-256 fingerprint of the server's host key, as printed by `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. Without it, ishare trusts the key it sees on the first connection and stores its fingerprint with the uploader. Uploads fail if the key changes later. **Check Host Key** in the uploader settings shows the fingerprint before you upload. |

## Dropbox, Google Drive and OneDrive

These uploaders sign in through your browser with OAuth 2.0 and PKCE. The access and refresh tokens are stored in your Keychain and refreshed automatically; they are never written to the `.iscu` file. Each upload gets a shareable link: a public Dropbox shared link, a Google Drive file shared with anyone who has the link, or a OneDrive view link.

```json
{
  "name": "Dropbox",
  "uploaderType": "dropbox",
  "cloud": {
    "folder": "ishare",
    "pathTemplate": "{{date}}/{{filename}}",
    "directLink": false
  }
}
```

`uploaderType` is `dropbox`, `googledrive` or `onedrive`.

| Property | Required | Description |
| --- | --- | --- |
| `folder` | no | Folder uploads go into. Defaults to `ishare`. Missing folders are created. |
| `pathTemplate` | no | File name (and optional subfolders) inside `folder`. Defaults to `{{filename}}`. Existing files are never replaced. |
| `directLink` | no | Dropbox only: copy a `raw=1` link that opens the file itself instead of the Dropbox preview page. |
| `clientId` | no | The client ID of your own app. Needed only when your copy of ishare was built without one for that provider. |

Google Drive uploads use the `drive.file` scope, so ishare can only see files it created. Deleting an upload from the history deletes the file from the cloud storage.

To use your own app, register it with the provider and add the redirect URI shown in the uploader settings: `ishare-oauth://dropbox` for a Dropbox "Scoped access" app with public clients (PKCE) allowed, `ishare-oauth://onedrive` for a Microsoft Entra app that supports personal and work accounts on a "Mobile and desktop applications" platform, and `com.googleusercontent.apps.CLIENT_ID_PREFIX:/oauth2redirect` for a Google "iOS" OAuth client with the bundle ID `dev.adrian.ishare`. None of them needs a client secret.

## GitHub

Set `uploaderType` to `github` to commit images and other files to a repository with the Contents API. Text snippets, such as text you upload from the clipboard, become Gists instead.

```json
{
  "name": "GitHub screenshots",
  "uploaderType": "github",
  "github": {
    "repository": "OWNER/screenshots",
    "branch": "main",
    "pathTemplate": "{{date}}/{{uuid}}.{{ext}}",
    "linkStyle": "raw",
    "token": "github_pat_…",
    "textAsGist": true,
    "publicGists": false
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `repository` | yes | `owner/name`. |
| `branch` | no | Defaults to the repository's default branch. |
| `pathTemplate` | no | Path in the repository. Defaults to `{{date}}/{{uuid}}.{{ext}}`. |
| `linkStyle` | no | `raw` (default) copies the `raw.githubusercontent.com` URL, `blob` copies the GitHub page, and `markdown` copies `![name](raw URL)` for images or `[name](URL)` for other files. |
| `token` | yes | A fine-grained personal access token, moved to your Keychain on import. Limit it to the upload repository and grant **Contents: Read and write**, plus **Gists: Read and write** on the account for snippets. |
| `textAsGist` | no | `true` (default) uploads text files as Gists. |
| `publicGists` | no | `false` (default) creates secret Gists. |
| `commitMessage` | no | Defaults to `Upload {{filename}} with ishare`. |

Builds of ishare with a GitHub OAuth app can also **Sign in with GitHub** through the device flow, which asks for the `repo` and `gist` scopes. Raw links only work for public repositories. Deleting an upload from the history deletes the file in a new commit, or deletes the Gist.

## Image optimization

Any uploader can override the global image settings in **Settings → Uploaders → Images**:

```json
"imageOptimization": { "enabled": true, "format": "lossless" }
```

`format` is `lossless` (recompress PNGs without changing pixels and drop their ancillary chunks), `avif` (HEIC on Macs that can't encode AVIF) or `webp` (only where macOS can encode WebP). Leave a property out to use the global setting. The optimized file is uploaded only when it is smaller, and the history shows how much it saved.

## Link rewriting

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

## Auto-delete

Uploaders that can delete files (HTTP uploaders with a `deletionURL`, S3, WebDAV, SFTP, Dropbox, Google Drive, OneDrive and GitHub) can delete uploads from the server after a number of days:

```json
"autoDeleteAfterDays": 30
```

The value must be between 1 and 3650. ishare checks on launch, every hour and after your Mac wakes, deletes uploads whose time is up and shows a summary notification. Failed deletions are retried with an increasing delay. Uploads you mark **Keep Forever** in the history are never deleted. Expired uploads stay in the history marked "Expired — deleted from server" unless you turn off **Settings → Uploaders → Auto-Delete → Keep expired uploads in history**. Only the Mac that made an upload deletes it, and uploads made before you turned auto-delete on are kept.

## Local destinations

Folder and Photos uploaders keep captures on your Mac instead of uploading them. They can be the default uploader, an extra destination or part of an upload preset. Create them in **Settings → Uploaders → Create**.

### Folder

```json
{
  "name": "Website folder",
  "uploaderType": "folder",
  "folder": {
    "path": "~/Sites/screenshots",
    "subfolderTemplate": "{{date}}",
    "publicURL": "https://example.com/screenshots/{{path}}"
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `path` | yes | The folder captures are copied into. Choose it again with **Choose…** after importing so ishare is allowed to write to it. |
| `subfolderTemplate` | no | Subfolder for each capture. Supports the same placeholders as S3 key templates, for example `{{date}}` or `{{year}}/{{month}}`. |
| `publicURL` | no | Link to copy for folders that a web server or sync service publishes. Supports `{{filename}}`, `{{path}}` (subfolder and file name) and `{{subfolder}}`. Without it, ishare copies the `file://` URL. |

Files with the same name get a number appended instead of being replaced. Deleting the upload from the history moves the copy to the Trash.

**iCloud Drive** is a folder uploader that starts the folder picker in iCloud Drive. Choose iCloud Drive or a folder inside it and iCloud syncs the captures to your other devices.

### Photos

```json
{
  "name": "Photos",
  "uploaderType": "photos",
  "photos": { "album": "ishare" }
}
```

Captures are added to the album named by `album`, which is created when it doesn't exist. Use `"album": ""` to add them to the library only. ishare asks for Photos access when you create the uploader. Apps can't create shared albums or add to them, so pick a regular album and share it from Photos. Photos uploads have no link; the history keeps a reference to the photo, and deleting the upload there removes it from Photos.

## Webhooks

**Settings → Uploaders → Webhooks** sends a `POST` request after every successful upload, in the background and without delaying the link. Failed deliveries are retried three times with increasing delays. The `ishare JSON` payload looks like this:

```json
{
  "event": "upload.completed",
  "link": "https://i.example.com/2026/01/abc.png",
  "shortLink": "https://is.gd/abc",
  "deletionLink": "https://i.example.com/delete/abc",
  "fileName": "abc.png",
  "size": 123456,
  "type": "image/png",
  "uploader": "My server",
  "timestamp": "2026-01-01T12:00:00Z",
  "altText": "A bar chart of monthly downloads",
  "savedBytes": 20480
}
```

Properties without a value are left out. With a signing secret, the `X-ishare-Signature` header carries `sha256=` followed by the hex HMAC-SHA256 of the raw body, keyed with the secret. The `X-ishare-Event` header is `upload.completed`, or `webhook.test` for **Send Test**. The Slack and Discord presets send a message in the format of their incoming webhooks instead.

## Removing photo metadata

**Remove location and camera details from imported photos** is on by default. It strips GPS location, camera make, model and serial number, maker notes, IPTC and XMP data from Continuity Camera images, dropped files, files sent through the Services menu and the watch folder before they are uploaded, while keeping the orientation and color profile. Turn on **Remove location and camera details from every upload** to clean your own captures too.

## Shortcuts

Every uploader appears in the Shortcuts app. Use **Upload with ishare** to upload any image or video and get its URL back, or **Set ishare Uploader** to switch the default uploader.

## Migrating from 1.x uploaders

Version 2.0 replaced `responseProp` with `responseURL` templates. Rewrite `"responseProp": "url"` as `"responseURL": "{{url}}"`, and move any fixed URL prefix into the template.
