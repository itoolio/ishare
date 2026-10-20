---
layout: ../../layouts/Doc.astro
title: Custom uploaders
description: The ishare custom uploader (.iscu) specification for HTTP services and S3-compatible storage.
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

## Shortcuts

Every uploader appears in the Shortcuts app. Use **Upload with ishare** to upload any image or video and get its URL back, or **Set ishare Uploader** to switch the default uploader.

## Migrating from 1.x uploaders

Version 2.0 replaced `responseProp` with `responseURL` templates. Rewrite `"responseProp": "url"` as `"responseURL": "{{url}}"`, and move any fixed URL prefix into the template.
