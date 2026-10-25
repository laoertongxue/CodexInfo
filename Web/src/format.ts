/** The number formats the panel uses: `1.24M`, `3.3B`, `42.3 tok/s`, `84%`. */
export function formatTokens(value?: number | null): string {
  if (value == null) return "—";
  if (value >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(1)}B`;
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return String(value);
}

export function formatRate(value?: number | null): string {
  return value == null ? "—" : `${value.toFixed(1)} tok/s`;
}

export function formatDateTime(value?: string | number | null): string {
  if (value == null) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("zh-CN", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

/** The same moment in Beijing time; reset times are stated in UTC+8. */
export function formatBeijingDateTime(value?: string | number | null): string {
  if (value == null) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(date);
}

export function formatRemaining(value?: string | number | null, now = Date.now()): string {
  if (value == null) return "—";
  const target = new Date(value).getTime();
  if (Number.isNaN(target)) return "—";
  const minutes = Math.max(0, Math.round((target - now) / 60_000));
  if (minutes < 60) return `${minutes} 分钟`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时`;
  return `${Math.floor(hours / 24)} 天 ${hours % 24} 小时`;
}

/** The placeholder of a value that is not available. */
export const DASH = "—";
