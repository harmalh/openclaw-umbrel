# Upstream Issue Draft: Config Page Scroll Issue in Embedded Contexts

This document contains a draft issue/PR for the upstream Clawdbot repository regarding the Config page scrolling issue.

---

## Issue Title

**[UI] Config page doesn't scroll when Control UI is embedded in an iframe**

## Issue Body

### Summary

When the Clawdbot Control UI is embedded in an iframe (e.g., via Umbrel's `app_proxy`), the Config page content doesn't scroll. The content overflows the visible area but no scrollbar appears and scroll events have no effect.

### Environment

- **Clawdbot Version:** v2026.1.24
- **Browser:** Chrome 120+, Firefox 120+, Safari 17+
- **Context:** Embedded in iframe via Umbrel OS `app_proxy` service
- **Viewport:** Varies (tested at 1920x1080, 1366x768)

### Steps to Reproduce

1. Deploy Clawdbot in an environment where the Control UI is served through a reverse proxy or iframe (e.g., Umbrel)
2. Open the Control UI
3. Navigate to the **Config** tab
4. Observe that the config content area doesn't scroll

### Expected Behavior

The `.config-content` element should scroll vertically when its content exceeds the visible area.

### Actual Behavior

- The content overflows but no scrollbar appears
- Attempting to scroll (mouse wheel, trackpad, programmatic `scrollTop` changes) has no effect
- The `.config-content` element's `scrollHeight` equals its full content height (e.g., 81665px) instead of being constrained

### Root Cause Analysis

The issue is caused by the CSS layout in `ui/src/styles/config.css`:

**Problematic code (v2026.1.24):**

```css
.config-layout {
  /* ... */
  min-height: calc(100vh - 140px);  /* ← Problem: allows unbounded growth */
  /* ... */
}

.config-sidebar {
  display: flex;
  flex-direction: column;
  /* Missing: min-height: 0; overflow: hidden; */
}

.config-main {
  display: flex;
  flex-direction: column;
  /* Missing: min-height: 0; overflow: hidden; */
}
```

When a flex container doesn't have `min-height: 0`, its default `min-height: auto` prevents children from shrinking below their content size. This means the `overflow-y: auto` on `.config-content` never activates because its parent (`.config-main`) grows to accommodate all content.

### Proposed Fix

Change `.config-layout` to use `height` instead of `min-height`, and add `min-height: 0; overflow: hidden` to the flex children:

```css
.config-layout {
  /* ... */
  height: calc(100vh - 160px);  /* Fixed height, not min-height */
  /* ... */
}

.config-sidebar {
  display: flex;
  flex-direction: column;
  min-height: 0;      /* Allow shrinking below content size */
  overflow: hidden;   /* Contain overflow within bounds */
}

.config-main {
  display: flex;
  flex-direction: column;
  min-height: 0;      /* Allow shrinking below content size */  
  overflow: hidden;   /* Contain overflow within bounds */
}

/* .config-content already has overflow-y: auto - this will now work */
```

### Note on Upstream `main`

I noticed that the `main` branch already includes these changes (as of commit ~Jan 25, 2026). If this fix has been merged but not yet released, requesting a patch release that includes it would be helpful for users running Clawdbot in embedded contexts.

### Workaround

For users affected by this issue before an upstream fix is released, adding a CSS override with the above styles resolves the issue.

---

## Additional Issue: Header Clipping

### Summary

The `.content-header` element has `max-height: 90px` with `overflow: hidden`, which can clip the header text when:
- The page title or subtitle wraps to multiple lines
- Additional metadata is displayed in the header area

### Proposed Fix

Increase the `max-height` or make it responsive:

```css
.content-header {
  max-height: 120px;  /* Increased from 90px */
  /* or use: max-height: none; for no constraint */
}
```

This preserves the chat-focus collapse animation (which uses `max-height` for the transition) while preventing clipping in normal display.

---

## Labels Suggestion

- `bug`
- `ui`
- `control-ui`
- `embedded`

---

## PR Alternative

If submitting a PR instead of an issue, the changes would be to `ui/src/styles/config.css` and optionally `ui/src/styles/layout.css`:

**Files to modify:**
- `ui/src/styles/config.css` - Main scroll fix
- `ui/src/styles/layout.css` - Header max-height (optional)

The PR should include:
1. The CSS changes described above
2. A note in the commit message about iframe/embedded context compatibility
3. Testing instructions for verifying in both standalone and embedded modes
