# S3-compatible storage

Upload straight into a bucket with AWS Signature Version 4.

## Overview

Set `uploaderType` to `s3` and add an `s3` block to upload with signed `PUT` requests. This works with AWS S3, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, MinIO and other S3-compatible services.

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

`requestURL` and `responseURL` are not used by S3 uploaders and can be left out.

### The s3 block

| Property | Required | Description |
| --- | --- | --- |
| `endpoint` | yes | The service endpoint. `https://` is added when the scheme is missing. |
| `region` | no | The signing region. Defaults to `us-east-1`; R2 uses `auto`. |
| `bucket` | yes | The bucket to upload into. |
| `accessKeyId` | yes | The access key ID. |
| `secretAccessKey` | yes | The secret. It moves to the Keychain on import, and exports leave it out unless you choose to include it. |
| `pathStyle` | no | `true` (default) for `endpoint/bucket/key`, `false` for virtual-hosted `bucket.endpoint/key`. |
| `keyTemplate` | no | The object key. Defaults to `{{filename}}`. |
| `acl` | no | Sent as `x-amz-acl`, for example `public-read`. |
| `publicURL` | no | A template for the shared link. Defaults to the object URL. |
| `presignedExpiry` | no | Share a presigned link that expires after this many seconds instead of the public URL, from 1 to 604800 (seven days). Use it for private buckets. |

### Key templates

| Placeholder | Value |
| --- | --- |
| `{{filename}}` | The file name with its extension |
| `{{name}}` | The file name without its extension |
| `{{ext}}` | The extension in lowercase |
| `{{uuid}}` | A new UUID |
| `{{random}}` | A short random string |
| `{{timestamp}}` | Unix seconds |
| `{{date}}` | `yyyy/MM/dd` |
| `{{year}}`, `{{month}}`, `{{day}}` | Parts of the date |

### Public URL templates

| Placeholder | Value |
| --- | --- |
| `{{key}}` | The object key, URL-encoded |
| `{{rawkey}}` | The object key as is |
| `{{bucket}}` | The bucket |
| `{{region}}` | The region |
| `{{host}}` | The endpoint's host |
| `{{endpoint}}` | The endpoint URL |

### Deleting uploads

Deleting an S3 upload from the history window sends a signed `DELETE` for its key, so the access key needs permission to delete objects for that to work.

## See Also

- <doc:ISCUFormat>
- <doc:Examples>
