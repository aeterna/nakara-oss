ALTER TABLE "guild_settings" ADD COLUMN "attachment_quota_mb" integer DEFAULT 500 NOT NULL;--> statement-breakpoint
ALTER TABLE "guild_settings" ADD COLUMN "auto_close_warn_hours" integer DEFAULT 12 NOT NULL;--> statement-breakpoint
ALTER TABLE "tickets" ADD COLUMN "archived_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "tickets" ADD COLUMN "auto_close_warned_at" timestamp with time zone;