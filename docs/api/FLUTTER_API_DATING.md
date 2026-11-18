# Dating App — Flutter Member API

Hand this file to the **Flutter developer**. It is the member-app contract only.

**Do not call from the Flutter app**

| Path | Why |
|------|-----|
| `/api/v1/admin/**` | Admin panel only |
| `POST /auth/login/2fa` | Staff 2FA only |

Related deep-dives (same repo):

- `backend/docs/CALLS_API.md` — voice/video + Agora
- `backend/docs/STORE_API.md` — coins, gifts, emoji packs
- `backend/docs/SUBSCRIPTIONS_PAYMENTS.md` — Plus / payments
- `web/reference/member-api-contract.md` — full narrative contract

---

## 1. Base URLs

```
{HOST}/api/v1
```

| Environment | Base URL |
|-------------|----------|
| **Production (Render)** | `https://dating-backend-k53l.onrender.com/api/v1` |
| Local | `http://127.0.0.1:5050/api/v1` |

| Service | URL |
|---------|-----|
| REST API | `https://dating-backend-k53l.onrender.com/api/v1` |
| Uploaded images | `https://dating-backend-k53l.onrender.com/uploads/...` (or Cloudinary URLs from upload response) |
| Socket.IO | `wss://dating-backend-k53l.onrender.com` · namespace `/v1` · WebSocket only |

Android emulator → local API: use `http://10.0.2.2:5050/api/v1` (not `127.0.0.1`).

Health check (no auth):

```http
GET https://dating-backend-k53l.onrender.com/api/v1/health
```

---

## 2. Keys, tokens & config (Flutter)

### 2.1 Put these in the Flutter app (safe / client config)

Use `--dart-define`, `.env` + `flutter_dotenv`, or your CI secrets store. **Do not** commit production secrets that belong only on the server.

| Key / value | Example / source | Where used |
|-------------|------------------|------------|
| `API_BASE_URL` | `https://dating-backend-k53l.onrender.com/api/v1` | Dio `baseUrl` |
| `SOCKET_ORIGIN` | `https://dating-backend-k53l.onrender.com` | Socket.IO host (namespace `/v1`) |
| `TERMS_VERSION` | `2026-01` (must match backend `TERMS_VERSION`) | Onboarding `acceptedTermsVersion` |
| `SUPPORT_EMAIL` | From product / `NEXT_PUBLIC_SUPPORT_EMAIL` on web | Help / contact UI |
| **Dev OTP code** | `123456` while backend `OTP_MODE=fixed` | OTP verify screen (dev/test only) |
| **Firebase (FCM)** | `google-services.json` (Android) + `GoogleService-Info.plist` (iOS) from Firebase Console | Push: then send `pushToken` to `POST /devices` |
| **Agora App ID** (optional hardcode) | Same as backend `AGORA_APP_ID` — or use `credentials.appId` from call API | Agora RTC `initialize` / join |
| **Razorpay Key ID** (later, if Web checkout in app) | Backend `RAZORPAY_KEY_ID` (public key id only) | Checkout UI — **never** the secret |
| **Google Sign-In** (later) | Google Cloud OAuth client (iOS/Android) | When `POST /auth/social/google` is live |
| **Apple Sign-In** (later) | Apple Developer Services ID / bundle | When `POST /auth/social/apple` is live |
| **Play / App Store IAP** (later) | Product ids `dc_plus_monthly`, `dc_plus_yearly` + store console | Plus purchases when verify/restore is wired |

**Suggested dart-defines**

```bash
flutter run \
  --dart-define=API_BASE_URL=https://dating-backend-k53l.onrender.com/api/v1 \
  --dart-define=SOCKET_ORIGIN=https://dating-backend-k53l.onrender.com \
  --dart-define=TERMS_VERSION=2026-01
```

Local phone on same Wi‑Fi (backend `HOST=0.0.0.0`):

```bash
--dart-define=API_BASE_URL=http://<YOUR-PC-LAN-IP>:5050/api/v1 \
--dart-define=SOCKET_ORIGIN=http://<YOUR-PC-LAN-IP>:5050
```

