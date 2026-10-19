// Transport for the app/WebView. Supply the signed-in user's ID token through
// getToken(); never embed an API secret or service-account key in the HTML.
export function foodClient({getToken, onState, onEvent, onError = () => {}}) {
  let socket, stopped = false, retryTimer, snapshot, receivedAt = 0;
  const pending = new Map();
  async function request(path, method = 'GET', body, key) {
    const token = await getToken();
    if (!token) throw new Error('Sign in required');
    const response = await fetch('/food/' + path, {
      method, cache: 'no-store', headers: {
        Authorization: 'Bearer ' + token,
        ...(body ? {'Content-Type': 'application/json'} : {}),
        ...(key ? {'Idempotency-Key': key} : {}),
      }, ...(body ? {body: JSON.stringify(body)} : {}),
    });
    if (!response.ok) {
      const error = new Error('Food request failed'); error.status = response.status;
      throw error;
    }
    return response.json();
  }
  function accept(state) {
    snapshot = state; receivedAt = performance.now(); onState(state);
  }
  async function refresh() { const state = await request('state'); accept(state); return state; }
  async function connect() {
    try {
      await refresh();
      if (stopped) return;
      const token = await getToken();
      if (stopped) return;
      socket = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/food/events`);
      socket.onopen = () => socket.send(JSON.stringify({authorization: 'Bearer ' + token}));
      socket.onmessage = ({data}) => {
        try {
          const message = JSON.parse(data);
          if (message.event === 'state') accept(message.data);
          else onEvent(message); // UI must deduplicate result/banner by round ID.
        } catch (error) { onError(error); }
      };
      socket.onclose = () => { if (!stopped) retryTimer = setTimeout(connect, 3000); };
    } catch (error) { onError(error); if (!stopped) retryTimer = setTimeout(connect, 3000); }
  }
  return {
    start: connect,
    close() { stopped = true; clearTimeout(retryTimer); socket?.close(); },
    refresh,
    remainingSeconds() {
      if (!snapshot) return 0;
      return Math.max(0, Math.ceil((snapshot.endsAt - snapshot.serverNow - (performance.now() - receivedAt)) / 1000));
    },
    async bet(slot, amount) {
      if (!snapshot || snapshot.phase !== 'bet' || this.remainingSeconds() <= 0) throw new Error('Betting closed');
      const round = snapshot.round, fingerprint = JSON.stringify([round, slot, amount]);
      // Rapid duplicate taps share one in-flight promise. Ambiguous network
      // failures keep the same key for retry, preventing a second debit.
      let entry = pending.get(fingerprint);
      if (entry?.promise) return entry.promise;
      if (!entry) { entry = {key: crypto.randomUUID()}; pending.set(fingerprint, entry); }
      entry.promise = request('bet', 'POST', {round, slot, amount}, entry.key)
        .then(result => { pending.delete(fingerprint); refresh().catch(onError); return result; })
        .catch(error => { entry.promise = null; if (error.status && error.status < 500) pending.delete(fingerprint); throw error; });
      return entry.promise;
    },
    history: () => request('history'),
    autoplay: (slot, amount, rounds) => request('auto', 'POST', {slot, amount, rounds}),
  };
}
