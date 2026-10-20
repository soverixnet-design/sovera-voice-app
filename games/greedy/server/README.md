# Greedy গেম সার্ভার — আসল ফলাফল ও কয়েন

এই সার্ভার রাউন্ড চালায়, ফলাফল ঠিক করে, বেটের কয়েন কাটে আর জয়ের কয়েন দেয়। ফোনের গেম শুধু দেখায়, তাই কেউ অ্যাপের কোড বদলে কয়েন বাড়াতে পারবে না।

```
তোমার অ্যাপ (ভয়েস রুম)                Greedy সার্ভার                 তোমার অ্যাপের সার্ভার
 WebView: index.html?server=..&token=JWT ──WebSocket /ws──►  রাউন্ড, ফলাফল, বেট  ──HTTP──►  /balance  /debit  /credit
                                                             (SQLite: রাউন্ড, বেট, পেমেন্ট)   (ইউজারের আসল কয়েন)
```

## চালানো
```bash
npm install
cp .env.example .env      # তারপর .env খুলে সব change-me বদলাও
npm start                 # পোর্ট 8080
```
দরকার Node.js 18 বা নতুন। সার্ভার চালু রাখতে `pm2 start src/server.js --name greedy` ব্যবহার করো, আর সামনে Nginx দিয়ে HTTPS দাও (WebSocket-এর জন্য `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";`)।

`CLIENT_DIR=../client` দিলে এই সার্ভারই গেমের ফাইলও দেয়: `https://game.your-app.com/?token=JWT&sheet=1`।

## ধাপ ১ — ইউজার পরিচয় (JWT)
তোমার অ্যাপের সার্ভার প্রতিটি ইউজারের জন্য একটা টোকেন বানাবে (HS256, গোপন কী `GAME_JWT_SECRET`), তারপর গেমের লিংকে `token=` দিয়ে পাঠাবে।
টোকেনের ভেতরে: `{ "uid": "ইউজার আইডি", "name": "নাম", "avatar": "ছবির লিংক", "exp": মেয়াদ (unix সেকেন্ড) }`

PHP (firebase/php-jwt):
```php
$token = \Firebase\JWT\JWT::encode(['uid'=>(string)$user->id,'name'=>$user->name,'avatar'=>$user->avatar,'exp'=>time()+43200], GAME_JWT_SECRET, 'HS256');
```
Node (jsonwebtoken):
```js
const token = jwt.sign({ uid: String(user.id), name: user.name, avatar: user.avatar }, GAME_JWT_SECRET, { algorithm: 'HS256', expiresIn: '12h' });
```
পরীক্ষার জন্য: `node tools/make-token.js 1001 Rasel`

## ধাপ ২ — ওয়ালেট API (তোমার অ্যাপে বানাতে হবে)
`.env`-এ `WALLET_MODE=http` আর `WALLET_URL=https://api.your-app.com/greedy-wallet` দাও। গেম সার্ভার এই তিনটা POST কল করবে:

| পথ | পাঠায় | ফেরত দিতে হবে |
|---|---|---|
| `/balance` | `{ userId }` | `{ ok:true, balance }` |
| `/debit` | `{ txId, userId, amount, roundId, itemId }` | `{ ok:true, balance }` অথবা কয়েন কম হলে `{ ok:false, error:"INSUFFICIENT_BALANCE", balance }` |
| `/credit` | `{ txId, userId, amount, roundId, reason:"win" বা "refund", refundOf? }` | `{ ok:true, balance }` |

জরুরি নিয়ম:
1. **স্বাক্ষর যাচাই:** হেডার `X-Greedy-Timestamp` আর `X-Greedy-Signature` = `hex(HMAC_SHA256(WALLET_SECRET, timestamp + "." + body))`। না মিললে ৪০১। ৬০ সেকেন্ডের বেশি পুরনো হলে বাতিল।
2. **একই txId দুইবার এলে একবারই কাজ করবে** (txId কলামে UNIQUE দাও) এবং আগের ব্যালান্স ফেরত দেবে। নেটওয়ার্ক সমস্যায় সার্ভার আবার চেষ্টা করে, তাই এটা না করলে কয়েন দুইবার কাটা বা দেওয়া হবে।
3. **refund:** `refundOf`-এ যে debit txId আছে সেটা আসলে কাটা হয়ে থাকলেই ফেরত দাও, না হলে শুধু `ok:true` আর বর্তমান ব্যালান্স।
4. ৫০০+ স্ট্যাটাস বা টাইমআউট হলে সার্ভার ধরে নেয় কাজ হয়নি এবং পরে আবার চেষ্টা করে।

