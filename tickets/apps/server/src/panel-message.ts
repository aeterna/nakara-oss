export interface PanelEmbedInput {
  title: string;
  description?: string | null;
  color?: number | null;
  imageUrl?: string | null;
  image_url?: string | null;
  footer?: string | null;
}

export interface PanelButtonInput {
  categoryId?: string;
  category_id?: string;
  label: string;
  emoji?: string | null;
  style?: 'primary' | 'secondary' | 'success' | 'danger' | number;
}

export interface PanelMessageData {
  embed: PanelEmbedInput;
  kind?: 'buttons' | 'select' | string;
  buttons: PanelButtonInput[];
}

export interface CategoryReference {
  id: string;
  name?: string;
  emoji?: string | null;
}

export interface DiscordEmbedOutput {
  title: string;
  description?: string;
  color?: number;
  footer?: { text: string };
  image?: { url: string };
}

export interface DiscordButtonComponent {
  type: 2;
  style: number;
  label: string;
  custom_id: string;
  emoji?: { name: string; id?: string; animated?: boolean };
}

export interface DiscordSelectOption {
  label: string;
  value: string;
  emoji?: { name: string; id?: string; animated?: boolean };
}

export interface DiscordSelectComponent {
  type: 3;
  custom_id: string;
  placeholder?: string;
  options: DiscordSelectOption[];
}

export interface DiscordActionRow {
  type: 1;
  components: Array<DiscordButtonComponent | DiscordSelectComponent | any>;
}

export interface DiscordMessagePayload {
  embeds: DiscordEmbedOutput[];
  components: DiscordActionRow[];
}

function parseEmoji(raw?: string | null): { name: string; id?: string; animated?: boolean } | undefined {
  if (!raw || typeof raw !== 'string' || !raw.trim()) {
    return undefined;
  }
  const trimmed = raw.trim();
  const customMatch = trimmed.match(/^<(a)?:([a-zA-Z0-9_]+):([0-9]+)>$/);
  if (customMatch) {
    return {
      name: customMatch[2],
      id: customMatch[3],
      animated: Boolean(customMatch[1]),
    };
  }
  return { name: trimmed };
}

function mapStyleToNumber(style?: string | number): number {
  if (typeof style === 'number' && style >= 1 && style <= 4) {
    return style;
  }
  switch (style) {
    case 'primary':
      return 1;
    case 'secondary':
      return 2;
    case 'success':
      return 3;
    case 'danger':
      return 4;
    default:
      return 1;
  }
}

export function buildPanelMessage(
  panel: PanelMessageData,
  categories?: CategoryReference[]
): DiscordMessagePayload {
  const embedOut: DiscordEmbedOutput = {
    title: panel.embed.title,
  };

  if (panel.embed.description) {
    embedOut.description = panel.embed.description;
  }
  if (panel.embed.color !== undefined && panel.embed.color !== null) {
    embedOut.color = panel.embed.color;
  }
  if (panel.embed.footer) {
    embedOut.footer = { text: panel.embed.footer };
  }
  const imgUrl = panel.embed.imageUrl ?? panel.embed.image_url;
  if (imgUrl) {
    embedOut.image = { url: imgUrl };
  }

  const buttonsList = panel.buttons || [];

  if (panel.kind === 'select') {
    const options: DiscordSelectOption[] = buttonsList.map((btn) => {
      const catId = btn.categoryId ?? btn.category_id ?? '';
      const cat = Array.isArray(categories) ? categories.find((c) => c.id === catId) : undefined;
      const label = (btn.label || cat?.name || 'Ticket').slice(0, 100);
      const emojiRaw = btn.emoji || cat?.emoji;
      const opt: DiscordSelectOption = {
        label,
        value: catId,
      };
      const emojiObj = parseEmoji(emojiRaw);
      if (emojiObj) {
        opt.emoji = emojiObj;
      }
      return opt;
    });

    return {
      embeds: [embedOut],
      components: [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: 'nt:open-select',
              options,
            },
          ],
        },
      ],
    };
  }

  // Buttons layout: chunks of 5
  const rows: DiscordActionRow[] = [];
  for (let i = 0; i < buttonsList.length; i += 5) {
    const chunk = buttonsList.slice(i, i + 5);
    const components: DiscordButtonComponent[] = chunk.map((btn) => {
      const catId = btn.categoryId ?? btn.category_id ?? '';
      const comp: DiscordButtonComponent = {
        type: 2,
        style: mapStyleToNumber(btn.style),
        label: btn.label || 'Ticket',
        custom_id: `nt:open:${catId}`,
      };
      const emojiObj = parseEmoji(btn.emoji);
      if (emojiObj) {
        comp.emoji = emojiObj;
      }
      return comp;
    });

    rows.push({
      type: 1,
      components,
    });
  }

  return {
    embeds: [embedOut],
    components: rows,
  };
}
