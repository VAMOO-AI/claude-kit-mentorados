"use client";
// src/components/mcp/InstallGuide.tsx — lógica do guia de 4 passos.
// Visual mínimo de propósito: troque por Card/Badge/tokens do projeto alvo.
import React, { useMemo, useSyncExternalStore } from "react";

export const MCP_URL = "https://<dominio>/api/mcp";
export const MCP_NAME = "<nome>";

type ToolId = "claude" | "claude-code" | "chatgpt" | "outro";

const TOOLS: { id: ToolId; label: string; hint: string }[] = [
  { id: "claude", label: "Claude", hint: "app ou web" },
  { id: "claude-code", label: "Claude Code", hint: "terminal" },
  { id: "chatgpt", label: "ChatGPT", hint: "app ou web" },
  { id: "outro", label: "Outro cliente", hint: "MCP remoto" },
];

const STORAGE_KEY = "<nome>-mcp-install-v1";
type Progress = { tool: ToolId | null; done: number[] };
const EMPTY: Progress = { tool: null, done: [] };

function parseProgress(raw: string): Progress {
  if (!raw) return EMPTY;
  try {
    const parsed = JSON.parse(raw) as Partial<Progress>;
    const tool = TOOLS.some((t) => t.id === parsed.tool) ? (parsed.tool as ToolId) : null;
    const done = Array.isArray(parsed.done) ? parsed.done.filter((n) => [1, 2, 3, 4].includes(n)) : [];
    return { tool, done };
  } catch {
    return EMPTY;
  }
}

// Progresso no localStorage via store externo: o servidor vê "" (sem progresso)
// e o cliente troca pelo salvo depois de hidratar, sem mismatch. Sem storage
// (aba anônima, bloqueado) o guia segue funcionando em memória.
let memory = "";
const listeners = new Set<() => void>();

function readRaw(): string {
  try {
    return window.localStorage.getItem(STORAGE_KEY) ?? "";
  } catch {
    return memory;
  }
}

function writeProgress(p: Progress) {
  memory = JSON.stringify(p);
  try {
    window.localStorage.setItem(STORAGE_KEY, memory);
  } catch {
    // fica só em memória
  }
  listeners.forEach((l) => l());
}

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

function AddInstructions({ tool }: { tool: ToolId | null }) {
  if (!tool) return <p>Escolha a ferramenta no passo 1 para ver a instrução.</p>;
  if (tool === "claude-code") {
    return <code>{`claude mcp add --transport http ${MCP_NAME} ${MCP_URL}`}</code>;
  }
  const texto: Record<Exclude<ToolId, "claude-code">, string> = {
    claude: `Configurações → Conectores → Adicionar conector personalizado. Nome ${MCP_NAME}, URL:`,
    chatgpt: "Configurações → Conectores (Apps) → ative o modo desenvolvedor e crie um conector com a URL:",
    outro: "Qualquer cliente de MCP remoto com Streamable HTTP e login OAuth. Cadastre o servidor com a URL:",
  };
  return (
    <div>
      <p>{texto[tool]}</p>
      <code>{MCP_URL}</code>
    </div>
  );
}

export function InstallGuide() {
  const raw = useSyncExternalStore(subscribe, readRaw, () => "");
  const progress = useMemo(() => parseProgress(raw), [raw]);

  const toggleDone = (step: number) =>
    writeProgress({ ...progress, done: progress.done.includes(step) ? progress.done.filter((s) => s !== step) : [...progress.done, step] });
  const chooseTool = (tool: ToolId) => writeProgress({ tool, done: progress.done.includes(1) ? progress.done : [...progress.done, 1] });

  const steps = [
    {
      n: 1,
      title: "Escolha a ferramenta",
      manual: false,
      body: (
        <div role="radiogroup" aria-label="Ferramenta">
          {TOOLS.map((t) => (
            <button key={t.id} type="button" role="radio" aria-checked={progress.tool === t.id} onClick={() => chooseTool(t.id)}>
              {t.label} <small>{t.hint}</small>
            </button>
          ))}
        </div>
      ),
    },
    { n: 2, title: "Adicione o MCP", manual: true, body: <AddInstructions tool={progress.tool} /> },
    {
      n: 3,
      title: "Faça login",
      manual: true,
      body: <p>A ferramenta abre o navegador no login do app. Entre com a sua conta (e o MFA, se pedir) e clique em Permitir. Não há token para copiar.</p>,
    },
    { n: 4, title: "Teste a conexão", manual: true, body: <code>Quem sou eu no &lt;sistema&gt;?</code> },
  ];

  return (
    <section aria-label="Instalação guiada">
      <p>
        {progress.done.length} de 4 passos concluídos
        {progress.done.length > 0 && (
          <button type="button" onClick={() => writeProgress(EMPTY)}>
            Recomeçar
          </button>
        )}
      </p>
      <ol>
        {steps.map((s) => (
          <li key={s.n}>
            <h3>{s.title}</h3>
            {s.manual && (
              <button type="button" aria-pressed={progress.done.includes(s.n)} onClick={() => toggleDone(s.n)}>
                {progress.done.includes(s.n) ? "Feito" : "Marcar como feito"}
              </button>
            )}
            {s.body}
          </li>
        ))}
      </ol>
    </section>
  );
}