### 2.2 Comes from the API (do not hardcode secrets)

| Value | How you get it | Use |
|-------|----------------|-----|
| `accessToken` | Login / OTP verify / refresh | `Authorization: Bearer …` + Socket `auth.token` |
| `refreshToken` | Same | `POST /auth/token/refresh` · logout body |
| `userId` / user summary | Auth `data` | Session, analytics |
| `mediaId` + image URL | `POST /media/upload` | Profile / chat / verification |
| Agora `appId`, `channelName`, `token`, `uid`, `expiresAt` | `POST /calls` or `POST /calls/:id/accept` → `data.credentials` | Join Agora channel |
| Store / subscription checkout ids | `/store/checkout`, `/subscriptions/checkout` | Verify purchase |
| Idempotency UUID | Client-generated (`uuid` package) | Header `Idempotency-Key` (+ message `clientMessageId`) |

Store tokens in **`flutter_secure_storage`**, not `SharedPreferences`.

### 2.3 Server-only — NEVER put in the Flutter app

These live only in `backend/.env` / Render. Shipping them = account takeover / bill fraud.

| Secret | Why server-only |
|--------|-----------------|
| `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` | Signs all member tokens |
| `AGORA_APP_CERTIFICATE` | Used to mint call tokens on server |
| `CLOUDINARY_API_KEY` / `CLOUDINARY_API_SECRET` | Media upload on server |
| `RAZORPAY_KEY_SECRET` / `RAZORPAY_WEBHOOK_SECRET` | Payments |
| `MONGODB_URI` | Database |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Admin seed |
| `DEMO_WEBHOOK_SECRET` | Demo payment webhooks |
| SMS provider keys (when `OTP_MODE=sms`) | OTP delivery |

### 2.4 Quick map: who owns what

```
Flutter app
  ├── API_BASE_URL, SOCKET_ORIGIN, TERMS_VERSION
  ├── Firebase config files → FCM pushToken → POST /devices
  ├── accessToken / refreshToken (from API, secure storage)
  ├── Agora join params (from /calls credentials)
  └── (later) Razorpay Key ID / Google / Apple client IDs / IAP product ids

Backend only
  ├── JWT secrets, MongoDB, Cloudinary secret
  ├── Agora App Certificate → issues RTC tokens
  └── Razorpay secret / webhooks / SMS
```

Ask the backend owner for: current **Agora App ID** (if you init SDK before first call), **Firebase project** invite / config files, and **Razorpay Key ID** when payments go live. They will **not** give you certificate / JWT / Cloudinary / Razorpay secrets.

---

## 3. Recommended Flutter packages

| Purpose | Package |
|---------|---------|
| HTTP | `dio` |
| Secure tokens | `flutter_secure_storage` |
| UUID (idempotency) | `uuid` |
| Socket.IO | `socket_io_client` |
| Push | `firebase_messaging` (FCM) |
| Voice/video | Agora RTC SDK (see Calls doc) |
| In-app purchase | `in_app_purchase` (when store verify is live) |

---

## 4. Headers & auth

| Header | When | Example |
|--------|------|---------|
| `Content-Type` | JSON bodies | `application/json` |
| `Authorization` | All protected routes | `Bearer <accessToken>` |
| `Idempotency-Key` | Swipes + send message | UUID string |

### Auth flow

1. Sign in (OTP, email/password, or social when enabled).
2. Store `accessToken` + `refreshToken` in **secure storage**.
3. Send `Authorization: Bearer <accessToken>` on protected calls.
4. On `401` → `POST /auth/token/refresh` with `refreshToken` → save both new tokens → retry once.
5. Logout → `POST /auth/logout` (or `/auth/logout-all`) → clear storage → disconnect socket.

### Dio sketch (token + refresh)

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://dating-backend-k53l.onrender.com/api/v1',
  headers: {'Content-Type': 'application/json'},
  validateStatus: (s) => s != null && s < 500, // handle 4xx yourself
));

dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) async {
    final token = await secureStorage.read(key: 'accessToken');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  },
  onError: (err, handler) async {
    if (err.response?.statusCode == 401) {
      // refresh once, update storage, clone & retry request
    }
    handler.next(err);
  },
));
```

---

## 5. Response envelope

**Success**

```json
{
  "success": true,
  "data": {},
  "meta": { "requestId": "req_xxx" }
}
```

**Error**

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable message",
    "details": [{ "field": "email", "reason": "REQUIRED" }]
  },
  "meta": { "requestId": "req_xxx" }
}
```

Always check `success`, then read `data` or `error`.

### Common error codes

| Code | HTTP | When |
|------|------|------|
| `VALIDATION_ERROR` | 400 | Bad / missing fields |
| `OTP_INVALID` / `OTP_EXPIRED` | 400 | OTP issues |
| `UNAUTHENTICATED` | 401 | Refresh token |
| `FORBIDDEN` | 403 | Not allowed |
| `ACCOUNT_INELIGIBLE` | 403 | Suspended / banned / deleted |
| `USER_BLOCKED` | 403 | Block relationship |
| `MATCH_REQUIRED` | 403 | Match / conversation invalid |
| `SUBSCRIPTION_REQUIRED` | 403 | Plus feature |
| `NOT_FOUND` | 404 | Missing / hidden |
| `CONFLICT` | 409 | Duplicate / idempotency / call state |
| `MEDIA_REJECTED` | 422 | Photo rejected |
| `RATE_LIMITED` | 429 | Respect `Retry-After` |
| `SERVER_ERROR` | 500 | Unexpected |
| `FEATURE_NOT_CONFIGURED` | 501 | Social login / real SMS / IAP not wired |

### Pagination

| Query | Default | Notes |
|-------|---------|-------|
| `cursor` | — | From previous `nextCursor` |
| `limit` | `20` | Max `50` (messages default `50`) |

### Idempotency

For `POST /swipes` and `POST /conversations/:id/messages`:

1. Generate a UUID once per logical action.
2. Send header `Idempotency-Key: <uuid>`.
3. For messages, body `clientMessageId` **must equal** that UUID.
4. Retry with the same key after network failure — safe.

---

## 6. Typical app flows

### A. First-time OTP user

1. `POST /auth/otp/request` — E.164 phone (`+919876543210`)
2. `POST /auth/otp/verify` — code (**dev: `123456`**, `OTP_MODE=fixed`)
3. Save tokens
4. Upload 2–6 photos → `POST /media/upload` (`purpose=PROFILE_PHOTO`)
5. `POST /profile/onboarding` with `photoMediaIds`
6. `GET /discovery` → swipe
7. On match → chat (+ Socket.IO)

### B. Email register / login

1. `POST /auth/register` or `POST /auth/login`
2. Same onboarding / discovery if profile incomplete

### C. Returning user

1. Use stored `accessToken`
2. If expired → refresh
3. `GET /profile/me`, discovery, matches, conversations

### D. Send chat message

1. Optional: upload attachment (`purpose=CHAT_ATTACHMENT`)
2. `POST /conversations/:id/messages` with matching `Idempotency-Key` + `clientMessageId`

### E. Buy Plus (demo)

1. `GET /subscriptions/products`
2. `POST /subscriptions/checkout` — `platform`: `IOS` \| `ANDROID` \| `WEB`
3. `POST /subscriptions/verify` with `checkoutId` + `providerProof.outcome` (`SUCCESS` / `FAILURE` in demo)
4. `GET /subscriptions/entitlement` or listen `entitlement:updated`

---

## 7. Auth endpoints

