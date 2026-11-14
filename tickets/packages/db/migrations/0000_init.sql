CREATE TYPE "public"."game_action_status" AS ENUM('queued', 'leased', 'done', 'failed', 'expired');--> statement-breakpoint
CREATE TYPE "public"."ticket_status" AS ENUM('open', 'claimed', 'closed');--> statement-breakpoint
CREATE TABLE "attachments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"ticket_id" uuid NOT NULL,
	"message_id" text,
	"filename" text NOT NULL,
	"content_type" text,
	"size" integer NOT NULL,
	"sha256" text NOT NULL,
	"stored" boolean DEFAULT false NOT NULL,
	"storage_key" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "audit_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"actor_id" text NOT NULL,
	"kind" text NOT NULL,
	"target" text,
	"detail" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "blocks" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"user_id" text NOT NULL,
	"reason" text,
	"created_by" text NOT NULL,
	"expires_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "bridge_nonces" (
	"server_id" uuid NOT NULL,
	"nonce" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "bridge_nonces_server_id_nonce_pk" PRIMARY KEY("server_id","nonce")
);
--> statement-breakpoint
CREATE TABLE "categories" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"name" text NOT NULL,
	"emoji" text,
	"staff_role_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"mode" text DEFAULT 'thread' NOT NULL,
	"parent_channel_id" text NOT NULL,
	"name_template" text DEFAULT 'ticket-{number}' NOT NULL,
	"welcome_message" text,
	"form" jsonb,
	"auto_close_hours" integer,
	"max_open_per_user" integer DEFAULT 1 NOT NULL,
	"game_server_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "data_requests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"user_id" text,
	"kind" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "game_actions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"ticket_id" uuid NOT NULL,
	"server_id" uuid NOT NULL,
	"action" text NOT NULL,
	"params" jsonb,
	"status" "game_action_status" DEFAULT 'queued' NOT NULL,
	"requested_by" text NOT NULL,
	"lease_until" timestamp with time zone,
	"expires_at" timestamp with time zone NOT NULL,
	"result" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "game_servers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"name" text NOT NULL,
	"secret_enc" "bytea" NOT NULL,
	"confirmed" boolean DEFAULT false NOT NULL,
	"edition" text,
	"resource_version" text,
	"protocol" integer DEFAULT 1 NOT NULL,
	"players_online" integer DEFAULT 0,
	"last_seen_at" timestamp with time zone,
	"revoked" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "guild_settings" (
	"guild_id" text PRIMARY KEY NOT NULL,
	"locale" text DEFAULT 'th' NOT NULL,
	"retention_days" integer DEFAULT 90 NOT NULL,
	"log_channel_id" text,
	"rating_dm" boolean DEFAULT false NOT NULL,
	"privacy_policy_url" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "guilds" (
	"guild_id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"icon" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "messages" (
	"id" text PRIMARY KEY NOT NULL,
	"guild_id" text NOT NULL,
	"ticket_id" uuid NOT NULL,
	"author_id" text NOT NULL,
	"author_name" text NOT NULL,
	"is_staff" boolean DEFAULT false NOT NULL,
	"is_system" boolean DEFAULT false NOT NULL,
	"content_enc" "bytea" NOT NULL,
	"edited_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "pair_codes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"code_hash" text NOT NULL,
	"server_name" text,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "panels" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"channel_id" text NOT NULL,
	"message_id" text,
	"embed" jsonb NOT NULL,
	"kind" text NOT NULL,
	"buttons" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ratings" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"ticket_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"staff_id" text,
	"score" integer NOT NULL,
	"feedback" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"token_hash" text NOT NULL,
	"csrf_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tags" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"name" text NOT NULL,
	"body" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ticket_members" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"ticket_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"role" text DEFAULT 'member' NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tickets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"guild_id" text NOT NULL,
	"number" integer NOT NULL,
	"category_id" uuid NOT NULL,
	"status" "ticket_status" DEFAULT 'open' NOT NULL,
	"opener_id" text NOT NULL,
	"claimer_id" text,
	"channel_id" text NOT NULL,
	"answers" jsonb,
	"first_response_at" timestamp with time zone,
	"last_activity_at" timestamp with time zone,
	"closed_at" timestamp with time zone,
	"close_reason" text,
	"reopened_count" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bridge_nonces" ADD CONSTRAINT "bridge_nonces_server_id_game_servers_id_fk" FOREIGN KEY ("server_id") REFERENCES "public"."game_servers"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "categories" ADD CONSTRAINT "categories_game_server_id_game_servers_id_fk" FOREIGN KEY ("game_server_id") REFERENCES "public"."game_servers"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "game_actions" ADD CONSTRAINT "game_actions_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "game_actions" ADD CONSTRAINT "game_actions_server_id_game_servers_id_fk" FOREIGN KEY ("server_id") REFERENCES "public"."game_servers"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "guild_settings" ADD CONSTRAINT "guild_settings_guild_id_guilds_guild_id_fk" FOREIGN KEY ("guild_id") REFERENCES "public"."guilds"("guild_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ratings" ADD CONSTRAINT "ratings_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ticket_members" ADD CONSTRAINT "ticket_members_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tickets" ADD CONSTRAINT "tickets_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "blocks_guild_id_user_id_idx" ON "blocks" USING btree ("guild_id","user_id");--> statement-breakpoint
CREATE INDEX "bridge_nonces_expires_at_idx" ON "bridge_nonces" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "game_actions_server_id_status_idx" ON "game_actions" USING btree ("server_id","status");--> statement-breakpoint
CREATE INDEX "messages_ticket_id_idx" ON "messages" USING btree ("ticket_id");--> statement-breakpoint
CREATE UNIQUE INDEX "pair_codes_code_hash_idx" ON "pair_codes" USING btree ("code_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "ratings_ticket_id_user_id_idx" ON "ratings" USING btree ("ticket_id","user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "sessions_token_hash_idx" ON "sessions" USING btree ("token_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "tags_guild_id_name_idx" ON "tags" USING btree ("guild_id","name");--> statement-breakpoint
CREATE UNIQUE INDEX "ticket_members_ticket_id_user_id_idx" ON "ticket_members" USING btree ("ticket_id","user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "tickets_guild_id_number_idx" ON "tickets" USING btree ("guild_id","number");--> statement-breakpoint
CREATE INDEX "tickets_guild_id_status_idx" ON "tickets" USING btree ("guild_id","status");