পুরো উদাহরণ: `tools/mock-app-wallet.js` (চালাও `WALLET_SECRET=xxx npm run mock-wallet`)। এটাকে তোমার ডাটাবেস দিয়ে বদলালেই হবে।

## রাউন্ড ও ফলাফল
- বেট ৩০ সেকেন্ড → ঘোরা ৬ সেকেন্ড → ফলাফল ৫ সেকেন্ড (`.env`-এ বদলানো যায়)।
- ১০টা ফলাফল: ৮টা খাবার + **সালাদ** (চার সবজির সব বেট ×5 জেতে) + **পিৎজা** (চার মাংসের সব বেট নিজের গুণে জেতে: ×10, ×15, ×25, ×45)।
- সম্ভাবনা `.env`-এ `W_SHRIMP, W_FISH, W_CHICKEN, W_STEAK, W_CABBAGE, W_CARROT, W_CORN, W_TOMATO, W_SALAD, W_PIZZA` দিয়ে বদলানো যায়। বর্তমান হিসাব দেখতে: `GET /api/odds`।
- **ন্যায্যতা:** রাউন্ড শুরুতে `hash = sha256(seed)` পাঠানো হয়, ফলাফল আসে `HMAC_SHA256(seed, roundId)` থেকে, শেষে seed দেখানো হয়। যেকেউ `GET /api/round/<নম্বর>` দিয়ে মিলিয়ে দেখতে পারে।
- সার্ভার হঠাৎ বন্ধ হলে, শেষ না হওয়া রাউন্ডের সব বেট আবার চালু হলে নিজে ফেরত যায়। জয়ের কয়েন দিতে না পারলে প্রতি ১০ সেকেন্ডে আবার চেষ্টা করে।

### সালাদ/পিৎজা ও লাভের হিসাব
সব গুণের উল্টো যোগফল (4×1/5 + 1/10 + 1/15 + 1/25 + 1/45) ≈ ১.০২৮৯। তাই গড় ফেরত ≈ (১ + ৩ × সালাদ+পিৎজার মোট সম্ভাবনা) ÷ ১.০২৮৯।
- ডিফল্ট (সালাদ ০.৪%, পিৎজা ০.২%): গড় ফেরত ≈ ৯৮.৯%, তোমার লাভ ≈ ১.১%।
- সালাদ+পিৎজা মিলে ≈ ০.৯৬% ছাড়ালে ফেরত ১০০% পেরিয়ে যায়, মানে তুমি লোকসানে যাবে। বেশি লাভ চাইলে সালাদ/পিৎজা কমাও বা খাবারের weight কমিয়ে একটা "হাউস" অংশ রাখো।

## অন্য API
- `GET /health` — সার্ভার চালু কিনা
- `GET /api/history?limit=50` — শেষ ফলাফলগুলো
- `GET /api/admin/stats?key=ADMIN_KEY` — আজকের মোট বেট, মোট জয়, লাভ, অনলাইন ইউজার, বাকি পেমেন্ট
- `GET /api/admin/topup?key=..&uid=..&amount=..` — শুধু `WALLET_MODE=local`-এ পরীক্ষার কয়েন দেওয়া

## WebSocket বার্তা (নিজের ক্লায়েন্ট বানালে)
ক্লায়েন্ট → সার্ভার: `{t:"bet", reqId, round, itemId, amount}`, `{t:"records"}`, `{t:"balance"}`
সার্ভার → ক্লায়েন্ট: `hello`, `state`, `totals`, `spin`, `bet_ok`, `bet_err`, `result`, `balance`, `records`। টোকেন ভুল হলে সংযোগ কোড ৪০০১ দিয়ে বন্ধ হয়।

## নিরাপত্তা
- প্রোডাকশনে `DEMO_AUTH=0` রাখো (না হলে টোকেন ছাড়াই যে কেউ ঢুকতে পারবে)।
- `GAME_JWT_SECRET`, `WALLET_SECRET`, `ADMIN_KEY` লম্বা র‍্যান্ডম রাখো, কাউকে দিও না।
- কয়েন যদি টাকায় কেনা বা টাকায় ফেরত নেওয়া যায়, তাহলে এটা অনেক দেশে (ওমান, বাংলাদেশসহ) জুয়া হিসেবে ধরা হয় এবং Google Play / App Store-এ আলাদা অনুমতি লাগে।
