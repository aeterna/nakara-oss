# Privacy Policy Template for Nakara Tickets

> **Notice to Server Operators:** Under Discord's Developer Terms (§5) and data protection regulations (such as GDPR), you are the Data Controller for your bot instance. Fill in the bracketed placeholders (`[ ... ]`), host this document on a public URL, and link it in the Discord Developer Portal under **General Information -> Privacy Policy URL**.

**Last Updated:** [Date]  
**Application Name:** [Your Bot / Server Name]  
**Operator / Data Controller:** [Server Name / Operator Legal Name or Handle]  
**Contact:** [operator@example.com or Discord Server Link]

---

## 1. What Data We Collect and Store

When you interact with our support ticket system on Discord or the web dashboard, the following information is processed and stored:

1. **Discord Identity Information:**
   - Your Discord user ID, username, and avatar hash.
   - Server (guild) membership and role IDs necessary for permission checks.
2. **Ticket Content and Communications:**
   - Message text, timestamps, and sender IDs sent inside support ticket threads or channels.
   - Message text is encrypted at rest using industry-standard AES-256-GCM encryption.
3. **Attachments:**
   - Media and files uploaded in ticket channels (downloaded strictly from `cdn.discordapp.com` / `media.discordapp.net`).
   - All attachment files are stored encrypted at rest.
4. **Ratings and Feedback:**
   - Ratings (e.g. star ratings) and optional feedback submitted upon ticket closure.
5. **Game Server Actions (when FiveM bridge is enabled):**
   - Player identifier (e.g. FiveM license or Discord ID) used strictly to verify in-game context (e.g. teleport, revive, inventory assistance) requested during support.
6. **Audit and Request Logs:**
   - Timestamps and records of ticket creation, closure, claiming, and data deletion requests.

---

## 2. Why We Collect This Data

We collect this information solely to:
- Facilitate customer support, player assistance, and dispute resolution.
- Enable staff members to review ticket history and investigate past inquiries.
- Provide quality assurance through user ratings and staff audit logs.

We do **not** sell, rent, or monetize your personal data. We do not use your messages for AI training or share your information with third-party advertisers.

---

## 3. Data Retention Period

- **Ticket Transcripts & Attachments:** Retained for a maximum of **[90 days]** (or the server's configured retention limit, default 90 days) following ticket closure. After this period, transcript text and associated files are automatically and permanently purged.
- **Audit Logs:** Retained as long as necessary for administrative accountability and server security.
- **Session Tokens:** Dashboard authentication tokens expire automatically and are discarded upon logout.

---

## 4. How to Delete Your Data (Right to Erasure)

You have the right to request deletion of your personal data at any time:

1. **In Discord:** Run the slash command:
   ```
   /tickets delete-my-data
   ```
   This immediately creates a deletion request and permanently removes all your messages, attachments, and feedback ratings from our database and storage.
2. **Via Web Dashboard:** You can submit a deletion request through the account settings page on the web dashboard.
3. **Contacting Us Directly:** If you cannot access Discord or the dashboard, email [operator@example.com] with your Discord User ID.

---

## 5. Security Measures

- **Encryption at Rest:** All ticket messages, transcripts, and attachment payloads are encrypted at rest with AES-256-GCM.
- **Access Control:** Transcripts are accessible only to authorized server administrators and support staff with verified permissions.
- **Security Headers:** The web dashboard enforces strict Content Security Policy (`CSP`), `X-Content-Type-Options: nosniff`, and secure cookie attributes (`HttpOnly`, `SameSite=Lax`).
- **Isolation:** The bot runs with strictly scoped permissions and never requests Administrator privileges.

---

## 6. Contact Information

For any privacy-related questions, data export requests, or security disclosures, please contact:
- **Email:** [operator@example.com]
- **Discord:** [discord.gg/your-invite or @OperatorHandle]
