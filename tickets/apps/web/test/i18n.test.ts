import { describe, it, expect } from 'vitest';
import { t } from '../src/i18n.js';

describe('web i18n merge (x4)', () => {
  it('resolves a key defined only in i18n/tags.ts through t()', () => {
    // tag_only_test_key is defined only in i18n/tags.ts
    const enVal = t('tag_only_test_key', 'en');
    const thVal = t('tag_only_test_key', 'th');

    expect(enVal).toBe('Tag snippet defined only in tags.ts');
    expect(thVal).toBe('ข้อความแท็กเฉพาะใน tags.ts');
  });

  it('still resolves base translations', () => {
    expect(t('categories', 'en')).toBe('Categories');
    expect(t('settings', 'en')).toBe('Settings');
  });
});
