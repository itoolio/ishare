# Password-protected and expiring links

Let people pick a password and an expiry for each upload to services that support them.

## Overview

The optional `linkOptions` block of an HTTP uploader tells ishare how the service expects a link password and an expiry. ishare then offers both in the uploader editor, where you set the defaults, and, with **Ask every time**, in a prompt before every upload to that uploader. The default password is stored in the Keychain, never in the `.iscu` file.

```json
"linkOptions": {
  "password": { "field": "x-zipline-password", "location": "header" },
  "expiry": {
    "field": "x-zipline-deletes-at",
    "location": "header",
    "format": "iso8601",
    "template": "date={{value}}"
  }
}
```

Either `password` or `expiry` can be left out, but not both. Nothing is sent for a part you don't use: an upload without a password sends no password field, and links that never expire send no expiry.

### Password

| Property | Required | Description |
| --- | --- | --- |
| `field` | yes | Name of the form field, header or query parameter. |
| `location` | no | `form` (default), `header` or `query`. |
| `template` | no | Wraps the password, for example `Bearer {{value}}`. Must contain `{{value}}`. |

### Expiry

| Property | Required | Description |
| --- | --- | --- |
| `field` | yes | Name of the form field, header or query parameter. |
| `location` | no | `form` (default), `header` or `query`. |
| `format` | no | How the expiry is written, see below. |
| `template` | no | Wraps the value, for example `date={{value}}` or `{{value}}m`. Must contain `{{value}}`. |

The `format` decides the value that replaces `{{value}}`:

| `format` | Aliases | Value for a link that expires in one hour |
| --- | --- | --- |
| `seconds` (default) | `s` | `3600` |
| `minutes` | `m` | `60`, rounded up |
| `iso8601` | `iso`, `date` | the UTC date, for example `2026-10-23T13:00:00Z` |
| `timestamp` | `unix`, `epoch` | Unix seconds, for example `1792760400` |

### Locations

- `form` adds a multipart text field. It requires `"requestBodyType": "multipartFormData"`, the default; validation rejects it with a binary body. `formdata`, `multipart` and `body` are accepted as aliases.
- `header` adds a request header. `headers` is an alias.
- `query` appends a query parameter to `requestURL`. `querystring` and `url` are aliases.

## See Also

- <doc:HTTPUploaders>
- <doc:Examples>
