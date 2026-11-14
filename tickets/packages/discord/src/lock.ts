import type pg from 'pg';

export interface LockOptions {
  intervalMs?: number;
  signal?: AbortSignal;
  onStandby?: () => void;
}

export interface GatewayLockHandle {
  release(): Promise<void>;
}

export async function acquireGatewayLock(
  pool: pg.Pool,
  appId: string,
  opts?: LockOptions
): Promise<GatewayLockHandle> {
  const intervalMs = opts?.intervalMs ?? 5000;
  const signal = opts?.signal;
  const key = `nakara-tickets:${appId}`;

  const client = await pool.connect();
  let clientReleased = false;

  const safeClientRelease = () => {
    if (!clientReleased) {
      clientReleased = true;
      try {
        client.release();
      } catch {
        // Ignore duplicate release errors
      }
    }
  };

  try {
    while (!signal?.aborted) {
      const res = await client.query<{ locked: boolean }>(
        'SELECT pg_try_advisory_lock(hashtextextended($1, 0)) AS locked',
        [key]
      );

      const locked = Boolean(res.rows[0]?.locked);
      if (locked) {
        let released = false;
        return {
          release: async () => {
            if (released) return;
            released = true;
            try {
              await client.query(
                'SELECT pg_advisory_unlock(hashtextextended($1, 0))',
                [key]
              );
            } finally {
              safeClientRelease();
            }
          },
        };
      }

      if (opts?.onStandby) {
        opts.onStandby();
      }

      // Wait intervalMs or abort
      await new Promise<void>((resolve, reject) => {
        if (signal?.aborted) {
          reject(signal.reason ?? new Error('Aborted'));
          return;
        }

        let timer: NodeJS.Timeout;

        const onAbort = () => {
          clearTimeout(timer);
          reject(signal?.reason ?? new Error('Aborted'));
        };

        timer = setTimeout(() => {
          signal?.removeEventListener('abort', onAbort);
          resolve();
        }, intervalMs);

        signal?.addEventListener('abort', onAbort, { once: true });
      });
    }

    throw signal?.reason ?? new Error('Aborted');
  } catch (err) {
    safeClientRelease();
    throw err;
  }
}
