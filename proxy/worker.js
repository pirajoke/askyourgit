// Cloudflare Worker — Ask your GIT AI Proxy
// Deploy: wrangler deploy
// Set secrets: wrangler secret put ANTHROPIC_API_KEY
//              wrangler secret put STATS_SECRET
// Set vars:    MONTHLY_BUDGET_LIMIT (default 500 requests/month)
//              DAILY_PER_USER_LIMIT (default 15 requests/day)

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-installation-id',
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

    // --- GET /stats or health check ---
    if (request.method === 'GET') {
      const url = new URL(request.url);
      const secret = url.searchParams.get('secret');
      if (url.pathname === '/stats' && secret && env.STATS_SECRET && secret === env.STATS_SECRET) {
        const list = await env.SMILE_STATS.list();
        const stats = {};
        for (const key of list.keys) {
          stats[key.name] = Number(await env.SMILE_STATS.get(key.name)) || 0;
        }
        return Response.json(stats, { headers: CORS_HEADERS });
      }
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

    // --- POST /event — anonymous analytics ---
    const url = new URL(request.url);
    if (url.pathname === '/event') {
      try {
        const { action, tool, stack } = await request.json();
        const VALID_ACTIONS = ['install', 'summary', 'chat', 'stack_detected'];
        if (!action || !VALID_ACTIONS.includes(action)) {
          return Response.json({ error: 'Invalid action' }, { status: 400, headers: CORS_HEADERS });
        }
        const day = new Date().toISOString().slice(0, 10);
        const increments = [`total:${action}`, `day:${day}:${action}`];
        if (tool) increments.push(`total:${action}:${tool}`);
        if (stack) increments.push(`total:stack:${stack}`);
        await Promise.all(increments.map(async (key) => {
          const val = Number(await env.SMILE_STATS.get(key)) || 0;
          await env.SMILE_STATS.put(key, String(val + 1));
        }));
        return Response.json({ ok: true }, { headers: CORS_HEADERS });
      } catch (err) {
        return Response.json({ error: 'Bad request' }, { status: 400, headers: CORS_HEADERS });
      }
    }

    if (!env.ANTHROPIC_API_KEY) {
      return Response.json(
        { error: 'Server misconfigured: missing API key' },
        { status: 500, headers: CORS_HEADERS }
      );
    }

    // --- Monthly budget kill-switch ---
    const monthKey = `budget:${new Date().toISOString().slice(0, 7)}`;
    const monthCount = Number(await env.SMILE_STATS.get(monthKey)) || 0;
    const monthlyLimit = Number(env.MONTHLY_BUDGET_LIMIT) || 500;
    if (monthCount >= monthlyLimit) {
      return Response.json(
        { error: 'Monthly budget exceeded. Add your own Claude API key in settings.' },
        { status: 503, headers: CORS_HEADERS }
      );
    }

    // --- Per-installation rate limit (15/day default) ---
    const installId = request.headers.get('x-installation-id') || ip;
    const dailyUserKey = `user:${new Date().toISOString().slice(0, 10)}:${installId.slice(0, 16)}`;
    const dailyUserCount = Number(await env.SMILE_STATS.get(dailyUserKey)) || 0;
    const dailyPerUserLimit = Number(env.DAILY_PER_USER_LIMIT) || 15;
    if (dailyUserCount >= dailyPerUserLimit) {
      return Response.json(
        { error: 'Daily limit reached. Add your Claude API key in settings for unlimited use.' },
        { status: 429, headers: CORS_HEADERS }
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
        // Increment budget + per-user counters
        await Promise.all([
          env.SMILE_STATS.put(monthKey, String(monthCount + 1)),
          env.SMILE_STATS.put(dailyUserKey, String(dailyUserCount + 1)),
        ]);
        return Response.json(
          { content: data.content[0].text },
          { headers: CORS_HEADERS }
        );
      }

      return Response.json(
        { error: data.error?.message || 'API error' },
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