| Method | Path | Auth | Body / notes |
|--------|------|------|--------------|
| POST | `/auth/otp/request` | No | `{ "phoneNumber": "+91..." }` |
| POST | `/auth/otp/verify` | No | `{ "phoneNumber", "code" }` → tokens |
| POST | `/auth/token/refresh` | No | `{ "refreshToken" }` → new pair |
| POST | `/auth/logout` | Yes | `{ "refreshToken" }` |
| POST | `/auth/logout-all` | Yes | All devices |
| POST | `/auth/register` | No | email, password (10–128), displayName, dateOfBirth, acceptedTermsVersion |
| POST | `/auth/login` | No | `{ "email", "password" }` |
| POST | `/auth/social/:provider` | No | `apple` \| `google` — **501 until configured** |

---

## 8. Profile & media

| Method | Path | Notes |
|--------|------|-------|
| GET | `/profile/me` | Own profile |
| PATCH | `/profile/me` | Partial: displayName, bio, interests, city, occupation |
| POST | `/profile/onboarding` | Once; see enums below |
| PUT | `/profile/preferences` | minAge, maxAge, maxDistanceKm, showMe |
| PUT | `/profile/interests` | `{ "interestIds": [...] }` (1–10) |
| POST | `/profile/photos` | `{ "mediaId" }` |
| PATCH | `/profile/photos/order` | `{ "photoIds": [...] }` |
| DELETE | `/profile/photos/:photoId` | |
| POST | `/profile/verification` | `{ "selfieMediaId" }` after upload |
| GET | `/profiles/:userId` | Public profile |
| GET | `/interests` | Catalogue |
| GET | `/profile/login-activity` | Own login history |
| POST | `/media/upload` | Multipart (below) |
| GET | `/media/:mediaId` | Metadata |

### Onboarding enums

| Field | Values |
|-------|--------|
| `gender` | `WOMAN`, `MAN`, `NON_BINARY` |
| `showMe` | `WOMEN`, `MEN`, `EVERYONE` |
| `relationshipGoal` | `LONG_TERM`, `LONG_TERM_OPEN_TO_SHORT`, `SHORT_TERM_OPEN_TO_LONG`, `SHORT_TERM_FUN`, `NEW_FRIENDS`, `STILL_FIGURING_OUT` |

Rules: `interestIds` 1–10 · `photoMediaIds` 2–6 · `maxDistanceKm` 1–500 · `bio` max 500.

### Multipart upload (Dio)

```dart
final form = FormData.fromMap({
  'purpose': 'PROFILE_PHOTO', // or VERIFICATION_SELFIE | CHAT_ATTACHMENT
  'file': await MultipartFile.fromFile(path, filename: 'photo.jpg'),
});

final res = await dio.post(
  '/media/upload',
  data: form,
  options: Options(contentType: 'multipart/form-data'),
);
// use res.data['data']['mediaId'] and URL from response
```

Rate limit: **30 uploads / hour**.

---

## 9. Discovery, likes, matches

| Method | Path | Notes |
|--------|------|-------|
| GET | `/discovery` | Optional query: `minAge`, `maxAge`, `distanceKm` |
| POST | `/swipes` | **Idempotency-Key** required. Body: `{ "targetUserId", "action" }` — `LIKE` \| `PASS` \| `SUPER_LIKE` |
| POST | `/swipes/undo` | **Plus** feature |
| GET | `/likes/received` | Full list **Plus**; free → count |
| GET | `/likes/sent` | Outgoing pending |
| GET | `/matches` | Paginated |
| GET | `/matches/:matchId` | |
| POST | `/matches/:matchId/unmatch` | |

---

## 10. Chat

| Method | Path | Notes |
|--------|------|-------|
| GET | `/conversations` | List |
| GET | `/conversations/:id` | Header |
| DELETE | `/conversations/:id` | Hide for me |
| GET | `/conversations/:id/messages` | `cursor`, `limit` ≤ 50 |
| POST | `/conversations/:id/messages` | See body below |
| POST | `/messages/:id/read` | Mark read up to message |
| DELETE | `/messages/:id` | Hide for me |
| POST | `/messages/:id/unsend` | Sender unsends for both |
| POST | `/messages/:id/report` | Same report quota as `/reports` |

**Send message**

