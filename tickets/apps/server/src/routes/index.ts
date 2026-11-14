import type { FastifyInstance } from 'fastify';
import actions from './actions.js';
import audit from './audit.js';
import auth from './auth.js';
import blocks from './blocks.js';
import bridge from './bridge.js';
import categories from './categories.js';
import data from './data.js';
import gameServers from './game-servers.js';
import me from './me.js';
import panels from './panels.js';
import settings from './settings.js';
import stats from './stats.js';
import system from './system.js';
import tags from './tags.js';
import tickets from './tickets.js';

export default async function (app: FastifyInstance) {
  for (const plugin of [
    actions, audit, auth, blocks, bridge, categories, data,
    gameServers, me, panels, settings, stats, system, tags, tickets,
  ]) {
    app.register(plugin);
  }
}
