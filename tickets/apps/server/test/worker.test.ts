import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { startWorker, type Job, type JobContext, type Logger } from '../src/worker.js';

describe('worker (w1)', () => {
  let mockLog: Logger;
  let mockCtx: JobContext;

  beforeEach(() => {
    vi.useFakeTimers();
    mockLog = {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
    mockCtx = {
      db: {} as any,
      config: {} as any,
      discord: null,
      storage: null,
      log: mockLog,
    };
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('(w1-1) a job runs on its interval (fake timers)', async () => {
    let runCount = 0;
    const testJob: Job = {
      name: 'interval-job',
      intervalMs: 1000,
      async run() {
        runCount++;
      },
    };

    const worker = startWorker([testJob], mockCtx, mockLog);

    expect(runCount).toBe(0);

    // Advance 1000 ms
    await vi.advanceTimersByTimeAsync(1000);
    expect(runCount).toBe(1);

    // Advance another 1000 ms
    await vi.advanceTimersByTimeAsync(1000);
    expect(runCount).toBe(2);

    await worker.stop();
  });

  it('(w1-2) a throwing job is logged and runs again', async () => {
    let attempts = 0;
    const failingJob: Job = {
      name: 'flaky-job',
      intervalMs: 1000,
      async run() {
        attempts++;
        if (attempts === 1) {
          throw new Error('boom');
        }
      },
    };

    const worker = startWorker([failingJob], mockCtx, mockLog);

    // First run fails
    await vi.advanceTimersByTimeAsync(1000);
    expect(attempts).toBe(1);
    expect(mockLog.error).toHaveBeenCalled();
    const [logMsg] = (mockLog.error as any).mock.calls[0];
    expect(String(logMsg)).toContain('flaky-job');

    // Second run succeeds
    await vi.advanceTimersByTimeAsync(1000);
    expect(attempts).toBe(2);

    await worker.stop();
  });

  it('(w1-3) a slow job never overlaps itself', async () => {
    let concurrent = 0;
    let maxConcurrent = 0;
    let totalRuns = 0;

    const slowJob: Job = {
      name: 'slow-job',
      intervalMs: 1000,
      async run() {
        concurrent++;
        maxConcurrent = Math.max(maxConcurrent, concurrent);
        // Simulate long async task lasting 2500 ms (using setTimeout)
        await new Promise((resolve) => setTimeout(resolve, 2500));
        concurrent--;
        totalRuns++;
      },
    };

    const worker = startWorker([slowJob], mockCtx, mockLog);

    // 1000ms: job 1 starts
    await vi.advanceTimersByTimeAsync(1000);
    expect(concurrent).toBe(1);

    // 2000ms: interval ticks again, but job 1 is still running, so it does not overlap
    await vi.advanceTimersByTimeAsync(1000);
    expect(concurrent).toBe(1);
    expect(maxConcurrent).toBe(1);

    // 3500ms: job 1 finishes (at 3500ms total elapsed)
    await vi.advanceTimersByTimeAsync(1500);
    expect(totalRuns).toBe(1);
    expect(maxConcurrent).toBe(1);

    // Next interval at 4000ms triggers job 2
    await vi.advanceTimersByTimeAsync(1000);
    expect(maxConcurrent).toBe(1);

    // Stop worker while job 2 is running and advance time for it to complete
    const stopPromise = worker.stop();
    await vi.advanceTimersByTimeAsync(3000);
    await stopPromise;

    expect(maxConcurrent).toBe(1);
    expect(totalRuns).toBe(2);
    expect(concurrent).toBe(0);
  });

  it('(w1-4) stop() waits for running jobs', async () => {
    let finished = false;

    const longJob: Job = {
      name: 'long-job',
      intervalMs: 1000,
      async run() {
        await new Promise((resolve) => setTimeout(resolve, 3000));
        finished = true;
      },
    };

    const worker = startWorker([longJob], mockCtx, mockLog);

    // Start job
    await vi.advanceTimersByTimeAsync(1000);
    expect(finished).toBe(false);

    // Call stop while job is running
    const stopPromise = worker.stop();

    // Advance time to allow job to complete
    await vi.advanceTimersByTimeAsync(3000);
    await stopPromise;

    expect(finished).toBe(true);
  });

  it('(w1-5) job receives ctx with storage and gateway closeHooks', async () => {
    let capturedStorage: any = undefined;
    let capturedCloseHooksCalled = false;

    const mockStorage = {
      put: vi.fn(),
      get: vi.fn(),
      delete: vi.fn(),
    };
    const mockCloseHooks = vi.fn().mockImplementation(async () => {
      capturedCloseHooksCalled = true;
    });

    const ctxWithStorageAndGateway: JobContext = {
      db: {} as any,
      config: {} as any,
      discord: null,
      storage: mockStorage as any,
      gateway: {
        closeHooks: mockCloseHooks,
      },
      log: mockLog,
    };

    const testJob: Job = {
      name: 'storage-gateway-job',
      intervalMs: 1000,
      async run(ctx) {
        capturedStorage = ctx.storage;
        await ctx.gateway?.closeHooks?.('guild-1', 'ticket-1', 'actor-1');
      },
    };

    const worker = startWorker([testJob], ctxWithStorageAndGateway, mockLog);

    await vi.advanceTimersByTimeAsync(1000);
    expect(capturedStorage).toBe(mockStorage);
    expect(capturedCloseHooksCalled).toBe(true);
    expect(mockCloseHooks).toHaveBeenCalledWith('guild-1', 'ticket-1', 'actor-1');

    await worker.stop();
  });
});