```json
{
  "text": "Hello!",
  "attachmentMediaId": "med_xxx",
  "clientMessageId": "550e8400-e29b-41d4-a716-446655440000"
}
```

- Need `text` and/or `attachmentMediaId`
- Header `Idempotency-Key` **==** `clientMessageId`
- Limits: 30/min per conversation · 300/hour per user

---

## 11. Calls (Agora)

Full detail: `backend/docs/CALLS_API.md`.

| Method | Path | Notes |
|--------|------|-------|
| POST | `/calls` | `{ "conversationId", "type": "AUDIO"|"VIDEO" }` → call + Agora credentials |
| GET | `/calls/active` | Current ringing/accepted call |
| GET | `/calls` | History |
| POST | `/calls/:callId/accept` | Callee → credentials |
| POST | `/calls/:callId/reject` | Callee |
| POST | `/calls/:callId/cancel` | Caller |
| POST | `/calls/:callId/end` | Either party |
| POST | `/calls/:callId/gifts` | Send gift during call |

**Never** put `AGORA_APP_CERTIFICATE` in the app. Join with `appId`, `channelName`, `token`, `uid` from API.

Socket events (examples): `call:incoming`, `call:accepted`, `call:rejected`, `call:cancelled`, `call:ended`, `call:missed`, `call:busy`.

---

## 12. Store (coins / gifts / emoji)

Full detail: `backend/docs/STORE_API.md`.

| Method | Path | Notes |
|--------|------|-------|
| GET | `/store/catalog` | Items |
| GET | `/store/wallet` | Coin balance + owned packs |
| GET | `/store/history` | Purchases |
| POST | `/store/checkout` | Coin pack (money) |
| POST | `/store/verify` | After payment / demo |
| POST | `/store/buy-with-coins` | Emoji pack or gift |

---

## 13. Subscriptions

| Method | Path | Notes |
|--------|------|-------|
| GET | `/subscriptions/products` | Paywall UI |
| GET | `/subscriptions/entitlement` | Current tier |
| GET | `/subscriptions/history` | |
| POST | `/subscriptions/checkout` | `{ "productId", "platform": "IOS"|"ANDROID"|"WEB" }` |
| POST | `/subscriptions/verify` | `{ "checkoutId", "providerProof" }` |
| POST | `/subscriptions/restore` | Store restore (may be 501 until wired) |
| POST | `/subscriptions/cancel` | Cancel |

Known products: `dc_plus_monthly`, `dc_plus_yearly`.

---

## 14. Safety, notifications, support

### Safety

| Method | Path | Notes |
|--------|------|-------|
| POST | `/users/:userId/block` | Idempotent |
| DELETE | `/users/:userId/block` | |
| GET | `/blocks` | |
| POST | `/reports` | 20/day |

Report body:

```json
{
  "targetType": "USER",
  "targetId": "usr_xxx",
  "reason": "FAKE_PROFILE",
  "details": "optional",
  "alsoBlock": true
}
```

`targetType`: `USER` \| `PHOTO`  
Reasons: `FAKE_PROFILE`, `INAPPROPRIATE_PHOTOS`, `HARASSMENT`, `SPAM_OR_SCAM`, `UNDERAGE`, `OFFLINE_BEHAVIOUR`, `OTHER`

### Devices & notifications

| Method | Path | Notes |
|--------|------|-------|
| POST | `/devices` | `{ "platform": "IOS"|"ANDROID", "pushToken", "appVersion", "locale" }` |
| DELETE | `/devices/:deviceId` | On logout |
| GET | `/notifications` | Inbox |
| POST | `/notifications/:id/read` | |
| GET | `/notification-preferences` | |
| PATCH | `/notification-preferences` | Partial: newMatches, messages, likes, promotions |

### Support & account

| Method | Path | Notes |
|--------|------|-------|
| GET | `/support/faqs` | Public |
| POST | `/support/tickets` | 5/day — category, subject, message |
| GET | `/support/tickets/:ticketId` | Own tickets |
| POST | `/account/deletion-request` | `{ "confirm": true }` → **202** |
| GET | `/account/export-status` | |

