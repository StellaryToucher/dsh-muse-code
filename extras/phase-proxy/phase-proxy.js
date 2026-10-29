// phase-proxy.js — 修正中转站 SSE 里 message item 的 phase 不一致问题。
//
// 现象：magpie 的 response.output_item.added 里 message 项没有 phase 字段，
// 但随后的 output_item.done / response.completed 里带 phase:"commentary"。
// muse 的流解析器在 added 时把 message 默认为 final_answer，随后看到
// commentary，于是报 "changed phase from final_answer to commentary" 并终止。
//
// 本代理逐行转发，只改 data: 里的 JSON：
//   MODE=strip   —— 删掉所有 phase 字段（一致性最好，中间 commentary 会被当成普通文本）
//   MODE=commentary / final_answer —— 统一改写为指定 phase
// 默认 strip。
const http = require('http');
const fs = require('fs');
const path = require('path');

const LISTEN = Number(process.env.PROXY_PORT || 3426);
const UPSTREAM = process.env.PROXY_UPSTREAM || 'http://127.0.0.1:3425';
const MODE = process.env.MODE || 'strip';
const LOGDIR = process.env.PROXY_LOGDIR || '';

let seq = 0;
const log = (...a) => console.log(new Date().toISOString(), ...a);

function transform(obj) {
  const fix = (item) => {
    if (!item || typeof item !== 'object') return;
    if (item.type === 'message') {
      if (MODE === 'strip') delete item.phase;
      else item.phase = MODE;
    }
  };
  if (obj.item) fix(obj.item);
  if (obj.response && Array.isArray(obj.response.output)) obj.response.output.forEach(fix);
  return obj;
}

const server = http.createServer((req, res) => {
  const id = ++seq;
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const tag = `${String(id).padStart(3, '0')}-${req.method}-${req.url.replace(/[^\w.-]/g, '_')}`;
    if (LOGDIR) {
      fs.mkdirSync(LOGDIR, { recursive: true });
      fs.writeFileSync(path.join(LOGDIR, tag + '.req.json'), body);
    }
    const target = new URL(UPSTREAM);
    const up = http.request(
      { hostname: target.hostname, port: target.port, path: req.url, method: req.method,
        headers: { ...req.headers, host: `${target.hostname}:${target.port}` } },
      (ur) => {
        res.writeHead(ur.statusCode || 502, ur.headers);
        const isEventStream = String(ur.headers['content-type'] || '').includes('event-stream');
        if (!isEventStream) { ur.pipe(res); return; }
        let buf = '';
        const flushLine = (line) => {
          if (!line.startsWith('data:')) { res.write(line + '\n'); return; }
          const payload = line.slice(5).trim();
          if (payload === '[DONE]' || payload === '') { res.write(line + '\n'); return; }
          try {
            const obj = transform(JSON.parse(payload));
            res.write('data: ' + JSON.stringify(obj) + '\n');
          } catch {
            res.write(line + '\n');
          }
        };
        ur.setEncoding('utf8');
        ur.on('data', (chunk) => {
          buf += chunk;
          let i;
          while ((i = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, i).replace(/\r$/, '');
            buf = buf.slice(i + 1);
            flushLine(line);
          }
        });
        ur.on('end', () => {
          if (buf.length) flushLine(buf.replace(/\r$/, ''));
          res.end();
        });
      }
    );
    up.on('error', (e) => { log('upstream error', e && e.message); if (!res.headersSent) res.writeHead(502); res.end(); });
    up.end(body);
  });
});

server.listen(LISTEN, '127.0.0.1', () => log(`phase-proxy :${LISTEN} -> ${UPSTREAM} MODE=${MODE}`));
