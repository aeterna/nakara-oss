import type { TicketsDb } from '@nakara-tickets/db';
import type { TicketsConfig } from './config.js';
import type { DiscordRest } from './discord-rest.js';
import type { Storage } from './storage.js';

export type { Storage };

export interface Logger {
  info: (msg: string, ...args: any[]) => void;
  warn: (msg: string, ...args: any[]) => void;
  error: (msg: string, ...args: any[]) => void;
}

export interface JobContextGateway {
  closeHooks?(guildId: string, ticketId: string, actorId: string): Promise<void>;
}

export interface JobContext {
  db: TicketsDb;
  config: TicketsConfig;
  discord: DiscordRest | null;
  storage: Storage | null;
  gateway?: JobContextGateway;
  log: Logger;
}

export interface Job {
  name: string;
  intervalMs: number;
  run(ctx: JobContext): Promise<void>;
}

export interface WorkerHandle {
  stop(): Promise<void>;
}

export function startWorker(
  jobs: Job[],
  ctx: JobContext,
  log: Logger
): WorkerHandle {
  const timers: NodeJS.Timeout[] = [];
  const activeRuns = new Set<Promise<void>>();
  let stopped = false;

  for (const job of jobs) {
    let running = false;

    const timer = setInterval(() => {
      if (stopped || running) {
        return;
      }
      running = true;

      const runPromise = (async () => {
        try {
          await job.run(ctx);
        } catch (err) {
          log.error(`Job ${job.name} failed:`, err);
        } finally {
          running = false;
        }
      })();

      activeRuns.add(runPromise);
      runPromise.finally(() => {
        activeRuns.delete(runPromise);
      });
    }, job.intervalMs);

    timers.push(timer);
  }

  return {
    async stop(): Promise<void> {
      stopped = true;
      for (const timer of timers) {
        clearInterval(timer);
      }
      await Promise.all(Array.from(activeRuns));
    },
  };
}
