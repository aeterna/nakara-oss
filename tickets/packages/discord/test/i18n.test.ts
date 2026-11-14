import { describe, it, expect } from 'vitest';
import { t } from '../src/i18n.js';

describe('discord i18n merge (x4)', () => {
  it('resolves a key defined in area dictionaries through t()', () => {
    const enVal = t('en', 'tag_only_test_key');
    const thVal = t('th', 'tag_only_test_key');

    expect(enVal).toBe('Tag snippet defined only in tags.ts');
    expect(thVal).toBe('ข้อความแท็กเฉพาะใน tags.ts');
  });

  it('still resolves base translations', () => {
    expect(t('en', 'ticket_limit')).toBe('You have reached the maximum number of open tickets.');
    expect(t('th', 'ticket_limit')).toBe('คุณมีตั๋วที่เปิดอยู่ครบตามจำนวนที่กำหนดแล้ว ไม่สามารถเปิดเพิ่มได้');
  });
});
