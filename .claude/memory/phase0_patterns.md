---
name: Phase 0 component patterns
description: Reference patterns from Phase 0 that ALL subsequent phases must follow exactly — style injection, test imports, story format, barrel exports
type: reference
---

## File Triad Pattern
Every component = `ComponentName.tsx` + `ComponentName.test.tsx` + `ComponentName.stories.tsx`

## Component Pattern (see Button.tsx as canonical reference)
- `forwardRef` with explicit props interface exported
- `data-ts-{component-name}` attribute on root element
- `ensureXStyles()` pattern for hover/focus/active CSS injection (unique `id` per component)
- `CSSProperties` const objects for base styles, variant overrides via spread
- `--ts-*` CSS custom properties exclusively — zero hardcoded colors
- `usePress` from `@react-aria/interactions` for accessible press handling
- Lucide icons via `lucide-react`
- `fontWeight` cast pattern: `'var(--ts-*)' as unknown as number` (only allowed cast)

## Test Pattern (see Button.test.tsx)
```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
```

## Story Pattern (see Button.stories.tsx)
```typescript
import type { Meta, StoryObj } from '@storybook/react';
const meta: Meta<typeof Component> = {
  title: '{Category}/{Component}',
  component: Component,
  parameters: { layout: 'padded' }, // or 'centered' for dialogs
};
export default meta;
type Story = StoryObj<typeof Component>;
```

## Barrel Export Pattern
- Domain `index.ts`: `export { Component, type ComponentProps } from './Component';`
- Main `src/index.ts`: re-exports entire domain namespace

## Token Architecture
- Layer 1: `tokens/desk-mock.css` — Desk OKLCH design tokens
- Layer 2: `tokens/brand.css` — Tradesurface brand tokens referencing Layer 1
- Layer 3: `tokens/components.css` — Component-specific tokens referencing Layer 2
- Layer 4: Component CSS — only references `--ts-*` tokens

## Storybook Config
- `.storybook/main.ts` and `.storybook/preview.ts` already configured
- Stories use CSF3 format
- Story titles: `{Category}/{Component}` (e.g., `Chart/ColorPicker`)
