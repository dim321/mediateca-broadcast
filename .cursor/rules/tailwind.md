# Tailwind CSS v4 Rules

You are an expert in Tailwind CSS v4. This version has significant breaking changes from v3. Always use v4 patterns.

## Key Changes in v4

### 1. CSS-First Configuration (No more tailwind.config.js)

```css
/* app.css - Configuration is now in CSS */
@import "tailwindcss";

@theme {
  /* Custom colors */
  --color-brand: #3b82f6;
  --color-brand-dark: #1d4ed8;

  /* Custom fonts */
  --font-display: "Inter", sans-serif;

  /* Custom spacing */
  --spacing-18: 4.5rem;

  /* Custom breakpoints */
  --breakpoint-3xl: 1920px;
}
```

### 2. Import Changed

```css
/* v3 (OLD - don't use) */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* v4 (NEW - use this) */
@import "tailwindcss";
```

### 3. Renamed Utilities

| v3 (Old)              | v4 (New)                |
|-----------------------|-------------------------|
| `flex-grow`           | `grow`                  |
| `flex-shrink`         | `shrink`                |
| `overflow-clip`       | `text-clip`             |
| `decoration-clone`    | `box-decoration-clone`  |
| `decoration-slice`    | `box-decoration-slice`  |
| `bg-opacity-*`        | `bg-{color}/*`          |
| `text-opacity-*`      | `text-{color}/*`        |
| `border-opacity-*`    | `border-{color}/*`      |
| `ring-opacity-*`      | `ring-{color}/*`        |
| `placeholder-{color}` | `placeholder:text-{color}` |

### 4. Opacity Modifier Syntax

```html
<!-- v3 (OLD - don't use) -->
<div class="bg-blue-500 bg-opacity-50">

<!-- v4 (NEW - use this) -->
<div class="bg-blue-500/50">
```

### 5. Gradient Color Stops with Opacity

```html
<!-- v3 (OLD) -->
<div class="from-blue-500 from-opacity-50">

<!-- v4 (NEW) -->
<div class="from-blue-500/50">
```

### 6. Shadow Colors

```html
<!-- v3 (OLD) -->
<div class="shadow-lg shadow-blue-500/50">

<!-- v4 (NEW) - shadow color is part of shadow utility -->
<div class="shadow-lg shadow-blue-500/50">  <!-- Same syntax, but defined differently -->
```

### 7. Container Configuration

```css
/* v4 - Container is configured in CSS */
@utility container {
  margin-inline: auto;
  padding-inline: 1rem;
  max-width: var(--breakpoint-xl);
}
```

### 8. Custom Utilities

```css
/* v4 - Define custom utilities in CSS */
@utility content-auto {
  content-visibility: auto;
}

@utility scrollbar-hidden {
  -ms-overflow-style: none;
  scrollbar-width: none;
  &::-webkit-scrollbar {
    display: none;
  }
}
```

### 9. Custom Variants

```css
/* v4 - Define custom variants in CSS */
@variant hocus (&:hover, &:focus);
@variant group-hocus (group:hover &, group:focus &);
```

### 10. Plugins Replaced by CSS

```css
/* v4 - Typography plugin is now CSS-based */
@plugin "@tailwindcss/typography";

/* Or configure inline */
@theme {
  --typography-body: 1rem;
  --typography-headings: "Inter", sans-serif;
}
```

## Breaking Changes Checklist

When migrating from v3 to v4:

- [ ] Replace `@tailwind` directives with `@import "tailwindcss"`
- [ ] Move `tailwind.config.js` settings to `@theme` in CSS
- [ ] Update `flex-grow` → `grow`, `flex-shrink` → `shrink`
- [ ] Update opacity utilities: `bg-opacity-50` → `bg-{color}/50`
- [ ] Update `placeholder-gray-500` → `placeholder:text-gray-500`
- [ ] Replace JS plugins with CSS `@plugin` or custom utilities
- [ ] Update container configuration to CSS-based approach
- [ ] Check custom colors use `--color-*` naming in `@theme`

## Color Configuration

```css
@theme {
  /* Completely override default colors */
  --color-*: initial;  /* Reset all colors */

  /* Define your palette */
  --color-primary: #3b82f6;
  --color-primary-50: #eff6ff;
  --color-primary-100: #dbeafe;
  --color-primary-500: #3b82f6;
  --color-primary-900: #1e3a8a;

  /* Semantic colors */
  --color-success: #22c55e;
  --color-warning: #f59e0b;
  --color-error: #ef4444;
}
```

## Dark Mode

```css
/* v4 - Dark mode with CSS variables */
@theme {
  --color-background: #ffffff;
  --color-foreground: #000000;
}

@media (prefers-color-scheme: dark) {
  @theme {
    --color-background: #0a0a0a;
    --color-foreground: #ffffff;
  }
}

/* Or with class-based dark mode */
@theme dark {
  --color-background: #0a0a0a;
  --color-foreground: #ffffff;
}
```

## Native CSS Features v4 Embraces

```css
/* Container queries - native support */
@container (min-width: 400px) {
  .card { grid-template-columns: 1fr 1fr; }
}

/* CSS nesting - native support */
.card {
  padding: 1rem;

  & .title {
    font-size: 1.5rem;
  }

  &:hover {
    background: var(--color-gray-100);
  }
}

/* :has() selector support */
.form:has(:invalid) {
  border-color: var(--color-error);
}
```

## PostCSS Configuration

```javascript
// postcss.config.js for v4
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

## Vite Configuration

```javascript
// vite.config.js
import tailwindcss from '@tailwindcss/vite'

export default {
  plugins: [tailwindcss()],
}
```

## Common Mistakes to Avoid

1. **Don't use tailwind.config.js** - Configuration is in CSS now
2. **Don't use @tailwind directives** - Use @import "tailwindcss"
3. **Don't use opacity suffix utilities** - Use slash notation (bg-blue-500/50)
4. **Don't use flex-grow/flex-shrink** - Use grow/shrink
5. **Don't use placeholder-{color}** - Use placeholder:text-{color}
