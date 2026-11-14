export type SupportedLocale = 'th' | 'en';

export const translations = {
  th: {
    ticket_limit: 'คุณมีตั๋วที่เปิดอยู่ครบตามจำนวนที่กำหนดแล้ว ไม่สามารถเปิดเพิ่มได้',
    ticket_blocked: 'คุณถูกระงับการเปิดตั๋วในเซิร์ฟเวอร์นี้',
    ticket_not_found: 'ไม่พบข้อมูลตั๋ว',
    ticket_invalid_transition: 'ไม่สามารถเปลี่ยนสถานะตั๋วได้',
    ticket_not_claimer: 'เฉพาะผู้รับเรื่องเท่านั้นที่สามารถดำเนินการนี้ได้',
    ticket_target_required: 'กรุณาระบุผู้รับเรื่องใหม่',
    staff_only: 'การดำเนินการนี้สำหรับทีมงานเท่านั้น',
    ticket_created: 'สร้างตั๋วเรียบร้อยแล้ว: {channel}',
    ticket_claimed: 'ตั๋วนี้ถูกรับเรื่องโดย {user}',
    ticket_closed: 'ตั๋วนี้ถูกปิดโดย {user}',
    ticket_reopened: 'ตั๋วนี้ถูกเปิดใหม่อีกครั้งโดย {user}',
    ticket_welcome: 'ยินดีต้อนรับ! ทีมงานจะให้บริการคุณในไม่ช้า',
    claim_button: 'รับเรื่อง',
    close_button: 'ปิดตั๋ว',
    panel_sent: 'ส่งพาเนลเรียบร้อยแล้ว',
    panel_title: 'เปิดตั๋วแจ้งเรื่อง',
    panel_description: 'เลือกหมวดหมู่ด้านล่างเพื่อเปิดตั๋วสอบถามหรือแจ้งปัญหา',
    submit_button: 'ส่งข้อมูล',
    error: 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
  },
  en: {
    ticket_limit: 'You have reached the maximum number of open tickets.',
    ticket_blocked: 'You are blocked from opening tickets in this server.',
    ticket_not_found: 'Ticket not found.',
    ticket_invalid_transition: 'Cannot transition ticket in its current state.',
    ticket_not_claimer: 'Only the claimer can perform this action.',
    ticket_target_required: 'Target is required for transfer.',
    staff_only: 'This action is restricted to staff members.',
    ticket_created: 'Ticket created: {channel}',
    ticket_claimed: 'Ticket claimed by {user}',
    ticket_closed: 'Ticket closed by {user}',
    ticket_reopened: 'Ticket reopened by {user}',
    ticket_welcome: 'Welcome! Staff will assist you shortly.',
    claim_button: 'Claim',
    close_button: 'Close',
    panel_sent: 'Panel sent successfully.',
    panel_title: 'Support Tickets',
    panel_description: 'Select a category below to open a ticket.',
    submit_button: 'Submit',
    error: 'An error occurred. Please try again.',
  },
} as const;

export type TranslationKey = keyof (typeof translations)['en'];

export function t(locale: string | null | undefined, key: TranslationKey, params?: Record<string, string>): string {
  const normLocale: SupportedLocale = locale === 'th' ? 'th' : 'en';
  let template: string = translations[normLocale][key] ?? translations.en[key] ?? key;

  if (params) {
    for (const [k, v] of Object.entries(params)) {
      template = template.replaceAll(`{${k}}`, v);
    }
  }

  return template;
}
