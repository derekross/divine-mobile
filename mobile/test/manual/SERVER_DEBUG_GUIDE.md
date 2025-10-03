# Server Debug Guide: Blossom Upload 502 Error

## Issue Summary
The `/upload` endpoint at `cf-stream-service-prod.protestnet.workers.dev` is returning **502 Bad Gateway** with `{"error":"stream_error","status":400}`.

## What's Working (Client Side) ✅
1. **Auth event creation**: Kind 24242 with proper tags `["t", "upload"]`, `["expiration", "<timestamp>"]`
2. **Request format**: PUT with raw bytes, proper headers
3. **Race condition**: Fixed - upload completes before publishing starts
4. **Response handling**: Ready to parse `{sha256, url, size, type}` response

## What's Failing (Server Side) ❌
**Error**: `502 Bad Gateway` with body `{"error":"stream_error","status":400}`

This indicates the Cloudflare Worker **cannot connect to Cloudflare Stream API**.

## Request Details

### Endpoint
```
PUT https://cf-stream-service-prod.protestnet.workers.dev/upload
```

### Headers
```
Authorization: Nostr <base64-encoded-event>
Content-Type: video/mp4
Content-Length: 1016
```

### Auth Event Structure (Base64 Decoded)
```json
{
  "kind": 24242,
  "created_at": 1759469858,
  "pubkey": "0000000000000000000000000000000000000000000000000000000000000000",
  "tags": [
    ["t", "upload"],
    ["expiration", "1759470158"]
  ],
  "content": "Test Blossom upload",
  "id": "0000000000000000000000000000000000000000000000000000000000000000",
  "sig": "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
}
```

### Body
Raw bytes (1016 bytes): MP4 file header + test data
- SHA256: `b19dc4deee058d6afdfa4b6c7ea7c30bb42a2e3fa654d31cfd03e4dd98e30c3c`

### Response
```
Status: 502 Bad Gateway
Body: {"error":"stream_error","status":400}
```

## Expected Flow (What SHOULD Happen)

### Step 1: Worker Receives PUT /upload
```javascript
// Worker receives request
const authHeader = request.headers.get('Authorization');
const [scheme, base64Event] = authHeader.split(' ');
const authEvent = JSON.parse(atob(base64Event));

// Verify:
// 1. authEvent.kind === 24242
// 2. authEvent.tags includes ["t", "upload"]
// 3. created_at is in past
// 4. expiration is in future
```

### Step 2: Worker Calls Cloudflare Stream API
**THIS IS WHERE IT'S FAILING**

The worker should:
```javascript
// Upload to Cloudflare Stream
const streamResponse = await fetch(
  `https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/stream`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${STREAM_API_TOKEN}`,
      'Content-Type': 'video/mp4'
    },
    body: videoBytes
  }
);
```

**Error suggests:**
- Missing/invalid `STREAM_API_TOKEN` environment variable
- Wrong `ACCOUNT_ID`
- Network timeout to Cloudflare Stream API
- Stream API quota exceeded

### Step 3: Worker Returns Blossom Response
After successful Stream upload, worker should return:
```json
{
  "sha256": "b19dc4deee058d6afdfa4b6c7ea7c30bb42a2e3fa654d31cfd03e4dd98e30c3c",
  "url": "https://cdn.divine.video/b19dc4deee058d6afdfa4b6c7ea7c30bb42a2e3fa654d31cfd03e4dd98e30c3c",
  "size": 1016,
  "type": "video/mp4",
  "uploaded": 1759469858
}
```

## What to Check on Server

### 1. Environment Variables
```bash
# Check these are set in wrangler.toml or dashboard:
CLOUDFLARE_ACCOUNT_ID=<your-account-id>
CLOUDFLARE_STREAM_API_TOKEN=<your-stream-token>

