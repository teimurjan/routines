import type { ComponentChildren } from "preact";

type Props = { trail: string[]; title: string; subtitle?: string; children?: ComponentChildren };

// The breadcrumb, the title and the line under it, with optional controls on the right.
export const PageHeader = ({ trail, title, subtitle, children }: Props) => (
  <header class="rt-page-header">
    <div class="rt-page-header__text">
      <nav class="rt-breadcrumb" aria-label="Breadcrumb">
        {trail.map((part, index) => (
          <span class="rt-breadcrumb__part" key={`${index}-${part}`}>
            {index > 0 && <span class="rt-breadcrumb__chevron" aria-hidden="true">›</span>}
            {part}
          </span>
        ))}
      </nav>
      <h1 class="rt-page-header__title">{title}</h1>
      {subtitle && <p class="rt-page-header__subtitle">{subtitle}</p>}
    </div>
    {children && <div class="rt-page-header__trailing">{children}</div>}
  </header>
);
