import { PGlite } from '@electric-sql/pglite';
import type { TicketsDb } from '../src/index.js';
export interface TestDbHandle {
    db: TicketsDb;
    pg: PGlite;
    client?: PGlite;
    reset: () => Promise<void>;
    close: () => Promise<void>;
}
export declare function openTestDb(): Promise<TestDbHandle>;
//# sourceMappingURL=pglite.d.ts.map