Ticket categories: `ACCOUNT`, `BILLING`, `SAFETY`, `BUG`, `OTHER`.

---

## 15. Socket.IO (Flutter)

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io(
  'https://dating-backend-k53l.onrender.com/v1',
  IO.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': accessToken})
      .disableAutoConnect()
      .build(),
);

socket.connect();

socket.on('message:new', (data) { /* update chat */ });
socket.on('match:new', (data) { /* show match UI */ });
socket.on('session:expired', (_) async {
  // refresh REST token, then reconnect socket with new token
});
socket.on('entitlement:updated', (data) { /* refresh Plus UI */ });
```

| Direction | Event | Payload / meaning |
|-----------|-------|-------------------|
| Client → | `typing` | `{ conversationId, isTyping }` |
| Client → | `message:read` | `{ conversationId, upToMessageId }` |
| Server → | `message:new` | New chat message |
| Server → | `message:read` | Read receipt |
| Server → | `typing` | Other user typing |
| Server → | `match:new` / `match:removed` | Match lifecycle |
| Server → | `entitlement:updated` | Subscription changed |
| Server → | `session:expired` | Refresh token + reconnect |
| Server → | `call:*` | See Calls API |

REST is source of truth — on reconnect, refetch conversations / matches if needed.

---

## 16. Quick reference (all member routes)

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | No |
| POST | `/auth/otp/request` | No |
| POST | `/auth/otp/verify` | No |
| POST | `/auth/token/refresh` | No |
| POST | `/auth/logout` | Yes |
| POST | `/auth/logout-all` | Yes |
| POST | `/auth/register` | No |
| POST | `/auth/login` | No |
| POST | `/auth/social/:provider` | No |
| GET/PATCH | `/profile/me` | Yes |
| POST | `/profile/onboarding` | Yes |
| PUT | `/profile/preferences` | Yes |
| PUT | `/profile/interests` | Yes |
| POST/PATCH/DELETE | `/profile/photos...` | Yes |
| POST | `/profile/verification` | Yes |
| GET | `/profiles/:userId` | Yes |
| GET | `/interests` | Yes |
| POST | `/media/upload` | Yes |
| GET | `/media/:mediaId` | Yes |
| GET | `/discovery` | Yes |
| POST | `/swipes` | Yes |
| POST | `/swipes/undo` | Yes |
| GET | `/likes/received` · `/likes/sent` | Yes |
| GET/POST | `/matches...` | Yes |
| GET/DELETE/POST | `/conversations...` · `/messages...` | Yes |
| POST/GET | `/calls...` | Yes |
| GET/POST | `/store/...` | Yes |
| GET/POST | `/subscriptions/...` | Yes |
| POST/DELETE/GET | `/users/.../block` · `/blocks` · `/reports` | Yes |
| POST/DELETE | `/devices...` | Yes |
| GET/POST/PATCH | `/notifications...` · `/notification-preferences` | Yes |
| GET/POST | `/support/...` · `/account/...` | Mixed |

---

## 17. Flutter checklist before first build

- [ ] `API_BASE_URL` + `SOCKET_ORIGIN` + `TERMS_VERSION` via `--dart-define` / env
- [ ] No server secrets in the app (JWT, Agora certificate, Cloudinary, Razorpay secret)
- [ ] Secure storage for tokens; clear on logout
- [ ] Dio interceptor: Bearer + single-flight refresh
- [ ] Parse `success` / `error.code` (not only HTTP status)
- [ ] UUID idempotency on swipe + send message
- [ ] Multipart upload with correct `purpose`
- [ ] Socket connect after login; reconnect after token refresh
- [ ] Firebase config + register FCM device after login (`POST /devices`)
- [ ] Android cleartext / network security for local HTTP if needed
- [ ] Agora join only with server-issued credentials (`appId`/`token`/`uid` from API)
- [ ] Never call `/admin/**`

---

*Generated for Flutter member app handoff. For request/response field details beyond this sheet, use the related docs listed at the top.*
