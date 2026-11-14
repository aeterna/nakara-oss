import path from 'node:path';
import fs from 'node:fs';
import fastifyStatic from '@fastify/static';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

const EXCLUDED_PREFIXES = ['/api', '/auth', '/bridge', '/healthz', '/metrics'] as const;
const CSP_HEADER = "default-src 'self'; img-src 'self' https://cdn.discordapp.com data:; frame-ancestors 'none'";

function isExcludedPath(url: string): boolean {
  const pathname = url.split('?')[0] ?? '';
  return EXCLUDED_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  );
}

/**
 * Serves the built SPA using @fastify/static.
 * Unknown GET paths outside /api, /auth, /bridge, /healthz, /metrics return index.html.
 * Sets X-Content-Type-Options: nosniff and Content-Security-Policy.
 * Missing dir logs a warning and serves nothing.
 */
export function installStatic(app: FastifyInstance, dir: string): void {
  if (!dir || !fs.existsSync(dir)) {
    if (app.log && typeof app.log.warn === 'function') {
      app.log.warn(`Static files directory not found: ${dir}; skipping static file serving`);
    } else {
      console.warn(`Static files directory not found: ${dir}; skipping static file serving`);
    }
    return;
  }

  const resolvedDir = path.resolve(dir);
  const staticPlugin = (fastifyStatic as any).default ?? fastifyStatic;

  app.register(async (scope: FastifyInstance) => {
    await scope.register(staticPlugin, {
      root: resolvedDir,
      wildcard: true,
      setHeaders: (res: any) => {
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('Content-Security-Policy', CSP_HEADER);
      },
    });

    scope.setNotFoundHandler((req: FastifyRequest, reply: FastifyReply) => {
      if (req.method === 'GET' && !isExcludedPath(req.url)) {
        const indexPath = path.join(resolvedDir, 'index.html');
        if (fs.existsSync(indexPath)) {
          reply.header('X-Content-Type-Options', 'nosniff');
          reply.header('Content-Security-Policy', CSP_HEADER);
          if (typeof (reply as any).sendFile === 'function') {
            return (reply as any).status(200).sendFile('index.html');
          }
          return reply
            .status(200)
            .type('text/html; charset=utf-8')
            .send(fs.readFileSync(indexPath, 'utf8'));
        }
      }

      return reply.status(404).send({ code: 'NOT_FOUND', message: 'Not found' });
    });
  });
}
