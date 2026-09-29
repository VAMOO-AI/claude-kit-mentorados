// src/lib/safe-redirect.ts
// Destino pós-login vindo de `?redirect=`. Só caminho interno: sem isso o login
// vira open redirect (`//evil.com`, `/\evil.com` e `javascript:` passam por um
// `startsWith("/")` ingênuo).
export function safeRedirectPath(raw: string | null | undefined): string {
  if (!raw) return "/";
  if (!raw.startsWith("/") || raw.startsWith("//") || raw.startsWith("/\\")) return "/";
  if (raw === "/login" || raw.startsWith("/login?") || raw.startsWith("/login/")) return "/";
  return raw;
}

// Na tela de login, depois de senha + MFA:
//   window.location.href = safeRedirectPath(new URLSearchParams(window.location.search).get("redirect"));
