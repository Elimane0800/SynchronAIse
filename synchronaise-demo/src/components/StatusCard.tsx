import "../tokens.css";

export type StatusVariant = "default" | "warning" | "danger";

export interface StatusCardProps {
  variant?: StatusVariant;
  title: string;
  description: string;
  actionLabel?: string;
}

const ACCENT: Record<StatusVariant, string> = {
  default: "var(--color-primary)",
  warning: "var(--color-warning)",
  danger: "var(--color-danger)",
};

export function StatusCard({
  variant = "danger",
  title,
  description,
  actionLabel = "Take action",
}: StatusCardProps) {
  const accent = ACCENT[variant];
  return (
    <div
      data-node="card"
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: "var(--spacing-md)",
        background: "var(--color-surface)",
        borderRadius: "var(--radius-md)",
        padding: "var(--spacing-md)",
        boxShadow: "var(--shadow-md)",
        maxWidth: 420,
        fontFamily: "var(--font-body)",
      }}
    >
      <svg data-node="icon" width="24" height="24" viewBox="0 0 24 24" fill={accent} aria-hidden>
        <circle cx="12" cy="12" r="10" />
      </svg>
      <div data-node="content" style={{ display: "flex", flexDirection: "column", gap: "var(--spacing-sm)", flex: 1 }}>
        <h3 data-node="title" style={{ margin: 0, font: "var(--font-heading)", fontSize: 16, color: "var(--color-text)" }}>
          {title}
        </h3>
        <p data-node="description" style={{ margin: 0, fontFamily: "var(--font-body)", fontSize: 14, color: "var(--color-muted)" }}>
          {description}
        </p>
      </div>
      <button
        data-node="btn-primary"
        style={{
          background: accent,
          color: "#ffffff",
          border: "none",
          borderRadius: "var(--radius-md)",
          padding: "var(--spacing-md)",
          cursor: "pointer",
          fontFamily: "var(--font-body)",
        }}
      >
        {actionLabel}
      </button>
    </div>
  );
}
