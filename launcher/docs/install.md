# Installing the launcher

ภาษาไทยอยู่ด้านล่าง · [Thai below](#ติดตั้ง-launcher)

1. Download `aeterna-launcher-<version>-windows-x64.zip` from the
   [releases page](https://github.com/aeterna/nakara-oss/releases?q=launcher-v). Do not take it from anywhere else.
2. Extract the whole zip into a folder of your own. Keep `rongroi-connect` next to `aeterna-launcher.exe`.
3. Open `aeterna-launcher.exe`.

**If Windows says "Windows protected your PC":** the exe has no Windows code-signing certificate, so SmartScreen may
stop it the first time. Choose **More info**, check that the file is `aeterna-launcher.exe`, then **Run anyway**. If
you did not download it from the page above, do not run it.

**Check the download (optional).** Compare the zip with `SHA256SUMS` on the same release page:

```
certutil -hashfile aeterna-launcher-<version>-windows-x64.zip SHA256
```

With the GitHub CLI you can also check that this repository's release workflow built it:

```
gh attestation verify aeterna-launcher-<version>-windows-x64.zip --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/launcher-release.yml
```

**Updates.** The launcher tells you when a newer verified version exists and links to its release page. It does not
install anything by itself: download the new zip and replace the folder.

What the launcher sends over the network: [privacy.md](privacy.md).

---

## ติดตั้ง launcher

1. ดาวน์โหลด `aeterna-launcher-<version>-windows-x64.zip` จาก
   [หน้า releases](https://github.com/aeterna/nakara-oss/releases?q=launcher-v) เท่านั้น
2. แตกไฟล์ zip ทั้งหมดลงในโฟลเดอร์ของคุณ โดยให้โฟลเดอร์ `rongroi-connect` อยู่ข้าง `aeterna-launcher.exe`
3. เปิด `aeterna-launcher.exe`

**ถ้า Windows ขึ้นว่า "Windows protected your PC":** ไฟล์นี้ไม่มีใบรับรอง code signing ของ Windows SmartScreen จึงอาจ
กันไว้ในครั้งแรก ให้กด **More info** ดูว่าชื่อไฟล์คือ `aeterna-launcher.exe` แล้วกด **Run anyway** ถ้าไม่ได้ดาวน์โหลดจากหน้าด้านบน
อย่าเปิดไฟล์นั้น

**ตรวจไฟล์ที่ดาวน์โหลด (ไม่บังคับ):** เทียบ zip กับ `SHA256SUMS` ในหน้า release เดียวกัน ด้วยคำสั่ง `certutil` ด้านบน

**การอัปเดต:** launcher จะแจ้งเมื่อมีรุ่นใหม่ที่ตรวจลายเซ็นผ่าน พร้อมลิงก์ไปหน้า release แต่จะไม่ติดตั้งเอง ให้ดาวน์โหลด zip ใหม่แล้วแทนที่โฟลเดอร์เดิม

launcher ส่งอะไรออกเน็ตบ้าง: [privacy.md](privacy.md)
