import { kv as _kv } from '@vercel/kv';

// KV is available only when KV_REST_API_URL + KV_REST_API_TOKEN env vars are set
const kvReady = !!(process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN);
const kv = kvReady ? _kv : null;

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const RATE_LIMIT = 20; // per IP per hour
const RATE_WINDOW = 3600; // seconds
const DAILY_CAP = 500; // total requests per day

// In-memory fallback (resets on cold start, but keeps proxy working without KV)
const memRateLimits = new Map();
let memDailyCount = 0;
let memDailyDate = '';

async function checkRateLimit(ip) {
  if (kv) {
    try {
      const key = `rl:${ip}`;
      const count = await kv.incr(key);
      if (count === 1) await kv.expire(key, RATE_WINDOW);
      return count <= RATE_LIMIT;
    } catch { /* KV error — fall through to memory */ }
  }
  // In-memory fallback
  const now = Date.now();
  const entry = memRateLimits.get(ip);
  if (!entry || now - entry.start > RATE_WINDOW * 1000) {
    memRateLimits.set(ip, { start: now, count: 1 });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

async function checkDailyCap() {
  const today = new Date().toISOString().slice(0, 10);
  if (kv) {
    try {
      const key = `daily:${today}`;
      const count = await kv.incr(key);
      if (count === 1) await kv.expire(key, 86400);
      return count <= DAILY_CAP;
    } catch { /* KV error — fall through to memory */ }
  }
  // In-memory fallback
  if (memDailyDate !== today) {
    memDailyDate = today;
    memDailyCount = 0;
  }
  memDailyCount++;
  return memDailyCount <= DAILY_CAP;
}

export default async function handler(req, res) {
  // CORS: only allow chrome extensions
  const origin = req.headers.origin || '';
  if (origin.startsWith('chrome-extension://')) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-installation-id');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Require installation ID header (rate limiting by installation)
  const installId = req.headers['x-installation-id'];
  if (!installId) {
    return res.status(403).json({ error: 'Missing installation ID. Update your extension.' });
  }

  // Daily cost cap
  if (!(await checkDailyCap())) {
    return res.status(429).json({ error: 'Daily limit reached. Try again tomorrow or add your own API key.' });
  }

  // Per-IP rate limit (KV with in-memory fallback)
  const ip = req.headers['x-forwarded-for']?.split(',')[0] || 'unknown';
  if (!(await checkRateLimit(ip))) {
    return res.status(429).json({ error: 'Rate limit exceeded. Try again later.' });
  }

  if (!ANTHROPIC_API_KEY) {
    return res.status(500).json({ error: 'Server misconfigured: missing API key' });
  }

  try {
    const body = req.body;
    if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
      return res.status(400).json({ error: 'Invalid request: messages required' });
    }

    const maxTokens = Math.min(body.max_tokens || 512, 1024);
    const apiBody = {
      model: 'claude-haiku-4-5-20251001',
      max_tokens: maxTokens,
      messages: body.messages.slice(-10),
    };
    if (body.system) apiBody.system = body.system.slice(0, 5000);

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(apiBody),
    });

    const data = await response.json();
    if (data.content && data.content[0]) {
      return res.json({ content: data.content[0].text });
    }
    return res.status(response.status).json({ error: data.error?.message || 'API error' });
  } catch (err) {
    return res.status(500).json({ error: 'Internal error: ' + err.message });
  }
}
