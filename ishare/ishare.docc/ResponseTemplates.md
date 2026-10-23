# Response templates

Build the shared link and the deletion URL from the service's response.

## Overview

`responseURL` and `deletionURL` are templates. Text outside double braces is copied as is, and every `{{placeholder}}` is replaced with a value from the response body. `ResponseTemplate` renders them after a successful upload.

### JSON paths

A placeholder names a path into a JSON response. Object keys are separated by dots and array elements are addressed by index:

| Response | Template | Result |
| --- | --- | --- |
| `{"url": "https://i.example.com/a.png"}` | `{{url}}` | `https://i.example.com/a.png` |
| `{"data": {"link": "https://i.example.com/a.png"}}` | `{{data.link}}` | `https://i.example.com/a.png` |
| `{"files": [{"url": "https://i.example.com/a.png"}]}` | `{{files[0].url}}` | `https://i.example.com/a.png` |
| `{"id": "a1b2", "ext": "png"}` | `https://cdn.example.com/{{id}}.{{ext}}` | `https://cdn.example.com/a1b2.png` |

`{{files.0.url}}` is the same path as `{{files[0].url}}`. Strings, numbers and booleans are inserted as text; objects and arrays are inserted as compact JSON. Whitespace inside the braces is ignored.

### Plain-text responses

Some services answer with the URL itself instead of JSON. Use `{{response}}`, or its alias `{{body}}`, to insert the whole response body with surrounding whitespace removed:

```json
"responseURL": "{{response}}"
```

### Missing values

When a placeholder in `responseURL` doesn't exist in the response, the upload fails with "Couldn't read the upload URL from the response" and the name of the missing path, and the response is shown in **Test Upload** so you can correct the template. The rendered URL must have a scheme such as `https`. A `deletionURL` that can't be rendered is skipped and the upload still succeeds.

### Templates in other properties

Templates appear in a few other places, each with its own placeholders:

- `linkOptions` templates wrap the password or expiry value with `{{value}}`. See <doc:LinkOptions>.
- S3 key templates and public URL templates use file and object placeholders such as `{{uuid}}` and `{{key}}`. See <doc:S3Uploaders>.
- Folder subfolder and public URL templates use the same file placeholders plus `{{path}}`. See <doc:LocalDestinations>.

## See Also

- <doc:HTTPUploaders>
