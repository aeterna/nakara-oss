import type { Job } from '../worker.js';
import { retentionJob } from './retention.js';
import { autoCloseJob } from './auto-close.js';

export const jobs: Job[] = [retentionJob, autoCloseJob];

export { retentionJob, autoCloseJob };