# Or check in worker code:
console.log('Account ID:', env.CLOUDFLARE_ACCOUNT_ID);
console.log('Stream token exists:', !!env.CLOUDFLARE_STREAM_API_TOKEN);
```

### 2. Stream API Endpoint
Verify the worker is calling:
```
POST https://api.cloudflare.com/client/v4/accounts/{account_id}/stream
```

### 3. Error Logging
Add detailed logging:
```javascript
try {
  const streamResponse = await fetch(streamUrl, options);
  console.log('Stream API status:', streamResponse.status);
  console.log('Stream API response:', await streamResponse.text());
} catch (error) {
  console.error('Stream API error:', error);
  console.error('Error details:', {
    message: error.message,
    stack: error.stack
  });
}
```

### 4. Authentication Check
The error might be from auth verification. Check:
```javascript
// Does worker verify the Nostr signature?
// Does it allow dummy/test pubkeys for testing?
// Is auth.pubkey being accessed when auth is null/undefined?
```

From your earlier note:
> "The problem was auth.pubkey being used without null checking. When auth failed, it would crash trying to access .pubkey on null."

**This might be the issue!** The test uses a dummy pubkey/signature. If the worker crashes on auth, it might return 502.

### 5. Worker Logs
Check Cloudflare Worker logs:
```bash
wrangler tail cf-stream-service-prod
```

Then run the test again:
```bash
dart run test/manual/test_blossom_upload_live.dart
```

Look for:
- JavaScript errors/exceptions
- "stream_error" message origin
- Auth verification failures
- Stream API call failures

## Quick Fixes to Try

### Fix 1: Allow Anonymous Uploads
```javascript
// In upload handler
const auth = await verifyAuth(request);
const pubkey = auth?.pubkey || 'anonymous';  // ✅ Safe null handling

// Don't crash on invalid auth for testing
if (!auth && REQUIRE_AUTH) {
  return new Response(JSON.stringify({
    error: 'auth_required',
    message: 'Valid Nostr signature required'
  }), { status: 401 });
}
```

### Fix 2: Better Error Response
```javascript
try {
  const streamResponse = await fetch(streamUrl, options);

  if (!streamResponse.ok) {
    const errorText = await streamResponse.text();
    return new Response(JSON.stringify({
      error: 'stream_error',
      status: streamResponse.status,
      details: errorText,  // ✅ Include actual error
      stream_endpoint: streamUrl
    }), { status: 502 });
  }
} catch (error) {
  return new Response(JSON.stringify({
    error: 'stream_error',
    message: error.message,  // ✅ Include error message
    stack: error.stack  // ✅ Include stack trace
  }), { status: 502 });
}
```

### Fix 3: Check Stream Token
```javascript
if (!env.CLOUDFLARE_STREAM_API_TOKEN) {
  return new Response(JSON.stringify({
    error: 'config_error',
    message: 'CLOUDFLARE_STREAM_API_TOKEN not configured'
  }), { status: 500 });
}
```

## Test Commands

### Test Upload Endpoint
```bash
dart run test/manual/test_blossom_upload_live.dart
```

### Test With Real Nostr Keys (if you have them)
Update the test with real signature and try again.

### Check Server Response Time
```bash
curl -w "\nTime: %{time_total}s\n" \
  -X PUT \
  -H "Authorization: Nostr eyJraW5kIjoyNDI0Mn0=" \
  -H "Content-Type: video/mp4" \
  --data-binary @test.mp4 \
  https://cf-stream-service-prod.protestnet.workers.dev/upload
```

## Expected Working Flow

Once fixed, the flow should be:

1. ✅ Client sends PUT /upload with Nostr auth + video bytes
2. ✅ Worker verifies auth (or allows anonymous)
3. ✅ Worker uploads to Cloudflare Stream
4. ✅ Worker gets Stream response with UID
5. ✅ Worker returns Blossom response:
   ```json
   {
     "sha256": "<hash>",
     "url": "https://cdn.divine.video/<hash>",
     "size": <bytes>,
     "type": "video/mp4"
   }
   ```
6. ✅ Client receives response and publishes Nostr event with cdn.divine.video URL

## What Client Is Ready For

The Flutter client will correctly handle any of these responses:

- **200/201 with Blossom response**: Parses and uses cdn.divine.video URL ✅
- **409 Conflict**: Assumes file exists, constructs cdn.divine.video URL ✅
- **401 Unauthorized**: Shows auth error to user ✅
- **502/500 Server Error**: Shows server error to user ✅

The race condition is fixed, so publishing will work once the upload returns a valid response.
