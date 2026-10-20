# Greedy Wheel কয়েন গেম

ভয়েস রুমের জন্য Greedy চাকা গেম। সালাদ (সব সবজি একসাথে জেতে) আর পিৎজা (সব মাংস একসাথে জেতে) আছে।

- `client/` — ফোনের গেম (HTML/CSS/JS)। অ্যাপের WebView-এ খোলো। গাইড: `client/README.md`
- `server/` — গেম সার্ভার (Node.js)। রাউন্ড, ফলাফল আর কয়েন এখানেই ঠিক হয়। গাইড: `server/README.md`

দ্রুত চালানো:
```bash
cd games/greedy/server
npm install
cp .env.example .env   # সব change-me বদলাও
npm start              # http://localhost:8080
```
লিংক: `https://তোমার-গেম-সার্ভার/?token=<JWT>&sheet=1`
