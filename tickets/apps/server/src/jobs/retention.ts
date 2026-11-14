import type { Job, JobContext } from '../worker.js';

export const retentionJob: Job = {
  name: 'retention',
  intervalMs: 15 * 60 * 1000, // 15 minutes
  async run(_ctx: JobContext): Promise<void> {
    // Lanes fill this
  },
};

export default retentionJob;
