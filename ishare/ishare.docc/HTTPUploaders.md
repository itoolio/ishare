# HTTP uploaders

Send captures to any web service that accepts a file and answers with its URL.

## Overview

An HTTP uploader, `"uploaderType": "custom"` or no `uploaderType` at all, describes one request: where to send the file, which headers and form fields to add, and how to find the link in the response.

```json
{
  "name": "My server",
  "requestURL": "https://uploader.example.com/upload",
  "requestMethod": "POST",
  "headers": { "Authorization": "Bearer YOUR_TOKEN" },
  "formData": { "album": "screenshots" },
  "fileFormName": "file",
  "requestBodyType": "multipartFormData",
  "responseURL": "{{files[0].url}}",
  "deletionURL": "{{files[0].deleteUrl}}",
  "deleteRequestType": "DELETE"
}
```

### The request

| Property | Required | Description |
| --- | --- | --- |
| `requestURL` | yes | The http or https URL the file is sent to. Query parameters are kept. |
| `requestMethod` | no | `POST` (default), `PUT` or `PATCH`. |
| `requestBodyType` | no | `multipartFormData` (default) sends a multipart form. `binary` sends the raw file as the body with its MIME type as `Content-Type`. `multipart`, `formdata` and `raw` are accepted as aliases. |

### Headers

`headers` is an object of extra request headers, typically an API key:

```json
"headers": { "Authorization": "Bearer YOUR_TOKEN", "accept": "json" }
```

Every request also carries an `x-file-name` header with the original file name, its extension in lowercase, so services that store files under their sent name can keep it.

### Form fields

`formData` is an object of extra multipart text fields sent before the file. It is only used with a multipart body:

```json
"formData": { "username": "ishare", "album": "screenshots" }
```

### The file field

`fileFormName` names the multipart field that carries the file. It defaults to `file`; some services expect another name, for example copyparty uses `f`. The file is sent with its original name and a MIME type derived from its extension, such as `image/png`, `video/mp4` or `text/plain; charset=utf-8` for text snippets.

### The response

| Property | Required | Description |
| --- | --- | --- |
| `responseURL` | yes | A template that builds the public URL of the upload from the response. See <doc:ResponseTemplates>. |
| `deletionURL` | no | A template that builds a URL deleting the upload. Leave it out when the service has none. |
| `deleteRequestType` | no | `GET` (default) or `DELETE`: the method ishare uses for the deletion URL. The uploader's headers are sent with it. |

Any status code from 200 to 299 is a success. Other status codes fail the upload with the status and the start of the response body; 408, 429 and 5xx responses and network errors are retried later from the upload queue.

### Password-protected and expiring links

Add a `linkOptions` block when the service can protect a link with a password or delete it after a while. See <doc:LinkOptions>.

## See Also

- <doc:ResponseTemplates>
- <doc:LinkOptions>
- <doc:Examples>
