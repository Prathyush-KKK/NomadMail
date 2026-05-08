#!/usr/bin/env node
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { createReadStream, existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = resolve(__dirname, "..");
const cliPath = join(repoRoot, "scripts", "nomad-inbox.ps1");
const installerPath = join(repoRoot, "scripts", "install-windows-agent-helper.ps1");
const startupSystemPromptPath = join(repoRoot, "prompts", "nomadmail-startup.system.md");
const crossChatHandoffPath = join(repoRoot, "prompts", "nomadmail-cross-chat-handoff.md");
const workspaceStatePath = join(repoRoot, "docs", "governance", "WORKSPACE_STATE.md");
const agentUserFlowPath = join(repoRoot, "docs", "runbooks", "agent-user-flow.md");
const versionPath = join(repoRoot, "VERSION");
const serviceVersion = readVersion();

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const windowsToIanaTimeZones = new Map([
  ["India Standard Time", "Asia/Kolkata"],
  ["UTC", "UTC"],
  ["Eastern Standard Time", "America/New_York"],
  ["Central Standard Time", "America/Chicago"],
  ["Mountain Standard Time", "America/Denver"],
  ["Pacific Standard Time", "America/Los_Angeles"],
  ["GMT Standard Time", "Europe/London"],
  ["W. Europe Standard Time", "Europe/Berlin"],
  ["Tokyo Standard Time", "Asia/Tokyo"],
  ["China Standard Time", "Asia/Shanghai"],
  ["AUS Eastern Standard Time", "Australia/Sydney"],
]);

function readVersion() {
  try {
    const version = readFileSync(versionPath, "utf8").trim();
    return version || "0.1.0";
  } catch {
    return "0.1.0";
  }
}

const tools = [
  {
    name: "nomadmail_get_agent_guide",
    description: "Return guidance for agents that need to parse email backups, sync live mail, and hand normalized mail data to a target repository index without accidentally updating NomadInbox storage.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_startup_system_prompt",
    description: "Return the canonical NomadInbox/NomadMail startup system prompt that agents should load automatically when this repository is opened as a workspace.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_workspace_state",
    description: "Return the living NomadInbox workspace state file so agents can resume from durable session state before refreshing live status.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_agent_user_flow",
    description: "Return the definitive user-facing flow from first workspace prompt through daily mail query choices.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_cross_chat_handoff",
    description: "Return the canonical handoff prompt for another AI chat session that needs to connect to this local NomadInbox/NomadMail workspace through MCP, local HTTP, or repo scripts.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_install_windows_helper",
    description: "Install the Windows PowerShell helper that initializes ignored runtime state and lets agents track sync operations and connected account config. Returns an explicit unsupported-platform response on non-Windows hosts.",
    inputSchema: {
      type: "object",
      properties: {
        dataDir: {
          type: "string",
          description: "Optional local NomadInbox data directory for messages, sync status, and action logs.",
        },
        installRoot: {
          type: "string",
          description: "Optional local folder where the helper launcher and status file should be written.",
        },
        startTray: {
          type: "boolean",
          default: false,
          description: "Start the Windows tray app after installing the helper. Use only after user approval.",
        },
        skipUserEnvironment: {
          type: "boolean",
          default: false,
          description: "Skip registering NOMADINBOX_HOME and related user environment variables. Intended for tests and temporary installs.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_health_check",
    description: "Check NomadMail local service, provider configuration, and background worker status.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_list_providers",
    description: "List Gmail API, Outlook Graph, and Outlook Desktop providers with capabilities and configuration state.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_list_accounts",
    description: "List configured local mailbox accounts and their sync settings.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_sync_once",
    description: "Run one NomadMail sync cycle for all enabled accounts or one account id. Writes to NOMADINBOX_DATA_DIR when set; otherwise writes to NomadInbox data.",
    inputSchema: {
      type: "object",
      properties: {
        accountId: {
          type: "string",
          description: "Optional configured account id to sync.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_search_messages",
    description: "Search locally synced live messages and read-only imported archive messages.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Whitespace-separated search terms matched against subject, sender, recipients, snippet, and indexed body text.",
        },
        limit: {
          type: "integer",
          minimum: 1,
          maximum: 100,
          default: 10,
        },
        includeLive: {
          type: "boolean",
          default: true,
        },
        includeArchive: {
          type: "boolean",
          default: true,
        },
        provider: {
          type: "string",
          description: "Optional provider filter such as gmail-api, outlook-graph, outlook-desktop, archive-import, or sample.",
        },
        folder: {
          type: "string",
          description: "Optional folder filter for live messages.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_latest_message",
    description: "Run a one-shot live sync by default, then return the newest live synced message summary. Use this for questions like 'what is the latest email' so answers are not based on stale local state.",
    inputSchema: {
      type: "object",
      properties: {
        accountId: {
          type: "string",
          description: "Optional configured account id to sync before reading the latest message.",
        },
        provider: {
          type: "string",
          description: "Optional provider filter such as gmail-api, outlook-graph, or outlook-desktop.",
        },
        folder: {
          type: "string",
          description: "Optional folder filter for live messages.",
        },
        requireContent: {
          type: "boolean",
          default: true,
          description: "When true, only return a live message with a snippet or locally stored body preview.",
        },
        syncFirst: {
          type: "boolean",
          default: true,
          description: "Keep true for latest-email questions. False is only for diagnostics.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_message",
    description: "Get one locally stored message by NomadMail message id.",
    inputSchema: {
      type: "object",
      required: ["id"],
      properties: {
        id: {
          type: "string",
          description: "NomadMail message id from search results.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_message_actions",
    description: "Return UI-ready, permission-gated mail actions for a discovered message. This does not send, delete, or mutate mail.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "string",
          description: "Optional NomadMail message id. Omit for general mail action guidance.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_backup_status",
    description: "Report how much live and imported email context is locally available.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_get_service_status",
    description: "Get optional background sync worker status and latest sync summary.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_start_service",
    description: "Start the optional user-session background sync worker.",
    inputSchema: {
      type: "object",
      properties: {
        intervalSeconds: {
          type: "integer",
          minimum: 30,
          maximum: 86400,
          description: "Optional worker interval override.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_stop_service",
    description: "Stop the optional user-session background sync worker.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "nomadmail_import_archive",
    description: "Import read-only email export context from EML, MBOX, or NomadMail JSONL. Set NOMADINBOX_DATA_DIR to a target-repo staging folder before calling when NomadInbox storage must not be updated.",
    inputSchema: {
      type: "object",
      required: ["format", "path"],
      properties: {
        format: {
          type: "string",
          enum: ["eml", "mbox", "jsonl"],
        },
        path: {
          type: "string",
          description: "Local file or folder path approved by the user.",
        },
        source: {
          type: "string",
          description: "Source label stored as provenance.",
        },
        maxMessages: {
          type: "integer",
          minimum: 0,
          default: 0,
        },
        includeBodies: {
          type: "boolean",
          default: false,
          description: "Store full archive bodies. Use only when explicitly approved.",
        },
        dryRun: {
          type: "boolean",
          default: false,
        },
      },
      additionalProperties: false,
    },
  },
];

function getStartupSystemPrompt() {
  return readFileSync(startupSystemPromptPath, "utf8").replace(/\r\n/g, "\n").trim();
}

function startupSystemPrompt() {
  return {
    status: "ok",
    service: "NomadMail",
    name: "nomadmail-startup",
    promptType: "system",
    path: startupSystemPromptPath,
    text: getStartupSystemPrompt(),
  };
}

function workspaceState() {
  return {
    status: "ok",
    service: "NomadMail",
    name: "nomadinbox-workspace-state",
    path: workspaceStatePath,
    text: readFileSync(workspaceStatePath, "utf8").replace(/\r\n/g, "\n").trim(),
  };
}

function agentUserFlow() {
  return {
    status: "ok",
    service: "NomadMail",
    name: "nomadmail-agent-user-flow",
    path: agentUserFlowPath,
    text: readFileSync(agentUserFlowPath, "utf8").replace(/\r\n/g, "\n").trim(),
  };
}

function crossChatHandoff() {
  return {
    status: "ok",
    service: "NomadMail",
    name: "nomadmail-cross-chat-handoff",
    path: crossChatHandoffPath,
    text: readFileSync(crossChatHandoffPath, "utf8").replace(/\r\n/g, "\n").trim(),
  };
}

function agentGuide() {
  return {
    status: "ok",
    service: "NomadMail",
    purpose: "Agent guidance for parsing email backups, syncing live mail, and updating a target repository index.",
    runtime: runtimeInfo(),
    timeHandling: timeContext(),
    startupSystemPrompt: startupSystemPrompt(),
    workspaceState: workspaceState(),
    agentUserFlow: agentUserFlow(),
    crossChatHandoff: crossChatHandoff(),
    startupGuidance: [
      "When opened in a user workspace, load startupSystemPrompt.text as the system-level instruction for NomadInbox/NomadMail behavior.",
      "Read workspaceState.text before answering so the latest durable session state is included before live status refresh.",
      "Use agentUserFlow.text as the user-facing conversation contract from first prompt through daily-mail query choices.",
      "Use crossChatHandoff.text when the user wants another chat session or another agent to connect to this same local NomadInbox/NomadMail workspace.",
      "Resolve the user's locale and time zone before parsing relative or ambiguous dates. Store normalized timestamps as UTC ISO 8601, but present user-facing times in the user's locale and time zone.",
      "When the user asks for the latest email, newest mail, recent message, or latest email content, treat that read request as approval to run one request-scoped live sync against already configured/enabled accounts before answering.",
      "On Windows, call nomadmail_install_windows_helper or run scripts/install-windows-agent-helper.ps1 before connecting accounts. This initializes the ignored runtime store, account config, helper launcher, and status file used to track sync operations. Then report tray availability and ask before starting the compiled tray client.",
      "If the user explicitly asks to install, start, or run the service on Windows, start the compiled tray client instead of starting only the raw HTTP server. The tray owns the long-running local HTTP agent service and its popup/menu must not block on sync/status refresh.",
      "Starting the tray is allowed only after user approval and must not turn on auto sync by itself.",
      "After service or tray setup succeeds, keep the response short: tell the user NomadMail is available from the NomadInbox system tray and agents can use the local service. Do not print endpoint lists, raw health JSON, process tables, or search results unless diagnostics were requested.",
      "On non-Windows, do not install the Windows helper or offer Outlook Desktop sync. Explain that the NomadMail MCP server is still Node-based and can expose local JSONL context tools, while live sync requires PowerShell Core plus a supported provider runtime or a future native provider adapter.",
      "Never discover tokens, profiles, exports, connected accounts, or mailbox contents until the user approves the exact source and scope."
    ],
    mcpPortability: {
      serverRuntime: "Node.js MCP/HTTP service intended to start on any OS with Node.js.",
      platformIndependentTools: ["nomadmail_get_agent_guide", "nomadmail_get_cross_chat_handoff", "nomadmail_search_messages", "nomadmail_get_message", "nomadmail_get_message_actions"],
      hostRuntimeTools: ["nomadmail_health_check", "nomadmail_list_providers", "nomadmail_list_accounts", "nomadmail_sync_once", "nomadmail_get_latest_message", "nomadmail_get_backup_status", "nomadmail_get_service_status", "nomadmail_start_service", "nomadmail_stop_service", "nomadmail_import_archive"],
      hostRuntimeRequirement: "Provider sync and archive import currently delegate to the NomadInbox PowerShell core. Windows uses Windows PowerShell by default; non-Windows hosts need pwsh or a future native adapter.",
      windowsOnlyCapabilities: ["Outlook Desktop COM sync", "compiled system tray client", "Windows PowerShell helper install"]
    },
    storageBoundary: {
      defaultDataDir: join(repoRoot, "data"),
      activeDataDir: dataDir(),
      rule: "NomadMail writes to NOMADINBOX_DATA_DIR when that environment variable is set. If it is not set, imports and syncs write to NomadInbox's own data directory.",
      targetRepoRule: "For another repository, start the NomadMail MCP/HTTP service or CLI with NOMADINBOX_DATA_DIR set to a staging folder inside that target repository, for example <targetRepo>\\.nomadmail-staging.",
      rawProviderStore: join(dataDir(), "provider-raw.jsonl"),
      normalizationRule: "Provider adapters store canonical records in messages.jsonl and provider-specific snapshots in provider-raw.jsonl. Agent/UI reads must normalize records before search, summaries, actions, or digest views."
    },
    generatedReportNaming: {
      rule: "For broad email-range markdown, HTML, or JSON reports, include the mail source and a sortable date or time range in the folder or filename so users can manage generated files later.",
      examples: [
        "unread-outlook-2026-04-29-to-2026-05-06.md",
        "unread-outlook-week-of-2026-05-06-index.md",
        "gmail-takeout-2025.md"
      ],
      avoid: [
        "unread-outlook-week.md",
        "latest-mails.md",
        "email-report.md"
      ]
    },
    safeWorkflow: [
      "Confirm the user-approved source path and target repository before reading or importing email backups.",
      "Run a dry-run import first with nomadmail_import_archive dryRun=true to confirm the format and count.",
      "For target repository indexing, set NOMADINBOX_DATA_DIR to <targetRepo>\\.nomadmail-staging before running import or live sync.",
      "Import EML folders, Gmail Takeout MBOX files, or existing NomadMail JSONL through nomadmail_import_archive.",
      "Use the generated archive-messages.jsonl or messages.jsonl as the source for the target repository's importer.",
      "When creating broad email report files for the user, use generatedReportNaming and put the source plus date range in the folder or filename.",
      "Run the target repository's own indexing command after import. Do not assume every repo uses the same index command.",
      "Use nomadmail_search_messages and nomadmail_get_message only after indexing or staging paths are clear."
    ],
    importFormats: {
      eml: "Use for folders of .eml files, including converted Outlook exports.",
      mbox: "Use for Gmail Takeout Mail.mbox files.",
      jsonl: "Use for existing NomadMail/NomadInbox messages.jsonl-style exports.",
      pst: "PST import is not implemented in this bootstrap. Export or convert PST content to EML, or use Outlook Desktop live sync.",
      msg: "MSG import is not implemented in this bootstrap. Convert to EML first."
    },
    liveSyncGuidance: [
      "On Windows, offer the compiled tray client as a status and control surface after installing the helper. The compact tray popup can refresh status, run Sync now, toggle auto sync, and show account status from cached state while refresh and sync run asynchronously. For new accounts, tell the user to ask an agent; the tray must not discover accounts or enable auto sync without approval.",
      "For Windows service-start requests, start or verify the tray and give a short tray status instead of a raw HTTP endpoint report.",
      "Use nomadmail_list_accounts before syncing and verify that only intended accounts are enabled.",
      "For latest-email questions, call nomadmail_get_latest_message with syncFirst=true, or run nomadmail_sync_once before searching live messages. If sync is blocked by disabled accounts, missing auth, or provider failure, say the latest email cannot be confirmed instead of presenting stale local data as definite.",
      "After a message is discovered, show a short action menu instead of stopping at search results. Use nomadmail_get_message_actions for reply, reply all, forward, draft new mail, mark/flag/move/archive/trash options and their permission gates.",
      "Use nomadmail_sync_once for request-driven sync, or nomadmail_start_service only when the user explicitly wants background sync.",
      "Gmail API sync requires NOMADINBOX_GMAIL_ACCESS_TOKEN or a Gmail-scoped gcloud login.",
      "Outlook Graph sync requires NOMADINBOX_GRAPH_ACCESS_TOKEN or an Azure CLI Microsoft Graph token.",
      "Outlook Desktop sync requires the signed-in Windows Outlook profile in the current user session."
    ],
    targetIndexExamples: [
      {
        target: "personal-context-workspace",
        commands: [
          "cd C:\\Users\\prat\\Code\\personal-context-workspace",
          "npm run import:mail-agent-jsonl -- --path <targetRepo>\\.nomadmail-staging --dataset email-backups",
          "npm run index"
        ]
      },
      {
        target: "generic repository",
        commands: [
          "Use the repository's own importer to consume <targetRepo>\\.nomadmail-staging\\archive-messages.jsonl or messages.jsonl.",
          "Run that repository's own index/build command after import."
        ]
      }
    ],
    safetyRules: [
      "Never send, reply, archive, trash, move, or mark mail through NomadMail without explicit action-time user confirmation.",
      "Replies, forwards, and new mail must be drafted first. Send only after the user explicitly approves the saved draft or exact recipients, subject, and body.",
      "Trash/delete actions require double explicit approval: first confirm intent, then ask for a final confirmation naming the message and mailbox effect before any delete/trash call.",
      "Imported archive mail is read-only context and has actionable=false.",
      "Do not import broad personal folders, authenticated cloud data, or mailbox exports unless the user has approved the exact source.",
      "Do not store OAuth tokens, secrets, raw mailbox exports, or generated message stores in git."
    ],
    mailActionGuidance: mailActionGuide(null)
  };
}

function dataDir() {
  return process.env.NOMADINBOX_DATA_DIR || join(repoRoot, "data");
}

function messagesPath() {
  return join(dataDir(), "messages.jsonl");
}

function providerRawPath() {
  return join(dataDir(), "provider-raw.jsonl");
}

function archiveMessagesPath() {
  return join(dataDir(), "archive-messages.jsonl");
}

function archiveIndexPath() {
  return join(dataDir(), "archive-index.jsonl");
}

function runtimeInfo() {
  const isWindows = process.platform === "win32";
  return {
    nodePlatform: process.platform,
    nodeVersion: process.version,
    isWindows,
    repoRoot,
    dataDir: dataDir(),
    powershellCommand: powershellExe(),
    windowsHelperSupported: isWindows,
    outlookDesktopSupported: isWindows,
    mcpServerPortable: true,
    timeContext: timeContext(),
    note: isWindows
      ? "Windows hosts can install the PowerShell helper, use Outlook Desktop COM, and run the tray controller."
      : "Non-Windows hosts can run the Node MCP server and local JSONL context tools. Provider sync/import needs pwsh or a future native adapter; Outlook Desktop and tray are Windows-only.",
  };
}

function timeContext() {
  const resolved = Intl.DateTimeFormat().resolvedOptions();
  const locale = process.env.NOMADINBOX_USER_LOCALE || process.env.NOMADINBOX_USER_CULTURE || resolved.locale || "en-US";
  const timeZone = nodeUserTimeZone();
  const now = new Date();
  return {
    locale,
    timeZone,
    windowsTimeZoneId: process.env.NOMADINBOX_USER_TIME_ZONE || null,
    ianaTimeZoneId: process.env.NOMADINBOX_USER_TIME_ZONE_IANA || null,
    nowUtc: now.toISOString(),
    nowLocal: formatLocalTime(now.toISOString()),
    parsingRule: "Parse ambiguous or relative user times in the user's locale/time zone, then persist UTC ISO 8601."
  };
}

function nodeUserTimeZone() {
  const resolved = Intl.DateTimeFormat().resolvedOptions();
  for (const candidate of [process.env.NOMADINBOX_USER_TIME_ZONE_IANA, process.env.NOMADINBOX_USER_TIME_ZONE, resolved.timeZone, "UTC"]) {
    if (!candidate) {
      continue;
    }
    const normalizedCandidates = [candidate, windowsToIanaTimeZones.get(candidate)].filter(Boolean);
    for (const normalized of normalizedCandidates) {
      try {
        new Intl.DateTimeFormat("en-US", { timeZone: normalized }).format(new Date());
        return normalized;
      } catch {
      }
    }
  }
  return "UTC";
}

function formatLocalTime(value) {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    return null;
  }
  const context = Intl.DateTimeFormat().resolvedOptions();
  const locale = process.env.NOMADINBOX_USER_LOCALE || process.env.NOMADINBOX_USER_CULTURE || context.locale || "en-US";
  const timeZone = nodeUserTimeZone();
  try {
    return new Intl.DateTimeFormat(locale, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      timeZone,
      timeZoneName: "short"
    }).format(date);
  } catch {
    return date.toISOString();
  }
}

function powershellExe() {
  return process.env.NOMADMAIL_POWERSHELL || process.env.NOMADINBOX_POWERSHELL || (process.platform === "win32" ? "powershell.exe" : "pwsh");
}

function platformResponse(action, message) {
  return {
    status: "unsupportedPlatform",
    service: "NomadMail",
    action,
    platform: process.platform,
    runtime: runtimeInfo(),
    message,
  };
}

function parseJsonOutput(stdout) {
  const text = stdout.trim().replace(/^\uFEFF/, "");
  if (text.length === 0) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    const firstObject = text.indexOf("{");
    const firstArray = text.indexOf("[");
    const starts = [firstObject, firstArray].filter((idx) => idx >= 0);
    if (starts.length === 0) {
      throw new Error(`Command did not return JSON: ${text.slice(0, 200)}`);
    }
    const start = Math.min(...starts);
    return JSON.parse(text.slice(start));
  }
}

function runPowerShellJson(filePath, args, unavailableName = "NomadInbox CLI", options = {}) {
  return new Promise((resolvePromise, reject) => {
    const timeoutMs = Number.parseInt(options.timeoutMs || "0", 10);
    const child = spawn(
      powershellExe(),
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", filePath, ...args],
      {
        cwd: repoRoot,
        env: process.env,
        windowsHide: true,
      },
    );

    let stdout = "";
    let stderr = "";
    let completed = false;
    let timer = null;

    function settleResolve(value) {
      if (completed) {
        return;
      }
      completed = true;
      if (timer) {
        clearTimeout(timer);
      }
      resolvePromise(value);
    }

    function settleReject(error) {
      if (completed) {
        return;
      }
      completed = true;
      if (timer) {
        clearTimeout(timer);
      }
      reject(error);
    }

    if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
      timer = setTimeout(() => {
        const wrapped = new Error(`${unavailableName} timed out after ${timeoutMs}ms`);
        wrapped.details = {
          status: "unavailable",
          service: "NomadInbox",
          code: "timeout",
          command: powershellExe(),
          args,
          timeoutMs,
          runtime: runtimeInfo(),
        };
        try {
          child.kill();
        } catch {
        }
        settleReject(wrapped);
      }, timeoutMs);
    }

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (error) => {
      const wrapped = new Error(`${unavailableName} is unavailable through ${powershellExe()}: ${error.message}`);
      wrapped.details = {
        status: "unavailable",
        service: "NomadInbox",
        code: error.code || null,
        command: powershellExe(),
        args,
        runtime: runtimeInfo(),
        guidance: process.platform === "win32"
          ? "Install or repair Windows PowerShell, then run scripts/install-windows-agent-helper.ps1."
          : "Install PowerShell Core as pwsh for CLI-backed tools, or use platform-independent NomadMail MCP tools for local JSONL search and message lookup.",
      };
      settleReject(wrapped);
    });
    child.on("close", (code) => {
      if (completed) {
        return;
      }
      let parsed = null;
      try {
        parsed = parseJsonOutput(stdout);
      } catch (error) {
        settleReject(new Error(`${error.message}${stderr ? `; stderr: ${stderr.trim()}` : ""}`));
        return;
      }

      if (code !== 0) {
        const detail = parsed || { status: "error", error: stderr.trim() || `Exited with code ${code}` };
        const error = new Error(detail.error || `${unavailableName} exited with code ${code}`);
        error.details = detail;
        settleReject(error);
        return;
      }

      settleResolve(parsed);
    });
  });
}

function runCli(args, options = {}) {
  return runPowerShellJson(cliPath, args, "NomadInbox CLI", options);
}

async function safeRunCli(args, options = {}) {
  try {
    return await runCli(args, options);
  } catch (error) {
    return {
      status: "unavailable",
      service: "NomadInbox",
      command: args.join(" "),
      error: error.message,
      details: error.details || null,
    };
  }
}

function normalizeLimit(value) {
  const parsed = Number.parseInt(value ?? "10", 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 10;
  }
  return Math.min(parsed, 100);
}

function lower(value) {
  return String(value ?? "").toLowerCase();
}

function flattenAddress(value) {
  if (!value) {
    return "";
  }
  if (Array.isArray(value)) {
    return value.map(flattenAddress).join(" ");
  }
  if (typeof value === "object") {
    return `${value.name ?? ""} ${value.email ?? ""}`;
  }
  return String(value);
}

function normalizeAddress(value, fallbackName = null, fallbackEmail = "unknown@example.invalid") {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return {
      name: value.name ?? fallbackName,
      email: value.email || fallbackEmail,
    };
  }
  const text = String(value || "").trim();
  const match = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  const email = match ? match[0] : (text || fallbackEmail);
  const nameText = fallbackName || text.replace(/<[^>]+>/g, "").trim().replace(/^"|"$/g, "");
  return {
    name: nameText && nameText !== email ? nameText : null,
    email,
  };
}

function normalizeAddressList(value) {
  if (!value) {
    return [];
  }
  if (Array.isArray(value)) {
    return value.map((item) => normalizeAddress(item)).filter((item) => item.email);
  }
  return String(value)
    .split(/[;,]/)
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => normalizeAddress(item));
}

function normalizeAttachmentList(record) {
  if (Array.isArray(record.attachments) && record.attachments.length > 0) {
    return record.attachments.filter((attachment) => attachment !== null && attachment !== undefined).map((attachment, index) => {
      if (typeof attachment === "string") {
        return { id: String(index + 1), name: attachment, contentType: null, sizeBytes: null, localPath: null };
      }
      return {
        id: String(attachment.id ?? attachment.attachmentId ?? index + 1),
        name: String(attachment.name ?? attachment.fileName ?? attachment.displayName ?? `attachment-${index + 1}`),
        contentType: attachment.contentType ?? attachment.mimeType ?? null,
        sizeBytes: Number.isFinite(Number(attachment.sizeBytes ?? attachment.size)) ? Number(attachment.sizeBytes ?? attachment.size) : null,
        localPath: attachment.localPath ?? null,
      };
    });
  }
  if (record.hasAttachments === true) {
    return [{ id: "provider-attachments", name: "Attachments available from provider", contentType: null, sizeBytes: null, localPath: null }];
  }
  return [];
}

function normalizeCapabilities(record, sourceType) {
  if (Array.isArray(record.capabilities) && record.capabilities.length > 0) {
    return record.capabilities;
  }
  if (record.actionable === false || record.provider === "archive-import" || sourceType === "archive-import") {
    return [];
  }
  const base = ["reply", "replyAll", "forward", "markRead", "markUnread", "move", "archive", "trash"];
  if (record.provider === "gmail-api") {
    return ["reply", "replyAll", "forward", "markRead", "markUnread", "star", "archive", "trash"];
  }
  if (normalizeAttachmentList(record).length > 0) {
    return [...base, "saveAttachment"];
  }
  return base;
}

function normalizeMessageRecord(record, sourceType = "live-sync") {
  const provider = record.provider || "sample";
  const providerMessageId = record.providerMessageId || record.entryId || record.messageId || record.id || null;
  const accountId = record.accountId || null;
  const id = record.id || (providerMessageId ? `${provider}:${providerMessageId}` : null);
  const from = normalizeAddress(record.from, record.fromName ?? null, record.fromEmail ?? "unknown@example.invalid");
  const attachments = normalizeAttachmentList(record);
  const normalizedSourceType = record.sourceType || sourceType;
  const bodyText = record.bodyText ?? record.body ?? null;
  const bodyHtml = record.bodyHtml ?? record.htmlBody ?? null;
  return {
    ...record,
    schemaVersion: record.schemaVersion || 1,
    id,
    accountId,
    provider,
    providerMessageId,
    conversationId: record.conversationId || record.threadId || null,
    threadKey: record.threadKey || record.conversationId || record.threadId || null,
    folder: record.folder || null,
    subject: record.subject || "(no subject)",
    from,
    to: normalizeAddressList(record.to),
    cc: normalizeAddressList(record.cc),
    receivedAt: record.receivedAt || record.receivedUtc || record.received || null,
    sentAt: record.sentAt || null,
    snippet: record.snippet || record.preview || record.bodyPreview || null,
    bodyText,
    bodyHtml,
    bodyTextAvailable: Boolean(record.bodyTextAvailable || bodyText),
    bodyHtmlAvailable: Boolean(record.bodyHtmlAvailable || bodyHtml),
    headers: record.headers && typeof record.headers === "object" ? record.headers : {},
    unread: typeof record.unread === "boolean" ? record.unread : record.isRead === false,
    flagged: Boolean(record.flagged || record.isMarkedAsTask),
    importance: record.importance == null ? null : String(record.importance),
    categories: Array.isArray(record.categories) ? record.categories : [],
    attachments,
    capabilities: normalizeCapabilities(record, normalizedSourceType),
    sourceType: normalizedSourceType,
    sourceProvider: record.sourceProvider || provider,
    actionable: record.actionable !== false && normalizedSourceType !== "archive-import",
    providerRawRef: record.providerRawRef || null,
    rawCaptured: Boolean(record.rawCaptured || record.providerRawRef),
    extractionStatus: record.extractionStatus || "notStarted",
    normalizedAt: record.normalizedAt || null,
  };
}

function searchText(record) {
  const normalized = normalizeMessageRecord(record);
  return lower([
    normalized.id,
    normalized.provider,
    normalized.folder,
    normalized.subject,
    flattenAddress(normalized.from),
    flattenAddress(normalized.to),
    flattenAddress(normalized.cc),
    normalized.snippet,
    normalized.bodyText,
    normalized.bodyHtml,
    record.searchableText,
  ].join(" "));
}

function messageTimestamp(record) {
  const normalized = normalizeMessageRecord(record);
  const parsed = Date.parse(normalized.receivedAt || normalized.sentAt || normalized.importedAt || "");
  return Number.isFinite(parsed) ? parsed : 0;
}

function summarizeMessage(record, sourceType) {
  const normalized = normalizeMessageRecord(record, sourceType);
  const source = normalized.sourceType || sourceType;
  return {
    id: normalized.id,
    schemaVersion: normalized.schemaVersion,
    provider: normalized.provider,
    sourceType: source,
    providerMessageId: normalized.providerMessageId || null,
    conversationId: normalized.conversationId || null,
    threadKey: normalized.threadKey || null,
    folder: normalized.folder || null,
    subject: normalized.subject || "(no subject)",
    from: normalized.from || null,
    to: normalized.to || [],
    receivedAt: normalized.receivedAt || null,
    receivedAtLocal: formatLocalTime(normalized.receivedAt || normalized.sentAt || normalized.importedAt || ""),
    snippet: normalized.snippet || null,
    unread: Boolean(normalized.unread),
    flagged: Boolean(normalized.flagged),
    attachmentCount: normalized.attachments.length,
    actionable: normalized.actionable !== false,
    capabilities: Array.isArray(normalized.capabilities) ? normalized.capabilities : [],
    providerRawRef: normalized.providerRawRef || null,
    rawCaptured: Boolean(normalized.rawCaptured),
    extractionStatus: normalized.extractionStatus || "notStarted",
    actionMenu: compactMailActionMenu(normalized, source),
  };
}

function providerActionCaveat(provider) {
  if (provider === "outlook-desktop") {
    return "Outlook Desktop actions may be unavailable unless Outlook is open in the signed-in Windows user session and COM automation can access the selected message.";
  }
  if (provider === "outlook-graph") {
    return "Outlook Graph actions may be unavailable unless the token includes the required delegated write/send scopes, such as Mail.ReadWrite or Mail.Send.";
  }
  if (provider === "gmail-api") {
    return "Gmail actions may be unavailable unless the account has approved non-readonly scopes. A gmail.readonly setup can sync/search but cannot draft, send, or mutate.";
  }
  if (provider === "archive-import") {
    return "Imported archive messages are read-only context and cannot be replied to, moved, sent from, or deleted through NomadMail.";
  }
  return "Provider actions may be unavailable until the connected account supports the required write/send permissions.";
}

function mailActionPermissionModel() {
  return {
    draftFirst: "Replies, forwards, and new mail must be drafted before any send.",
    sendApproval: "Send only after explicit user approval of the saved draft or the exact recipients, subject, and body.",
    deleteApproval: "Trash/delete requires two explicit confirmations: intent first, then a final confirmation naming the message and mailbox effect.",
    archiveBoundary: "Imported archive messages are read-only. Use live sync to locate a matching actionable provider message before offering mailbox actions.",
    runtimeCaveat: "Actions might not complete if provider permissions or local runtime access are missing. Previous runs found Graph/export paths can be unavailable, and Outlook Desktop actions only work when the local Outlook profile is reachable.",
  };
}

function compactMailActionMenu(record, sourceType) {
  const provider = record.provider || "unknown";
  const capabilities = Array.isArray(record.capabilities) ? record.capabilities : [];
  const actionable = record.actionable !== false && provider !== "archive-import" && sourceType !== "archive-import";
  if (!actionable) {
    return {
      available: false,
      prompt: "This message is read-only context. Ask an agent to find the matching live message before taking mailbox actions.",
      quickActions: ["summarize", "extract follow-up", "find matching live message"],
      blockedReason: "archive-or-non-actionable-message",
      permissionNote: mailActionPermissionModel().archiveBoundary,
    };
  }

  const quickActions = [];
  if (capabilities.includes("reply")) quickActions.push("draft reply");
  if (capabilities.includes("replyAll")) quickActions.push("draft reply all");
  if (capabilities.includes("forward")) quickActions.push("draft forward");
  quickActions.push("draft new mail");
  if (capabilities.includes("markRead") || capabilities.includes("markUnread")) quickActions.push("mark read/unread");
  if (capabilities.includes("flag") || capabilities.includes("unflag") || capabilities.includes("star")) quickActions.push("flag/star");
  if (capabilities.includes("move")) quickActions.push("move");
  if (capabilities.includes("archive")) quickActions.push("archive");
  if (capabilities.includes("trash")) quickActions.push("trash/delete with double confirmation");

  return {
    available: true,
    prompt: "Offer the user quick actions: draft a reply, draft a new mail, or manage the message. Draft/send/delete rules still apply.",
    quickActions,
    permissionNote: "Draft before send. Send needs explicit approval. Trash/delete needs double explicit approval.",
    providerCaveat: providerActionCaveat(provider),
  };
}

function mailActionGuide(record) {
  const permissionModel = mailActionPermissionModel();
  const provider = record?.provider || null;
  const sourceType = record?.sourceType || null;
  const capabilities = Array.isArray(record?.capabilities) ? record.capabilities : [];
  const actionable = Boolean(record) && record.actionable !== false && provider !== "archive-import" && sourceType !== "archive-import";
  const liveActionPreconditions = [
    "The message must be from live sync, not archive import.",
    "The provider must expose the requested capability for that message.",
    "The account must have the required provider permission or local runtime access.",
    "The user must approve the exact action at action time.",
  ];

  return {
    actionable,
    provider,
    sourceType,
    capabilities,
    userPrompt: actionable
      ? "What would you like to do with this email: draft reply, reply all, forward, draft new mail, mark read/unread, flag, move/archive, or trash?"
      : "This message is not currently actionable. I can summarize it or help locate the matching live message before any mailbox action.",
    primaryActions: [
      {
        id: "replyDraft",
        label: "Draft reply",
        enabledWhen: "live message with reply capability",
        steps: ["Ask for the reply intent or draft text.", "Create or present a draft.", "Send only after explicit approval."],
      },
      {
        id: "replyAllDraft",
        label: "Draft reply all",
        enabledWhen: "live message with replyAll capability",
        steps: ["Confirm reply-all is intended.", "Create or present a draft.", "Send only after explicit approval."],
      },
      {
        id: "composeDraft",
        label: "Draft new mail",
        enabledWhen: "connected account supports draft creation",
        steps: ["Collect recipients, subject, and body.", "Create or present a draft.", "Send only after explicit approval."],
      },
    ],
    secondaryActions: [
      { id: "markRead", label: "Mark read/unread", confirmation: "explicit approval required" },
      { id: "flag", label: "Flag/star", confirmation: "explicit approval required" },
      { id: "move", label: "Move/archive", confirmation: "explicit approval required" },
      { id: "trash", label: "Trash/delete", confirmation: "double explicit approval required" },
    ],
    permissionModel,
    liveActionPreconditions,
    providerCaveat: provider ? providerActionCaveat(provider) : "Provider-specific action support must be checked after a live message is selected.",
    implementationNote: "NomadMail currently exposes the action guide and local discovery context. Mutation tools must still be added behind this permission model before agents can execute them through MCP/HTTP.",
  };
}

function hasMessageContent(record) {
  const normalized = normalizeMessageRecord(record);
  return [normalized.snippet, normalized.bodyText, normalized.bodyHtml]
    .some((value) => typeof value === "string" && value.trim().length > 0);
}

function contentPreview(record) {
  const normalized = normalizeMessageRecord(record);
  for (const value of [normalized.snippet, normalized.bodyText, normalized.bodyHtml]) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim().slice(0, 600);
    }
  }
  return null;
}

function syncCompleted(sync) {
  if (!sync || sync.status !== "ok" || !Array.isArray(sync.results)) {
    return false;
  }
  return sync.results.some((result) => ["ok", "completed"].includes(lower(result?.status || "")));
}

async function* readJsonLines(path) {
  if (!existsSync(path)) {
    return;
  }

  const stream = createReadStream(path, { encoding: "utf8" });
  const rl = createInterface({ input: stream, crlfDelay: Infinity });
  for await (const line of rl) {
    const trimmed = line.trim().replace(/^\uFEFF/, "");
    if (trimmed.length === 0) {
      continue;
    }
    try {
      yield JSON.parse(trimmed);
    } catch {
      yield {
        id: null,
        provider: "invalid-jsonl",
        subject: "Invalid JSONL record",
        snippet: trimmed.slice(0, 160),
        actionable: false,
      };
    }
  }
}

function addTopResult(results, item, limit) {
  results.push(item);
  results.sort((a, b) => messageTimestamp(b) - messageTimestamp(a));
  if (results.length > limit) {
    results.length = limit;
  }
}

async function searchMessages(args = {}) {
  const query = lower(args.query || "").trim();
  const tokens = query.length > 0 ? query.split(/\s+/).filter(Boolean) : [];
  const limit = normalizeLimit(args.limit);
  const includeLive = args.includeLive !== false;
  const includeArchive = args.includeArchive !== false;
  const provider = lower(args.provider || "").trim();
  const folder = lower(args.folder || "").trim();
  const results = [];

  async function scan(path, sourceType) {
    for await (const record of readJsonLines(path)) {
      if (!record.id) {
        continue;
      }
      const normalized = normalizeMessageRecord(record, sourceType);
      if (provider && lower(normalized.provider) !== provider) {
        continue;
      }
      if (folder && lower(normalized.folder) !== folder) {
        continue;
      }
      const haystack = searchText(normalized);
      if (tokens.some((token) => !haystack.includes(token))) {
        continue;
      }
      addTopResult(results, summarizeMessage(normalized, sourceType), limit);
    }
  }

  if (includeLive) {
    await scan(messagesPath(), "live-sync");
  }
  if (includeArchive) {
    await scan(archiveIndexPath(), "archive-import");
  }

  return {
    status: "ok",
    service: "NomadMail",
    query,
    limit,
    includeLive,
    includeArchive,
    count: results.length,
    results,
  };
}

async function getLatestMessage(args = {}) {
  const syncFirst = args.syncFirst !== false;
  const requireContent = args.requireContent !== false;
  const provider = lower(args.provider || "").trim();
  const folder = lower(args.folder || "").trim();
  const sync = syncFirst
    ? await syncOnce({ accountId: args.accountId })
    : { status: "skipped", service: "NomadMail", reason: "syncFirst=false" };

  let latest = null;
  let latestWithContent = null;

  for await (const record of readJsonLines(messagesPath())) {
    if (!record.id) {
      continue;
    }
    const normalized = normalizeMessageRecord(record, "live-sync");
    if (provider && lower(normalized.provider) !== provider) {
      continue;
    }
    if (folder && lower(normalized.folder) !== folder) {
      continue;
    }

    if (!latest || messageTimestamp(normalized) > messageTimestamp(latest)) {
      latest = normalized;
    }
    if (hasMessageContent(normalized) && (!latestWithContent || messageTimestamp(normalized) > messageTimestamp(latestWithContent))) {
      latestWithContent = normalized;
    }
  }

  const selected = requireContent ? latestWithContent : latest;
  if (syncFirst && !syncCompleted(sync)) {
    return {
      status: "syncNotFresh",
      service: "NomadMail",
      syncFirst,
      requireContent,
      provider: provider || null,
      folder: folder || null,
      latestLiveSync: sync,
      freshnessRule: "Latest-email questions must run one-shot live sync first. If sync cannot complete, do not present stale local data as definitely latest.",
      message: null,
      contentAvailable: false,
      contentPreview: null,
      actionGuide: mailActionGuide(null),
      reason: "No live account sync completed. The latest email cannot be confirmed from local state.",
    };
  }

  return {
    status: selected ? "ok" : "notFound",
    service: "NomadMail",
    syncFirst,
    requireContent,
    provider: provider || null,
    folder: folder || null,
    latestLiveSync: sync,
    freshnessRule: "Latest-email questions must run one-shot live sync first. If sync cannot complete, do not present stale local data as definitely latest.",
    message: selected ? summarizeMessage(selected, "live-sync") : null,
    contentAvailable: selected ? hasMessageContent(selected) : false,
    contentPreview: selected ? contentPreview(selected) : null,
    actionGuide: selected ? mailActionGuide(selected) : mailActionGuide(null),
    latestLiveMessageWithoutContent: !selected && requireContent && latest ? summarizeMessage(latest, "live-sync") : null,
  };
}

async function getMessage(args = {}) {
  if (!args.id || typeof args.id !== "string") {
    throw new Error("id is required");
  }

  const found = await findMessageRecord(args.id);
  if (found) {
    const normalized = normalizeMessageRecord(found.record, found.record.sourceType || "live-sync");
    return {
      status: "ok",
      service: "NomadMail",
      message: normalized,
      rawRecordShape: found.record.schemaVersion ? "canonical" : "legacy-or-imported",
      actionGuide: mailActionGuide(normalized),
    };
  }

  return {
    status: "notFound",
    service: "NomadMail",
    id: args.id,
  };
}

async function findMessageRecord(id) {
  for (const path of [messagesPath(), archiveMessagesPath()]) {
    for await (const record of readJsonLines(path)) {
      if (record.id === id) {
        return { record, path };
      }
    }
  }
  return null;
}

async function getMessageActions(args = {}) {
  if (!args.id) {
    return {
      status: "ok",
      service: "NomadMail",
      actionGuide: mailActionGuide(null),
    };
  }

  const found = await findMessageRecord(args.id);
  if (!found) {
    return {
      status: "notFound",
      service: "NomadMail",
      id: args.id,
      actionGuide: mailActionGuide(null),
    };
  }

  return {
    status: "ok",
    service: "NomadMail",
    message: summarizeMessage(found.record, found.record.sourceType || "live-sync"),
    actionGuide: mailActionGuide(normalizeMessageRecord(found.record, found.record.sourceType || "live-sync")),
  };
}

async function healthCheck() {
  const healthCliOptions = { timeoutMs: 2500 };
  const [config, providers, serviceStatus] = await Promise.all([
    safeRunCli(["config", "status"], healthCliOptions),
    safeRunCli(["providers", "list"], healthCliOptions),
    safeRunCli(["service", "status"], healthCliOptions),
  ]);
  const cliAvailable = [config, providers, serviceStatus].every((item) => item?.status !== "unavailable");

  return {
    status: "ok",
    service: "NomadMail",
    version: serviceVersion,
    coreService: "NomadInbox",
    repoRoot,
    dataDir: dataDir(),
    runtime: runtimeInfo(),
    timeContext: timeContext(),
    cliAvailable,
    config,
    providers: providers?.providers || [],
    worker: serviceStatus?.worker || "unknown",
    serviceStatus,
  };
}

async function syncOnce(args = {}) {
  const cliArgs = ["sync", "once"];
  if (args.accountId) {
    cliArgs.push("--account-id", String(args.accountId));
  }
  return safeRunCli(cliArgs);
}

async function startService(args = {}) {
  const cliArgs = ["service", "start"];
  if (args.intervalSeconds) {
    cliArgs.push("--interval-seconds", String(args.intervalSeconds));
  }
  return safeRunCli(cliArgs);
}

async function importArchive(args = {}) {
  const format = String(args.format || "").toLowerCase();
  if (!["eml", "mbox", "jsonl"].includes(format)) {
    throw new Error("format must be one of: eml, mbox, jsonl");
  }
  if (!args.path || typeof args.path !== "string") {
    throw new Error("path is required");
  }

  const cliArgs = ["import", format, "--path", args.path];
  if (args.source) {
    cliArgs.push("--source", String(args.source));
  }
  if (args.maxMessages !== undefined) {
    cliArgs.push("--max-messages", String(args.maxMessages));
  }
  if (args.includeBodies) {
    cliArgs.push("--include-bodies");
  }
  if (args.dryRun) {
    cliArgs.push("--dry-run");
  }
  return safeRunCli(cliArgs);
}

async function installWindowsHelper(args = {}) {
  if (process.platform !== "win32") {
    return platformResponse(
      "install-windows-helper",
      "The Windows PowerShell helper, tray controller, and Outlook Desktop sync are Windows-only. Keep using the platform-independent NomadMail MCP server for local JSONL search/message tools, and configure provider sync only when this host has PowerShell Core and a supported provider runtime.",
    );
  }

  const installerArgs = [];
  if (args.dataDir) {
    installerArgs.push("-DataDir", String(args.dataDir));
  }
  if (args.installRoot) {
    installerArgs.push("-InstallRoot", String(args.installRoot));
  }
  if (args.startTray) {
    installerArgs.push("-StartTray");
  }
  if (args.skipUserEnvironment) {
    installerArgs.push("-SkipUserEnvironment");
  }
  return runPowerShellJson(installerPath, installerArgs, "NomadInbox Windows helper installer");
}

async function callTool(name, args = {}) {
  switch (name) {
    case "nomadmail_get_agent_guide":
      return agentGuide();
    case "nomadmail_get_startup_system_prompt":
      return startupSystemPrompt();
    case "nomadmail_get_workspace_state":
      return workspaceState();
    case "nomadmail_get_agent_user_flow":
      return agentUserFlow();
    case "nomadmail_get_cross_chat_handoff":
      return crossChatHandoff();
    case "nomadmail_install_windows_helper":
      return installWindowsHelper(args);
    case "nomadmail_health_check":
      return healthCheck();
    case "nomadmail_list_providers":
      return safeRunCli(["providers", "list"]);
    case "nomadmail_list_accounts":
      return safeRunCli(["accounts", "list"]);
    case "nomadmail_sync_once":
      return syncOnce(args);
    case "nomadmail_search_messages":
      return searchMessages(args);
    case "nomadmail_get_latest_message":
      return getLatestMessage(args);
    case "nomadmail_get_message":
      return getMessage(args);
    case "nomadmail_get_message_actions":
      return getMessageActions(args);
    case "nomadmail_get_backup_status":
      return safeRunCli(["backup", "status"]);
    case "nomadmail_get_service_status":
      return safeRunCli(["service", "status"]);
    case "nomadmail_start_service":
      return startService(args);
    case "nomadmail_stop_service":
      return safeRunCli(["service", "stop"]);
    case "nomadmail_import_archive":
      return importArchive(args);
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

function mcpToolResult(result) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(result, null, 2),
      },
    ],
  };
}

function sendMcp(message) {
  const json = JSON.stringify(message);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`);
}

function sendMcpError(id, code, message, data) {
  sendMcp({
    jsonrpc: "2.0",
    id,
    error: {
      code,
      message,
      data,
    },
  });
}

async function handleMcpMessage(message) {
  if (!message || typeof message !== "object") {
    return;
  }

  const { id, method, params } = message;
  const hasId = Object.prototype.hasOwnProperty.call(message, "id");

  try {
    if (method === "initialize") {
      sendMcp({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: params?.protocolVersion || "2024-11-05",
          capabilities: {
            tools: {},
          },
          serverInfo: {
            name: "nomadmail",
            version: serviceVersion,
          },
        },
      });
      return;
    }

    if (method === "notifications/initialized") {
      return;
    }

    if (method === "ping") {
      sendMcp({ jsonrpc: "2.0", id, result: {} });
      return;
    }

    if (method === "tools/list") {
      sendMcp({
        jsonrpc: "2.0",
        id,
        result: { tools },
      });
      return;
    }

    if (method === "tools/call") {
      const result = await callTool(params?.name, params?.arguments || {});
      sendMcp({
        jsonrpc: "2.0",
        id,
        result: mcpToolResult(result),
      });
      return;
    }

    if (hasId) {
      sendMcpError(id, -32601, `Method not found: ${method}`);
    }
  } catch (error) {
    if (hasId) {
      sendMcpError(id, -32000, error.message, error.details || undefined);
    } else {
      process.stderr.write(`NomadMail MCP notification error: ${error.message}\n`);
    }
  }
}

function startMcp() {
  let buffer = Buffer.alloc(0);

  process.stdin.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    while (true) {
      const headerEnd = buffer.indexOf("\r\n\r\n");
      if (headerEnd < 0) {
        return;
      }

      const header = buffer.slice(0, headerEnd).toString("utf8");
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) {
        buffer = buffer.slice(headerEnd + 4);
        continue;
      }

      const length = Number.parseInt(match[1], 10);
      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + length;
      if (buffer.length < bodyEnd) {
        return;
      }

      const body = buffer.slice(bodyStart, bodyEnd).toString("utf8");
      buffer = buffer.slice(bodyEnd);

      try {
        const message = JSON.parse(body);
        void handleMcpMessage(message);
      } catch (error) {
        sendMcpError(null, -32700, `Parse error: ${error.message}`);
      }
    }
  });

  process.stderr.write("NomadMail MCP server listening on stdio\n");
}

function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, jsonHeaders);
  res.end(JSON.stringify(body, null, 2));
}

function readBody(req) {
  return new Promise((resolvePromise, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString("utf8");
      if (body.length > 1024 * 1024) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (body.trim().length === 0) {
        resolvePromise({});
        return;
      }
      try {
        resolvePromise(JSON.parse(body));
      } catch (error) {
        reject(new Error(`Invalid JSON body: ${error.message}`));
      }
    });
    req.on("error", reject);
  });
}

function booleanQuery(value, defaultValue) {
  if (value === null || value === undefined) {
    return defaultValue;
  }
  return !["0", "false", "no"].includes(String(value).toLowerCase());
}

async function handleHttp(req, res) {
  const url = new URL(req.url || "/", "http://127.0.0.1");

  try {
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, await healthCheck());
      return;
    }
    if (req.method === "GET" && url.pathname === "/agent-guide") {
      sendJson(res, 200, agentGuide());
      return;
    }
    if (req.method === "GET" && url.pathname === "/startup-system-prompt") {
      sendJson(res, 200, startupSystemPrompt());
      return;
    }
    if (req.method === "GET" && url.pathname === "/workspace-state") {
      sendJson(res, 200, workspaceState());
      return;
    }
    if (req.method === "GET" && url.pathname === "/agent-user-flow") {
      sendJson(res, 200, agentUserFlow());
      return;
    }
    if (req.method === "GET" && url.pathname === "/cross-chat-handoff") {
      sendJson(res, 200, crossChatHandoff());
      return;
    }
    if (req.method === "POST" && url.pathname === "/install/windows-helper") {
      sendJson(res, 200, await installWindowsHelper(await readBody(req)));
      return;
    }
    if (req.method === "GET" && url.pathname === "/providers") {
      sendJson(res, 200, await safeRunCli(["providers", "list"]));
      return;
    }
    if (req.method === "GET" && url.pathname === "/accounts") {
      sendJson(res, 200, await safeRunCli(["accounts", "list"]));
      return;
    }
    if (req.method === "POST" && url.pathname === "/sync/once") {
      sendJson(res, 200, await syncOnce(await readBody(req)));
      return;
    }
    if (req.method === "POST" && url.pathname === "/messages/sync") {
      sendJson(res, 200, await syncOnce(await readBody(req)));
      return;
    }
    if (req.method === "POST" && url.pathname === "/messages/latest") {
      sendJson(res, 200, await getLatestMessage(await readBody(req)));
      return;
    }
    if (req.method === "GET" && url.pathname === "/service/status") {
      sendJson(res, 200, await safeRunCli(["service", "status"]));
      return;
    }
    if (req.method === "POST" && url.pathname === "/service/start") {
      sendJson(res, 200, await startService(await readBody(req)));
      return;
    }
    if (req.method === "POST" && url.pathname === "/service/stop") {
      sendJson(res, 200, await safeRunCli(["service", "stop"]));
      return;
    }
    if (req.method === "GET" && url.pathname === "/backup/status") {
      sendJson(res, 200, await safeRunCli(["backup", "status"]));
      return;
    }
    if (req.method === "GET" && url.pathname === "/import/status") {
      sendJson(res, 200, await safeRunCli(["import", "status"]));
      return;
    }
    if (req.method === "GET" && url.pathname === "/messages") {
      sendJson(res, 200, await searchMessages({
        query: url.searchParams.get("query") || "",
        limit: url.searchParams.get("limit") || "10",
        includeLive: booleanQuery(url.searchParams.get("includeLive"), true),
        includeArchive: booleanQuery(url.searchParams.get("includeArchive"), true),
        provider: url.searchParams.get("provider") || "",
        folder: url.searchParams.get("folder") || "",
      }));
      return;
    }
    if (req.method === "GET" && url.pathname === "/message-actions") {
      sendJson(res, 200, await getMessageActions({ id: url.searchParams.get("id") || "" }));
      return;
    }
    if (req.method === "GET" && url.pathname.startsWith("/messages/") && url.pathname.endsWith("/actions")) {
      const id = decodeURIComponent(url.pathname.slice("/messages/".length, -"/actions".length));
      sendJson(res, 200, await getMessageActions({ id }));
      return;
    }
    if (req.method === "GET" && url.pathname.startsWith("/messages/")) {
      sendJson(res, 200, await getMessage({ id: decodeURIComponent(url.pathname.slice("/messages/".length)) }));
      return;
    }
    if (req.method === "POST" && url.pathname.startsWith("/import/")) {
      const format = decodeURIComponent(url.pathname.slice("/import/".length));
      sendJson(res, 200, await importArchive({ ...(await readBody(req)), format }));
      return;
    }

    sendJson(res, 404, {
      status: "notFound",
      service: "NomadMail",
      method: req.method,
      path: url.pathname,
    });
  } catch (error) {
    sendJson(res, 500, {
      status: "error",
      service: "NomadMail",
      error: error.message,
      details: error.details || null,
    });
  }
}

function startHttp(port, host) {
  const server = createServer((req, res) => {
    void handleHttp(req, res);
  });

  server.listen(port, host, () => {
    process.stderr.write(`NomadMail HTTP service listening on http://${host}:${port}\n`);
  });
}

async function selfTest() {
  const providers = await safeRunCli(["providers", "list"]);
  const search = await searchMessages({ query: "", limit: 1 });
  const latest = await getLatestMessage({ syncFirst: false });
  const actionGuide = await getMessageActions({});
  const guide = agentGuide();
  const prompt = startupSystemPrompt();
  const state = workspaceState();
  const flow = agentUserFlow();
  const handoff = crossChatHandoff();
  return {
    status: "ok",
    service: "NomadMail",
    toolCount: tools.length,
    runtime: runtimeInfo(),
    cliAvailable: providers?.status !== "unavailable",
    providerCount: providers?.providers?.length || 0,
    searchStatus: search.status,
    latestMessageStatus: latest.status,
    messageActionsStatus: actionGuide.status,
    agentGuideStatus: guide.status,
    startupSystemPromptStatus: prompt.status,
    workspaceStateStatus: state.status,
    agentUserFlowStatus: flow.status,
    crossChatHandoffStatus: handoff.status,
  };
}

function parseArg(name, defaultValue) {
  const idx = process.argv.indexOf(name);
  if (idx >= 0 && idx + 1 < process.argv.length) {
    return process.argv[idx + 1];
  }
  return defaultValue;
}

function hasArg(name) {
  return process.argv.includes(name);
}

const mode = process.argv[2] || "mcp";

if (mode === "mcp") {
  startMcp();
} else if (mode === "http") {
  const port = Number.parseInt(parseArg("--port", process.env.NOMADMAIL_HTTP_PORT || "8791"), 10);
  const host = parseArg("--host", process.env.NOMADMAIL_HTTP_HOST || "127.0.0.1");
  startHttp(port, host);
} else if (mode === "self-test") {
  selfTest()
    .then((result) => {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    })
    .catch((error) => {
      process.stdout.write(`${JSON.stringify({ status: "error", service: "NomadMail", error: error.message }, null, 2)}\n`);
      process.exitCode = 1;
    });
} else if (mode === "agent-guide") {
  process.stdout.write(`${JSON.stringify(agentGuide(), null, 2)}\n`);
} else if (mode === "system-prompt") {
  process.stdout.write(`${JSON.stringify(startupSystemPrompt(), null, 2)}\n`);
} else if (mode === "workspace-state") {
  process.stdout.write(`${JSON.stringify(workspaceState(), null, 2)}\n`);
} else if (mode === "agent-user-flow") {
  process.stdout.write(`${JSON.stringify(agentUserFlow(), null, 2)}\n`);
} else if (mode === "cross-chat-handoff") {
  process.stdout.write(`${JSON.stringify(crossChatHandoff(), null, 2)}\n`);
} else if (mode === "tools") {
  process.stdout.write(`${JSON.stringify({ status: "ok", service: "NomadMail", tools }, null, 2)}\n`);
} else if (mode === "install-windows-helper") {
  installWindowsHelper({
    dataDir: parseArg("--data-dir", ""),
    installRoot: parseArg("--install-root", ""),
    startTray: hasArg("--start-tray"),
    skipUserEnvironment: hasArg("--skip-user-env"),
  })
    .then((result) => {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    })
    .catch((error) => {
      process.stdout.write(`${JSON.stringify({ status: "error", service: "NomadMail", error: error.message }, null, 2)}\n`);
      process.exitCode = 1;
    });
} else {
  process.stderr.write("Usage: node service/nomadmail-service.mjs [mcp|http|self-test|agent-guide|system-prompt|workspace-state|agent-user-flow|cross-chat-handoff|tools|install-windows-helper]\n");
  process.exitCode = 2;
}
