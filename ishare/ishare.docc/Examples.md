# Examples

Ready-made uploaders for popular services, from the repository's `examples` folder.

## Overview

Each example below is an `.iscu` file in the [examples](https://github.com/itoolio/ishare/tree/main/examples) folder. Download one, replace the placeholders in capitals with your own host and keys, and open it with ishare. **Test Upload** in the uploader editor shows the server's response, which helps when a service answers differently than expected.

### chibisafe

A multipart upload with an API key header, a file field named `file[]` and server-side deletion with `DELETE`.

```json
{
  "name": "chibisafe",
  "requestURL": "https://chibisafe.moe/api/upload",
  "headers": {
    "x-api-key": "API_KEY"
  },
  "fileFormName": "file[]",
  "responseURL": "{{url}}",
  "deletionURL": "{{deleteUrl}}",
  "deleteRequestType": "DELETE"
}
```

### copyparty

copyparty answers with JSON when asked to, and expects the file in a field named `f`.

```json
{
  "name": "copyparty",
  "requestURL": "http://127.0.0.1:3923/screenshots/",
  "headers": {
    "pw": "VALUE",
    "accept": "json"
  },
  "fileFormName": "f",
  "responseURL": "{{files[0].url}}"
}
```

### Discord webhook

Extra form fields set the name and avatar of the webhook message, and the link comes from the first attachment.

```json
{
  "name": "discord",
  "requestURL": "WEBHOOK_URL",
  "formData": {
    "username": "ishare",
    "avatar_url": "https://raw.githubusercontent.com/castdrian/ishare/main/ishare/Util/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png"
  },
  "responseURL": "{{attachments[0].url}}"
}
```

### lumen

A binary upload whose link is assembled from several response values.

```json
{
  "name": "lumen",
  "requestURL": "http://localhost:8080/upload",
  "headers": {
    "x-api-key": "API_KEY"
  },
  "requestBodyType": "binary",
  "responseURL": "http://localhost:8080/{{id}}.{{ext}}?key={{key}}&nonce={{nonce}}",
  "deletionURL": "http://localhost:8080/{{id}}.{{ext}}/delete?key={{key}}&nonce={{nonce}}&api_key=API_KEY"
}
```

### Zipline

```json
{
  "name": "zipline",
  "requestURL": "https://your-zipline-host.com/api/upload",
  "headers": {
    "Authorization": "API_KEY"
  },
  "responseURL": "{{files[0].url}}",
  "fileFormName": "file"
}
```

### Zipline with password-protected and expiring links

The same service with a `linkOptions` block that sends a password and an expiry date as headers. See <doc:LinkOptions>.

```json
{
  "name": "zipline-protected",
  "requestURL": "https://your-zipline-host.com/api/upload",
  "headers": {
    "Authorization": "API_KEY"
  },
  "responseURL": "{{files[0].url}}",
  "fileFormName": "file",
  "linkOptions": {
    "password": {
      "field": "x-zipline-password",
      "location": "header"
    },
    "expiry": {
      "field": "x-zipline-deletes-at",
      "location": "header",
      "format": "iso8601",
      "template": "date={{value}}"
    }
  }
}
```

### Zipline behind a CDN with auto-delete

Rewrites every returned link to a CDN host and deletes uploads after 30 days. See <doc:LinkRewritingAndAutoDelete>.

```json
{
  "name": "zipline-cdn",
  "requestURL": "https://your-zipline-host.com/api/upload",
  "headers": {
    "Authorization": "API_KEY"
  },
  "responseURL": "{{files[0].url}}",
  "deletionURL": "{{files[0].removeUrl}}",
  "deleteRequestType": "GET",
  "fileFormName": "file",
  "linkRewrite": {
    "host": "cdn.example.com",
    "scheme": "https",
    "pathPrefix": "/i",
    "stripQuery": true
  },
  "autoDeleteAfterDays": 30
}
```

### Amazon S3

A virtual-hosted bucket with dated keys and public objects. See <doc:S3Uploaders>.

```json
{
  "name": "s3",
  "uploaderType": "s3",
  "s3": {
    "endpoint": "https://s3.us-east-1.amazonaws.com",
    "region": "us-east-1",
    "bucket": "BUCKET_NAME",
    "accessKeyId": "ACCESS_KEY_ID",
    "secretAccessKey": "SECRET_ACCESS_KEY",
    "pathStyle": false,
    "keyTemplate": "{{date}}/{{uuid}}.{{ext}}",
    "acl": "public-read",
    "publicURL": "https://BUCKET_NAME.s3.us-east-1.amazonaws.com/{{key}}"
  }
}
```

### Folder

Copies captures into a dated subfolder of a folder a web server publishes. See <doc:LocalDestinations>.

```json
{
  "name": "folder",
  "uploaderType": "folder",
  "folder": {
    "path": "~/Sites/screenshots",
    "subfolderTemplate": "{{date}}",
    "publicURL": "https://example.com/screenshots/{{path}}"
  }
}
```

### Photos

Adds captures to an album named ishare.

```json
{
  "name": "photos",
  "uploaderType": "photos",
  "photos": {
    "album": "ishare"
  }
}
```

## See Also

- <doc:ISCUFormat>
