# Task 13 upload and authentication cases

Run with a local HTTP fixture server after app runtime testing is authorized. These cases describe expected browser behavior; this source-only packet does not start the server or inspect credentials.

| Case | Fixture | Expected result |
| --- | --- | --- |
| Single upload | Page with `<input type="file">` | One selected file reaches the requesting page. Cancel returns no selection. |
| Multiple upload | Page with `<input type="file" multiple>` | The native chooser honors the page's multiple-selection request. |
| Page lifetime | Select an external file, then navigate or close before using it | A stale chooser cannot return URLs; any scope acquired by Astra is released on provisional navigation or close. |
| Native mobile upload | Image input with `accept="image/*"` and `capture`, plus drag/drop | WebKit and the OS provide the native photo/camera and drag/drop flow. Astra does not replace it with a document-only picker. |
| Basic and Digest | HTTP and HTTPS endpoints returning Basic or Digest challenges with distinct realms | Prompt identifies host, non-default port and realm; HTTPS is identified as encrypted; HTTP warns that credentials may be exposed. |
| Retry limit | Endpoint rejects credentials repeatedly | Credentials may be submitted while `previousFailureCount` is below three; the next challenge is canceled without another prompt. |
| Native trust and client certificate | Valid/invalid server certificate and a client-certificate endpoint | Server trust follows WebKit default handling. Client certificate follows native handling until identity selection and provider behavior are established. |
| Download challenge | Protected response promoted to `WKDownload` | Uses the same serialized presenter and challenge policy as page navigation; closing/removing the download cancels its prompt once. |
