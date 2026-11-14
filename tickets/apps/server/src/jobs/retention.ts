import type { Job, JobContext } from '../worker.js';
import { purgeExpired } from '../privacy.js';

export const retentionJob: Job = {
  name: 'retention',
  intervalMs: 15 * 60 * 1000, // 15 minutes
  async run(ctx: JobContext): Promise<void> {
    const storage = (ctx as any).storage ?? null;
    const counts = await purgeExpired(ctx.db, new Date(), storage);
    ctx.log.info(
      `Retention purge complete: purged ${counts.tickets} tickets, ${counts.messages} messages, ${counts.attachments} attachments`,
    );
  },
};

export default retentionJob;
