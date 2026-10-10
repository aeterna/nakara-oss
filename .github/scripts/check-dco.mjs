#!/usr/bin/env node
// Every commit in BASE..HEAD must carry a `Signed-off-by:` line whose EMAIL matches the commit author (Developer
// Certificate of Origin, https://developercertificate.org). Fork-safe: reads git only, no token.
import { execFileSync } from 'node:child_process';

const [base, head] = process.argv.slice(2);
if (!base || !head) {
  console.error('usage: check-dco.mjs <base-sha> <head-sha>');
  process.exit(2);
}
const raw = execFileSync('git', ['log', '--no-merges', '--format=%H%x00%an%x00%ae%x00%B%x1e', `${base}..${head}`], { encoding: 'utf8' });
// GitHub's own bots cannot sign off. Commit author emails are NOT authenticated (anyone can set them),
// so a bot commit is exempt only when the PR itself was opened by that bot account (PR_AUTHOR comes
// from the event payload, which a contributor cannot forge). Bot PRs still need owner review + green CI.
const BOTS = new Map([
  ['dependabot[bot]', '49699333+dependabot[bot]@users.noreply.github.com'],
  ['github-actions[bot]', '41898282+github-actions[bot]@users.noreply.github.com'],
]);
const botEmail = BOTS.get(process.env.PR_AUTHOR ?? '');
const bad = [];
for (const rec of raw.split('\x1e').map((s) => s.trim()).filter(Boolean)) {
  const [sha, name, email, body] = rec.split('\x00');
  if (botEmail && email.trim().toLowerCase() === botEmail) continue;
  const signoffs = [...body.matchAll(/^Signed-off-by:\s*(.+?)\s*<([^>]+)>\s*$/gim)];
  // email only: names drift (accents, nicknames, casing) far more often than addresses do
  const ok = signoffs.some(([, , e]) => e.trim().toLowerCase() === email.trim().toLowerCase());
  if (!ok) bad.push(`${sha.slice(0, 10)} ${name} <${email}>`);
}
if (bad.length) {
  console.error(`✗ ${bad.length} commit(s) without a Signed-off-by line matching the author email:\n  ${bad.join('\n  ')}`);
  console.error('\nFix: git rebase --signoff <base>  (or commit with -s), then force-push your branch.');
  process.exit(1);
}
console.log('✓ DCO: every commit is signed off by its author');
