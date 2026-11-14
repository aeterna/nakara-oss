import type { DiscordPort } from '../src/types.js';

export interface SentMessage {
  id: string;
  channelId: string;
  payload: { content?: string; embeds?: any[]; components?: any[] };
}

export interface CreatedThread {
  id: string;
  channelId: string;
  name: string;
  members: string[];
  locked: boolean;
  archived: boolean;
}

export interface ShownModal {
  interaction: any;
  modal: { customId: string; title: string; components: any[] };
}

export interface EphemeralReply {
  interaction: any;
  message: string | { content: string; embeds?: any[]; components?: any[] };
}

export class FakeDiscordPort implements DiscordPort {
  threads: Map<string, CreatedThread> = new Map();
  messages: SentMessage[] = [];
  modals: ShownModal[] = [];
  ephemeralReplies: EphemeralReply[] = [];
  deferredReplies: { interaction: any; opts?: { ephemeral?: boolean } }[] = [];
  editedReplies: { interaction: any; message: string | { content: string; embeds?: any[]; components?: any[] } }[] = [];
  private nextThreadId = 1000;
  private nextMessageId = 5000;

  async createPrivateThread(channelId: string, name: string): Promise<{ id: string; name: string }> {
    const id = String(this.nextThreadId++);
    const thread: CreatedThread = {
      id,
      channelId,
      name,
      members: [],
      locked: false,
      archived: false,
    };
    this.threads.set(id, thread);
    return { id, name };
  }

  async addMember(threadId: string, userId: string): Promise<void> {
    const thread = this.threads.get(threadId);
    if (thread) {
      thread.members.push(userId);
    }
  }

  async sendMessage(
    channelId: string,
    payload: { content?: string; embeds?: any[]; components?: any[] }
  ): Promise<{ id: string }> {
    const id = String(this.nextMessageId++);
    this.messages.push({ id, channelId, payload });
    return { id };
  }

  async editMessage(
    channelId: string,
    messageId: string,
    payload: { content?: string; embeds?: any[]; components?: any[] }
  ): Promise<void> {
    const msg = this.messages.find((m) => m.id === messageId && m.channelId === channelId);
    if (msg) {
      msg.payload = { ...msg.payload, ...payload };
    }
  }

  async showModal(interaction: any, modal: { customId: string; title: string; components: any[] }): Promise<void> {
    this.modals.push({ interaction, modal });
  }

  async replyEphemeral(
    interaction: any,
    message: string | { content: string; embeds?: any[]; components?: any[] }
  ): Promise<void> {
    this.ephemeralReplies.push({ interaction, message });
  }

  async deferReply(interaction: any, opts?: { ephemeral?: boolean }): Promise<void> {
    this.deferredReplies.push({ interaction, opts });
  }

  async editReply(
    interaction: any,
    message: string | { content: string; embeds?: any[]; components?: any[] }
  ): Promise<void> {
    this.editedReplies.push({ interaction, message });
  }

  async lockAndArchiveThread(threadId: string): Promise<void> {
    const thread = this.threads.get(threadId);
    if (thread) {
      thread.locked = true;
      thread.archived = true;
    }
  }
}
