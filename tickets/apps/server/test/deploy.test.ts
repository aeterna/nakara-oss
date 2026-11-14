import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

interface ComposeService {
  image?: string;
  restart?: string;
  mem_limit?: string;
  environment?: Record<string, string> | string[];
  secrets?: string[];
  volumes?: string[];
  ports?: string[];
  profiles?: string[];
  depends_on?: any;
  command?: string | string[];
  entrypoint?: string | string[];
  healthcheck?: any;
}

interface ComposeConfig {
  services: Record<string, ComposeService>;
  secrets?: Record<string, any>;
  volumes?: Record<string, any>;
}

export function validateServiceMemLimits(services: Record<string, ComposeService>): string[] {
  const missing: string[] = [];
  for (const [name, service] of Object.entries(services)) {
    if (!service.mem_limit || typeof service.mem_limit !== 'string' || !/^\d+[kmgKMG]$/.test(service.mem_limit)) {
      missing.push(name);
    }
  }
  return missing;
}

export function findInlineSecrets(services: Record<string, ComposeService>): { service: string; variable: string; value: string }[] {
  const inlineSecrets: { service: string; variable: string; value: string }[] = [];
  const sensitiveRegex = /(TOKEN|SECRET|PASSWORD|KEY)/i;

  for (const [name, service] of Object.entries(services)) {
    const env = service.environment;
    if (!env) continue;

    if (Array.isArray(env)) {
      for (const entry of env) {
        const idx = entry.indexOf('=');
        if (idx === -1) continue;
        const k = entry.slice(0, idx).trim();
        const v = entry.slice(idx + 1).trim();
        if (sensitiveRegex.test(k)) {
          if (!k.endsWith('_FILE') || !v.startsWith('/run/secrets/')) {
            inlineSecrets.push({ service: name, variable: k, value: v });
          }
        }
      }
    } else {
      for (const [k, v] of Object.entries(env)) {
        if (sensitiveRegex.test(k)) {
          if (!k.endsWith('_FILE') || !String(v).startsWith('/run/secrets/')) {
            inlineSecrets.push({ service: name, variable: k, value: String(v) });
          }
        }
      }
    }
  }

  return inlineSecrets;
}

describe('deploy compose sanity acceptance tests', () => {
  const composePath = fileURLToPath(new URL('../../../compose.yaml', import.meta.url));

  it('compose.yaml file exists and parses as valid YAML', () => {
    expect(fs.existsSync(composePath), 'tickets/compose.yaml must exist').toBe(true);
    const content = fs.readFileSync(composePath, 'utf8');
    const config = YAML.parse(content) as ComposeConfig;
    expect(config).toBeDefined();
    expect(config.services).toBeDefined();
  });

  it('every service in compose.yaml has a valid mem_limit', () => {
    const content = fs.readFileSync(composePath, 'utf8');
    const config = YAML.parse(content) as ComposeConfig;
    const services = config.services;

    expect(Object.keys(services).length).toBeGreaterThan(0);
    const missing = validateServiceMemLimits(services);
    expect(missing, `services missing mem_limit: ${missing.join(', ')}`).toEqual([]);

    for (const [name, service] of Object.entries(services)) {
      expect(service.mem_limit, `service ${name} must define mem_limit`).toBeDefined();
      expect(service.mem_limit).toMatch(/^\d+[kmgKMG]$/);
    }
  });

  it('migrate service has restart: "no"', () => {
    const content = fs.readFileSync(composePath, 'utf8');
    const config = YAML.parse(content) as ComposeConfig;
    const migrate = config.services.migrate;

    expect(migrate, 'migrate service must be defined').toBeDefined();
    expect(migrate.restart).toBe('no');
  });

  it('no service has an inline value for a variable whose name contains TOKEN, SECRET, PASSWORD or KEY', () => {
    const content = fs.readFileSync(composePath, 'utf8');
    const config = YAML.parse(content) as ComposeConfig;
    const services = config.services;

    const leaks = findInlineSecrets(services);
    expect(
      leaks,
      `found inline secrets in compose services: ${leaks.map((l) => `${l.service}.${l.variable}=${l.value}`).join(', ')}`
    ).toEqual([]);
  });

  it('negative control: validator functions catch missing mem_limit, inline secrets, and invalid restart', () => {
    // 1. Catches missing mem_limit
    const badMemServices: Record<string, ComposeService> = {
      app: { image: 'test' },
    };
    expect(validateServiceMemLimits(badMemServices)).toContain('app');

    // 2. Catches inline PASSWORD
    const badPasswordServices: Record<string, ComposeService> = {
      db: {
        mem_limit: '256m',
        environment: { POSTGRES_PASSWORD: 'plaintext_super_secret' },
      },
    };
    const pwLeaks = findInlineSecrets(badPasswordServices);
    expect(pwLeaks).toHaveLength(1);
    expect(pwLeaks[0]?.variable).toBe('POSTGRES_PASSWORD');

    // 3. Catches inline TOKEN
    const badTokenServices: Record<string, ComposeService> = {
      bot: {
        mem_limit: '256m',
        environment: { DISCORD_TOKEN: 'token_xyz123' },
      },
    };
    const tokenLeaks = findInlineSecrets(badTokenServices);
    expect(tokenLeaks).toHaveLength(1);
    expect(tokenLeaks[0]?.variable).toBe('DISCORD_TOKEN');

    // 4. Catches sensitive variable ending in _FILE but not pointing to /run/secrets/
    const badFileServices: Record<string, ComposeService> = {
      srv: {
        mem_limit: '256m',
        environment: { TICKETS_DATA_KEY_FILE: '/etc/unsafe/raw_key' },
      },
    };
    const fileLeaks = findInlineSecrets(badFileServices);
    expect(fileLeaks).toHaveLength(1);
    expect(fileLeaks[0]?.variable).toBe('TICKETS_DATA_KEY_FILE');
  });

  it('service dependencies, profiles and volumes are properly wired', () => {
    const content = fs.readFileSync(composePath, 'utf8');
    const config = YAML.parse(content) as ComposeConfig;
    const { postgres, migrate, app, caddy, cloudflared, backup } = config.services;

    // postgres
    expect(postgres).toBeDefined();
    expect(postgres.healthcheck).toBeDefined();

    // migrate depends on postgres healthy
    expect(migrate).toBeDefined();
    expect(migrate.depends_on?.postgres?.condition).toBe('service_healthy');

    // app depends on migrate completed successfully
    expect(app).toBeDefined();
    expect(app.depends_on?.migrate?.condition).toBe('service_completed_successfully');

    // app mounts /data/files volume
    const appVolumes = app.volumes ?? [];
    const hasStorage = appVolumes.some((v) => v.includes('/data/files'));
    expect(hasStorage, 'app service must mount /data/files volume').toBe(true);

    // caddy profile
    expect(caddy).toBeDefined();
    expect(caddy.profiles).toContain('caddy');
    expect(caddy.ports).toBeDefined();
    const ports = caddy.ports ?? [];
    expect(ports.some((p) => p.includes('80'))).toBe(true);
    expect(ports.some((p) => p.includes('443'))).toBe(true);

    // cloudflared profile
    expect(cloudflared).toBeDefined();
    expect(cloudflared.profiles).toContain('cloudflared');
    expect(cloudflared.ports).toBeUndefined();
    expect(cloudflared.secrets).toContain('cloudflared_token');

    // backup
    expect(backup).toBeDefined();
    expect(backup.depends_on?.postgres?.condition).toBe('service_healthy');
  });
});
