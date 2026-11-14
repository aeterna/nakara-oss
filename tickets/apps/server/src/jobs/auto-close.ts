import type { Job, JobContext } from '../worker.js';

export const autoCloseJob: Job = {
  name: 'auto-close',
  intervalMs: 5 * 60 * 1000, // 5 minutes
  async run(_ctx: JobContext): Promise<void> {
    // Lanes fill this
  },
};

export default autoCloseJob;
