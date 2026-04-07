// Cloudflare Worker — SMILE AI Proxy
// Deploy: wrangler deploy
// Set secret: wrangler secret put ANTHROPIC_API_KEY

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// Simple in-memory rate limiter (per-IP, resets on worker restart)
const rateLimits = new Map();
const RATE_LIMIT = 20; // requests per window
const RATE_WINDOW = 60 * 60 * 1000; // 1 hour

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

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (request.method === 'GET') {
      return Response.json({ status: 'ok', service: 'smile-ai-proxy' }, { headers: CORS_HEADERS });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
    }

    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    if (!checkRateLimit(ip)) {
      return Response.json(
        { error: 'Rate limit exceeded. Try again later.' },
        { status: 429, headers: CORS_HEADERS }
      );
    }

    if (!env.ANTHROPIC_API_KEY) {
      return Response.json(
        { error: 'Server misconfigured: missing API key', hasEnv: Object.keys(env).join(',') },
        { status: 500, headers: CORS_HEADERS }
      );
    }

    try {
      const body = await request.json();

      // Validate request
      if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
        return Response.json(
          { error: 'Invalid request: messages required' },
          { status: 400, headers: CORS_HEADERS }
        );
      }

      // Enforce limits
      const maxTokens = Math.min(body.max_tokens || 512, 1024);

      const apiBody = {
        model: 'claude-haiku-4-5-20251001',
        max_tokens: maxTokens,
        messages: body.messages.slice(-10), // last 10 messages max
      };

      if (body.system) {
        // Truncate system prompt to 5000 chars
        apiBody.system = body.system.slice(0, 5000);
      }

      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify(apiBody),
      });

      const data = await response.json();

      if (data.content && data.content[0]) {
        return Response.json(
          { content: data.content[0].text },
          { headers: CORS_HEADERS }
        );
      }

      return Response.json(
        { error: data.error?.message || JSON.stringify(data), apiStatus: response.status, keyPrefix: env.ANTHROPIC_API_KEY?.slice(0, 12) },
        { status: response.status, headers: CORS_HEADERS }
      );
    } catch (err) {
      return Response.json(
        { error: 'Internal error: ' + err.message },
        { status: 500, headers: CORS_HEADERS }
      );
    }
  },
};
