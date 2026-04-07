const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const RATE_LIMIT = 20;
const RATE_WINDOW = 60 * 60 * 1000;
const rateLimits = new Map();

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimits.get(ip);
  if (!entry || now - entry.start > RATE_WINDOW) {
    rateLimits.set(ip, { start: now, count: 1 });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS, GET');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method === 'GET') return res.json({ status: 'ok', service: 'smile-ai-proxy' });
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const ip = req.headers['x-forwarded-for']?.split(',')[0] || 'unknown';
  if (!checkRateLimit(ip)) {
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
