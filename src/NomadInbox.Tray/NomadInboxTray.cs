using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace NomadInbox.Tray
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            var options = TrayOptions.Parse(args);
            bool created;
            using (var mutex = new Mutex(true, "NomadInboxTray-" + StableHash(options.RepoRoot.ToLowerInvariant()), out created))
            {
                if (!created)
                {
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var app = new TrayApplication(options))
                {
                    app.Run();
                }
            }
        }

        private static string StableHash(string value)
        {
            unchecked
            {
                var hash = 23;
                foreach (var ch in value)
                {
                    hash = (hash * 31) + ch;
                }
                return Math.Abs(hash).ToString(CultureInfo.InvariantCulture);
            }
        }
    }

    internal sealed class TrayOptions
    {
        public string RepoRoot { get; private set; }
        public string DataDir { get; private set; }
        public string Host { get; private set; }
        public int Port { get; private set; }
        public string IconPath { get; private set; }

        public string BaseUrl
        {
            get { return "http://" + Host + ":" + Port.ToString(CultureInfo.InvariantCulture); }
        }

        public static TrayOptions Parse(string[] args)
        {
            var repoRoot = AppDomain.CurrentDomain.BaseDirectory;
            var dataDir = "";
            var host = "127.0.0.1";
            var port = 8791;

            for (var i = 0; i < args.Length; i++)
            {
                var key = args[i];
                var value = (i + 1) < args.Length ? args[i + 1] : "";
                if (key == "--repo-root" && value.Length > 0)
                {
                    repoRoot = value;
                    i++;
                }
                else if (key == "--data-dir" && value.Length > 0)
                {
                    dataDir = value;
                    i++;
                }
                else if (key == "--host" && value.Length > 0)
                {
                    host = value;
                    i++;
                }
                else if (key == "--port" && value.Length > 0)
                {
                    int.TryParse(value, out port);
                    if (port <= 0) port = 8791;
                    i++;
                }
            }

            repoRoot = Path.GetFullPath(repoRoot);
            if (string.IsNullOrWhiteSpace(dataDir))
            {
                var configuredDataDir = Environment.GetEnvironmentVariable("NOMADINBOX_DATA_DIR");
                dataDir = string.IsNullOrWhiteSpace(configuredDataDir)
                    ? Path.Combine(repoRoot, "data")
                    : configuredDataDir;
            }

            return new TrayOptions
            {
                RepoRoot = repoRoot,
                DataDir = Path.GetFullPath(dataDir),
                Host = host,
                Port = port,
                IconPath = Path.Combine(repoRoot, "assets", "nomadinbox-tray.ico")
            };
        }
    }

    internal sealed class TrayApplication : IDisposable
    {
        private readonly TrayOptions options;
        private readonly Form invoker;
        private readonly NotifyIcon notify;
        private readonly ContextMenuStrip menu;
        private readonly System.Windows.Forms.Timer refreshTimer;
        private readonly JavaScriptSerializer serializer;
        private readonly object stateLock = new object();
        private readonly Icon appIcon;
        private readonly bool ownsAppIcon;
        private TrayState state = TrayState.Initial();
        private Process httpProcess;
        private bool httpStartedByTray;
        private bool refreshInFlight;
        private bool disposed;
        private SettingsForm settingsForm;

        public TrayApplication(TrayOptions options)
        {
            this.options = options;
            serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 100 };
            appIcon = LoadAppIcon(options.IconPath, out ownsAppIcon);

            invoker = new Form
            {
                ShowInTaskbar = false,
                WindowState = FormWindowState.Minimized,
                Opacity = 0
            };
            invoker.Load += (sender, args) => invoker.Hide();

            notify = new NotifyIcon
            {
                Icon = appIcon,
                Text = "NomadInbox - starting",
                Visible = true
            };
            menu = new ContextMenuStrip();
            menu.Opening += (sender, args) => BuildMenuFromCache();
            notify.ContextMenuStrip = menu;
            notify.MouseUp += (sender, args) =>
            {
                if (args.Button == MouseButtons.Left || args.Button == MouseButtons.Right)
                {
                    BuildMenuFromCache();
                    menu.Show(Cursor.Position);
                }
            };
            notify.DoubleClick += (sender, args) =>
            {
                BuildMenuFromCache();
                menu.Show(Cursor.Position);
            };

            refreshTimer = new System.Windows.Forms.Timer { Interval = 30000 };
            refreshTimer.Tick += (sender, args) => BeginRefresh("timer");
        }

        public void Run()
        {
            invoker.Show();
            invoker.Hide();
            Directory.CreateDirectory(options.DataDir);
            LoadCachedStatusAsync();
            BeginRefresh("startup");
            refreshTimer.Start();
            notify.ShowBalloonTip(2500, "NomadInbox", "NomadInbox is running. Click the tray icon for sync, auto sync, and status.", ToolTipIcon.Info);
            Application.Run(new ApplicationContext());
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            refreshTimer.Stop();
            refreshTimer.Dispose();
            if (settingsForm != null && !settingsForm.IsDisposed) settingsForm.Close();
            StopHttpServiceIfOwned();
            notify.Visible = false;
            notify.Dispose();
            if (ownsAppIcon) appIcon.Dispose();
            menu.Dispose();
            invoker.Dispose();
        }

        private void LoadCachedStatusAsync()
        {
            Task.Run(() =>
            {
                var cached = ReadCachedState();
                UpdateState(cached);
            });
        }

        private void BeginRefresh(string reason)
        {
            if (refreshInFlight) return;
            refreshInFlight = true;
            Task.Run(async () =>
            {
                try
                {
                    await EnsureHttpServiceAsync();
                    var serviceTask = RequestJsonAsync("GET", "/service/status", null, 3500);
                    var accountsTask = RequestJsonAsync("GET", "/accounts", null, 3500);
                    var backupTask = RequestJsonAsync("GET", "/backup/status", null, 3500);
                    await Task.WhenAll(serviceTask, accountsTask, backupTask);
                    var refreshed = BuildState(serviceTask.Result, accountsTask.Result, backupTask.Result, true, reason);
                    UpdateState(refreshed);
                }
                catch (Exception ex)
                {
                    var cached = ReadCachedState();
                    cached.HttpStatus = "unavailable";
                    cached.LastMessage = "Status refresh failed: " + ex.Message;
                    UpdateState(cached);
                }
                finally
                {
                    refreshInFlight = false;
                }
            });
        }

        private TrayState ReadCachedState()
        {
            var cached = TrayState.Initial();
            cached.DataDir = options.DataDir;
            cached.HttpUrl = options.BaseUrl;
            cached.HttpStatus = "checking";
            cached.LastMessage = "Using cached sync status.";

            var statusPath = Path.Combine(options.DataDir, "sync-status.json");
            var pidPath = Path.Combine(options.DataDir, "sync-worker.pid");
            var messagesPath = Path.Combine(options.DataDir, "messages.jsonl");
            var archivePath = Path.Combine(options.DataDir, "archive-messages.jsonl");
            cached.StatusPath = statusPath;
            cached.Worker = File.Exists(pidPath) ? "running" : "stopped";
            cached.LiveMessages = CountLines(messagesPath);
            cached.ArchiveMessages = CountLines(archivePath);

            try
            {
                if (File.Exists(statusPath))
                {
                    var parsed = ParseJson(File.ReadAllText(statusPath, Encoding.UTF8));
                    cached.LastRunAt = FormatLocalTime(GetString(parsed, "lastRunAt", ""));
                    cached.NextRunAt = FormatLocalTime(GetString(parsed, "nextRunAt", ""));
                    var worker = GetString(parsed, "worker", "");
                    if (!string.IsNullOrWhiteSpace(worker)) cached.Worker = worker;
                    cached.AccountRows = AccountRowsFromSyncStatus(GetList(parsed, "accounts"));
                }
            }
            catch (Exception ex)
            {
                cached.LastMessage = "Cached status unavailable: " + ex.Message;
            }

            return cached;
        }

        private TrayState BuildState(Dictionary<string, object> service, Dictionary<string, object> accounts, Dictionary<string, object> backup, bool httpRunning, string reason)
        {
            var serviceSyncStatus = GetDictionary(service, "syncStatus");
            var serviceBackup = GetDictionary(service, "backupStatus");
            var backupStatus = backup.Count > 0 ? backup : serviceBackup;
            var rows = AccountRowsFromAccounts(GetList(accounts, "accounts"), GetList(serviceSyncStatus, "accounts"));

            return new TrayState
            {
                DataDir = options.DataDir,
                HttpUrl = options.BaseUrl,
                HttpStatus = httpRunning ? "running" : "stopped",
                Worker = GetString(service, "worker", GetString(serviceSyncStatus, "worker", "unknown")),
                LastRunAt = FormatLocalTime(GetString(serviceSyncStatus, "lastRunAt", "")),
                NextRunAt = FormatLocalTime(GetString(serviceSyncStatus, "nextRunAt", "")),
                LiveMessages = GetInt(backupStatus, "liveSyncedMessages", CountLines(Path.Combine(options.DataDir, "messages.jsonl"))),
                ArchiveMessages = GetInt(backupStatus, "archiveImportedMessages", CountLines(Path.Combine(options.DataDir, "archive-messages.jsonl"))),
                TotalAccounts = rows.Count,
                EnabledAccounts = rows.Count(row => row.Enabled),
                AccountRows = rows,
                StatusPath = GetString(service, "statusPath", Path.Combine(options.DataDir, "sync-status.json")),
                LastUpdatedAt = DateTime.Now,
                LastMessage = "Status refreshed from " + reason + "."
            };
        }

        private void UpdateState(TrayState next)
        {
            if (disposed) return;
            lock (stateLock)
            {
                state = next;
            }

            BeginUi(() =>
            {
                var worker = next.Worker == "running" ? "auto sync on" : "auto sync off";
                notify.Text = ClampNotifyText("NomadInbox - " + worker);
                if (settingsForm != null && !settingsForm.IsDisposed)
                {
                    settingsForm.Render(next, refreshInFlight);
                }
            });
        }

        private void BuildMenuFromCache()
        {
            var snapshot = GetSnapshot();
            menu.Items.Clear();

            AddMenuItem("Sync now", true, (sender, args) => BeginManualSync());

            var autoText = snapshot.Worker == "running" ? "Auto sync: on (turn off)" : "Auto sync: off (turn on)";
            var autoItem = AddMenuItem(autoText, true, (sender, args) => BeginToggleAutoSync());
            autoItem.Checked = snapshot.Worker == "running";

            menu.Items.Add(new ToolStripSeparator());
            AddMenuItem("HTTP: " + snapshot.HttpStatus + " at " + options.BaseUrl, false, null);
            AddMenuItem("Messages: " + snapshot.LiveMessages + " live / " + snapshot.ArchiveMessages + " archive", false, null);
            AddMenuItem("Last sync: " + EmptyAs(snapshot.LastRunAt, "not recorded"), false, null);
            AddMenuItem("Next sync: " + EmptyAs(snapshot.NextRunAt, "not scheduled"), false, null);

            menu.Items.Add(new ToolStripSeparator());
            AddMenuItem("Accounts", false, null);
            if (snapshot.AccountRows.Count == 0)
            {
                AddMenuItem("No accounts configured", false, null);
            }
            else
            {
                foreach (var row in snapshot.AccountRows.Take(8))
                {
                    AddMenuItem(row.Label + ": " + row.StatusText, false, null);
                }
                if (snapshot.AccountRows.Count > 8)
                {
                    AddMenuItem("More accounts in Settings", false, null);
                }
            }

            menu.Items.Add(new ToolStripSeparator());
            AddMenuItem("Ask your agent if you want to connect new accounts.", false, null);
            AddMenuItem("Refresh status", true, (sender, args) => BeginRefresh("manual"));
            AddMenuItem("Settings and diagnostics...", true, (sender, args) => ShowSettings());
            AddMenuItem("Open runtime folder", true, (sender, args) => OpenRuntimeFolder());
            menu.Items.Add(new ToolStripSeparator());
            AddMenuItem("Exit tray", true, (sender, args) => ExitTray());
        }

        private ToolStripMenuItem AddMenuItem(string text, bool enabled, EventHandler click)
        {
            var item = new ToolStripMenuItem(text) { Enabled = enabled };
            if (click != null) item.Click += click;
            menu.Items.Add(item);
            return item;
        }

        private void BeginManualSync()
        {
            var snapshot = GetSnapshot();
            if (snapshot.EnabledAccounts == 0)
            {
                ShowBalloon("NomadInbox accounts", "Ask your agent if you want to connect new accounts. The tray will not discover credentials or mailbox data.");
                return;
            }

            ShowBalloon("NomadInbox sync", "Manual sync started.");
            Task.Run(async () =>
            {
                try
                {
                    await EnsureHttpServiceAsync();
                    var result = await RequestJsonAsync("POST", "/sync/once", "{}", 600000);
                    ShowBalloon("NomadInbox sync", SyncResultText(result));
                }
                catch (Exception ex)
                {
                    ShowBalloon("NomadInbox sync", "Manual sync failed: " + ex.Message);
                }
                finally
                {
                    BeginRefresh("sync");
                }
            });
        }

        private void BeginToggleAutoSync()
        {
            var snapshot = GetSnapshot();
            var shouldStop = snapshot.Worker == "running";
            if (!shouldStop && snapshot.EnabledAccounts == 0)
            {
                ShowBalloon("NomadInbox accounts", "Ask your agent if you want to connect new accounts. Auto sync stays off until accounts are enabled.");
                return;
            }

            Task.Run(async () =>
            {
                try
                {
                    await EnsureHttpServiceAsync();
                    await RequestJsonAsync("POST", shouldStop ? "/service/stop" : "/service/start", "{}", 30000);
                    ShowBalloon("NomadInbox auto sync", shouldStop ? "Auto sync is off." : "Auto sync is on for enabled accounts.");
                }
                catch (Exception ex)
                {
                    ShowBalloon("NomadInbox auto sync", "Auto sync request failed: " + ex.Message);
                }
                finally
                {
                    BeginRefresh("auto-sync");
                }
            });
        }

        private async Task EnsureHttpServiceAsync()
        {
            if (await IsHttpRunningAsync()) return;

            lock (this)
            {
                if (httpProcess != null && !httpProcess.HasExited) return;
                Directory.CreateDirectory(options.DataDir);
                var servicePath = Path.Combine(options.RepoRoot, "service", "nomadmail-service.mjs");
                var psi = new ProcessStartInfo
                {
                    FileName = "node",
                    Arguments = Quote(servicePath) + " http --port " + options.Port.ToString(CultureInfo.InvariantCulture) + " --host " + options.Host,
                    WorkingDirectory = options.RepoRoot,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                psi.EnvironmentVariables["NOMADINBOX_DATA_DIR"] = options.DataDir;
                httpProcess = Process.Start(psi);
                httpStartedByTray = true;
                if (httpProcess != null)
                {
                    File.WriteAllText(Path.Combine(options.DataDir, "nomadmail-http.pid"), httpProcess.Id.ToString(CultureInfo.InvariantCulture), Encoding.ASCII);
                }
            }

            for (var i = 0; i < 12; i++)
            {
                await Task.Delay(250);
                if (await IsHttpRunningAsync()) return;
            }
        }

        private async Task<bool> IsHttpRunningAsync()
        {
            try
            {
                var result = await RequestJsonAsync("GET", "/workspace-state", null, 1200);
                return GetString(result, "service", "") == "NomadMail";
            }
            catch
            {
                return false;
            }
        }

        private async Task<Dictionary<string, object>> RequestJsonAsync(string method, string path, string body, int timeoutMs)
        {
            return await Task.Run(() =>
            {
                var request = (HttpWebRequest)WebRequest.Create(options.BaseUrl + path);
                request.Method = method;
                request.Timeout = timeoutMs;
                request.ReadWriteTimeout = timeoutMs;
                request.Accept = "application/json";
                if (method == "POST")
                {
                    var bytes = Encoding.UTF8.GetBytes(body ?? "{}");
                    request.ContentType = "application/json; charset=utf-8";
                    request.ContentLength = bytes.Length;
                    using (var stream = request.GetRequestStream())
                    {
                        stream.Write(bytes, 0, bytes.Length);
                    }
                }

                using (var response = (HttpWebResponse)request.GetResponse())
                using (var stream = response.GetResponseStream())
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    return ParseJson(reader.ReadToEnd());
                }
            });
        }

        private Dictionary<string, object> ParseJson(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return new Dictionary<string, object>();
            return serializer.Deserialize<Dictionary<string, object>>(text) ?? new Dictionary<string, object>();
        }

        private void ShowSettings()
        {
            var snapshot = GetSnapshot();
            if (settingsForm == null || settingsForm.IsDisposed)
            {
                settingsForm = new SettingsForm(appIcon, BeginRefresh, BeginManualSync, BeginToggleAutoSync, OpenRuntimeFolder);
            }
            settingsForm.Render(snapshot, refreshInFlight);
            settingsForm.Show();
            settingsForm.Activate();
        }

        private void OpenRuntimeFolder()
        {
            Directory.CreateDirectory(options.DataDir);
            Process.Start("explorer.exe", Quote(options.DataDir));
        }

        private static Icon LoadAppIcon(string path, out bool ownsIcon)
        {
            if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
            {
                ownsIcon = true;
                return new Icon(path);
            }

            ownsIcon = false;
            return SystemIcons.Application;
        }

        private void ExitTray()
        {
            Dispose();
            Application.Exit();
        }

        private void StopHttpServiceIfOwned()
        {
            if (!httpStartedByTray || httpProcess == null) return;
            try
            {
                if (!httpProcess.HasExited) httpProcess.Kill();
            }
            catch
            {
            }
            try
            {
                File.Delete(Path.Combine(options.DataDir, "nomadmail-http.pid"));
            }
            catch
            {
            }
        }

        private TrayState GetSnapshot()
        {
            lock (stateLock)
            {
                return state.Clone();
            }
        }

        private void BeginUi(Action action)
        {
            if (notify == null || disposed) return;
            try
            {
                if (invoker != null && invoker.IsHandleCreated)
                {
                    invoker.BeginInvoke(action);
                }
                else
                {
                    action();
                }
            }
            catch
            {
                try { action(); } catch { }
            }
        }

        private void ShowBalloon(string title, string text)
        {
            BeginUi(() => notify.ShowBalloonTip(3000, title, Clamp(text, 240), ToolTipIcon.Info));
        }

        private static string SyncResultText(Dictionary<string, object> result)
        {
            if (GetString(result, "status", "") != "ok")
            {
                return "Sync did not complete. Open Settings for details or ask your agent to inspect NomadMail status.";
            }
            var synced = 0;
            foreach (var item in GetList(result, "results"))
            {
                synced += GetInt(item as Dictionary<string, object>, "synced", 0);
            }
            return "Manual sync finished for " + GetInt(result, "accountCount", 0) + " account(s). " + synced + " message(s) synced.";
        }

        private static List<AccountRow> AccountRowsFromAccounts(IList accounts, IList syncAccounts)
        {
            var syncById = new Dictionary<string, Dictionary<string, object>>(StringComparer.OrdinalIgnoreCase);
            foreach (var item in syncAccounts)
            {
                var row = item as Dictionary<string, object>;
                var id = GetString(row, "accountId", "");
                if (!string.IsNullOrWhiteSpace(id)) syncById[id] = row;
            }

            var rows = new List<AccountRow>();
            foreach (var item in accounts)
            {
                var account = item as Dictionary<string, object>;
                if (account == null) continue;
                var id = GetString(account, "id", "");
                Dictionary<string, object> sync;
                syncById.TryGetValue(id, out sync);
                rows.Add(new AccountRow
                {
                    Id = id,
                    Label = AccountLabel(account),
                    Provider = GetString(account, "provider", "account"),
                    Enabled = GetBool(account, "enabled", false),
                    StatusText = AccountSyncText(account, sync)
                });
            }
            return rows;
        }

        private static List<AccountRow> AccountRowsFromSyncStatus(IList syncAccounts)
        {
            var rows = new List<AccountRow>();
            foreach (var item in syncAccounts)
            {
                var sync = item as Dictionary<string, object>;
                if (sync == null) continue;
                rows.Add(new AccountRow
                {
                    Id = GetString(sync, "accountId", ""),
                    Label = EmptyAs(GetString(sync, "displayName", ""), GetString(sync, "accountId", "Account")),
                    Provider = GetString(sync, "provider", ""),
                    Enabled = true,
                    StatusText = GetString(sync, "status", "unknown") + ", " + GetString(sync, "synced", "0") + " synced"
                });
            }
            return rows;
        }

        private static string AccountLabel(Dictionary<string, object> account)
        {
            var provider = ProviderLabel(GetString(account, "provider", "Account"));
            foreach (var property in new[] { "email", "mailbox", "upn", "userPrincipalName", "username", "address", "profileEmail" })
            {
                var value = GetString(account, property, "");
                if (!string.IsNullOrWhiteSpace(value)) return provider + " (" + value + ")";
            }
            return EmptyAs(GetString(account, "displayName", ""), provider);
        }

        private static string AccountSyncText(Dictionary<string, object> account, Dictionary<string, object> sync)
        {
            if (!GetBool(account, "enabled", false)) return "disabled";
            if (sync == null) return "enabled, no recent sync";
            var reason = GetString(sync, "reason", "");
            var text = GetString(sync, "status", "unknown") + ", " + GetString(sync, "synced", "0") + " synced";
            return string.IsNullOrWhiteSpace(reason) ? text : text + ", " + reason;
        }

        private static string ProviderLabel(string provider)
        {
            if (provider == "outlook-desktop") return "Outlook Desktop";
            if (provider == "outlook-graph") return "Outlook Graph";
            if (provider == "gmail-api") return "Gmail";
            return string.IsNullOrWhiteSpace(provider) ? "Account" : provider;
        }

        private static Dictionary<string, object> GetDictionary(Dictionary<string, object> parent, string key)
        {
            if (parent == null || !parent.ContainsKey(key)) return new Dictionary<string, object>();
            return parent[key] as Dictionary<string, object> ?? new Dictionary<string, object>();
        }

        private static IList GetList(Dictionary<string, object> parent, string key)
        {
            if (parent == null || !parent.ContainsKey(key)) return new ArrayList();
            return parent[key] as IList ?? new ArrayList();
        }

        private static string GetString(Dictionary<string, object> parent, string key, string fallback)
        {
            if (parent == null || !parent.ContainsKey(key) || parent[key] == null) return fallback;
            var text = Convert.ToString(parent[key], CultureInfo.InvariantCulture);
            return string.IsNullOrWhiteSpace(text) ? fallback : text;
        }

        private static int GetInt(Dictionary<string, object> parent, string key, int fallback)
        {
            int value;
            return int.TryParse(GetString(parent, key, ""), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) ? value : fallback;
        }

        private static bool GetBool(Dictionary<string, object> parent, string key, bool fallback)
        {
            if (parent == null || !parent.ContainsKey(key) || parent[key] == null) return fallback;
            if (parent[key] is bool) return (bool)parent[key];
            bool value;
            return bool.TryParse(Convert.ToString(parent[key], CultureInfo.InvariantCulture), out value) ? value : fallback;
        }

        private static int CountLines(string path)
        {
            try
            {
                if (!File.Exists(path)) return 0;
                var count = 0;
                using (var reader = new StreamReader(path, Encoding.UTF8))
                {
                    while (reader.ReadLine() != null) count++;
                }
                return count;
            }
            catch
            {
                return 0;
            }
        }

        private static string FormatLocalTime(string value)
        {
            DateTimeOffset parsed;
            if (string.IsNullOrWhiteSpace(value) || !DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out parsed))
            {
                return "";
            }
            return parsed.ToLocalTime().ToString("g", CultureInfo.CurrentCulture);
        }

        private static string Quote(string value)
        {
            return "\"" + (value ?? "").Replace("\"", "\\\"") + "\"";
        }

        private static string EmptyAs(string value, string fallback)
        {
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }

        private static string ClampNotifyText(string value)
        {
            return Clamp(value, 63);
        }

        private static string Clamp(string value, int maxLength)
        {
            if (string.IsNullOrEmpty(value) || value.Length <= maxLength) return value ?? "";
            return value.Substring(0, maxLength - 3) + "...";
        }
    }

    internal sealed class TrayState
    {
        public string DataDir = "";
        public string HttpUrl = "";
        public string HttpStatus = "unknown";
        public string Worker = "unknown";
        public string LastRunAt = "";
        public string NextRunAt = "";
        public int LiveMessages;
        public int ArchiveMessages;
        public int TotalAccounts;
        public int EnabledAccounts;
        public string StatusPath = "";
        public string LastMessage = "";
        public DateTime LastUpdatedAt = DateTime.MinValue;
        public List<AccountRow> AccountRows = new List<AccountRow>();

        public static TrayState Initial()
        {
            return new TrayState
            {
                HttpStatus = "checking",
                Worker = "unknown",
                LastMessage = "Loading cached status."
            };
        }

        public TrayState Clone()
        {
            return new TrayState
            {
                DataDir = DataDir,
                HttpUrl = HttpUrl,
                HttpStatus = HttpStatus,
                Worker = Worker,
                LastRunAt = LastRunAt,
                NextRunAt = NextRunAt,
                LiveMessages = LiveMessages,
                ArchiveMessages = ArchiveMessages,
                TotalAccounts = TotalAccounts,
                EnabledAccounts = EnabledAccounts,
                StatusPath = StatusPath,
                LastMessage = LastMessage,
                LastUpdatedAt = LastUpdatedAt,
                AccountRows = AccountRows.Select(row => row.Clone()).ToList()
            };
        }
    }

    internal sealed class AccountRow
    {
        public string Id = "";
        public string Label = "";
        public string Provider = "";
        public bool Enabled;
        public string StatusText = "";

        public AccountRow Clone()
        {
            return new AccountRow
            {
                Id = Id,
                Label = Label,
                Provider = Provider,
                Enabled = Enabled,
                StatusText = StatusText
            };
        }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly Action<string> refresh;
        private readonly Action syncNow;
        private readonly Action toggleAutoSync;
        private readonly Action openRuntime;
        private readonly Label subtitle;
        private readonly Label httpPill;
        private readonly Label syncPill;
        private readonly ListView statusList;
        private readonly ListView accountList;
        private readonly TextBox storageText;
        private readonly Button toggleButton;

        public SettingsForm(Icon icon, Action<string> refresh, Action syncNow, Action toggleAutoSync, Action openRuntime)
        {
            this.refresh = refresh;
            this.syncNow = syncNow;
            this.toggleAutoSync = toggleAutoSync;
            this.openRuntime = openRuntime;

            Text = "NomadInbox Settings";
            Icon = icon;
            ClientSize = new Size(760, 560);
            MinimumSize = new Size(760, 560);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9F);
            BackColor = Color.FromArgb(248, 250, 252);

            var title = new Label { Text = "NomadInbox Settings", Left = 20, Top = 14, Width = 300, Height = 28, Font = new Font("Segoe UI", 16F, FontStyle.Bold), ForeColor = Color.FromArgb(30, 41, 59) };
            subtitle = new Label { Text = "Loading cached status.", Left = 20, Top = 46, Width = 520, Height = 22, ForeColor = Color.FromArgb(71, 85, 105) };
            httpPill = NewPill("HTTP");
            httpPill.Left = 520;
            httpPill.Top = 18;
            syncPill = NewPill("Auto sync");
            syncPill.Left = 626;
            syncPill.Top = 18;

            statusList = NewListView(20, 84, 720, 172, new[] { Tuple.Create("Status", 220), Tuple.Create("Value", 470) });
            accountList = NewListView(20, 270, 720, 124, new[] { Tuple.Create("Account", 260), Tuple.Create("Provider", 130), Tuple.Create("State", 100), Tuple.Create("Sync", 210) });
            storageText = new TextBox { Left = 20, Top = 408, Width = 720, Height = 86, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BackColor = Color.White };
            var syncButton = new Button { Text = "Sync now", Left = 20, Top = 510, Width = 100, Height = 30 };
            var refreshButton = new Button { Text = "Refresh", Left = 128, Top = 510, Width = 90, Height = 30 };
            toggleButton = new Button { Text = "Toggle auto sync", Left = 226, Top = 510, Width = 140, Height = 30 };
            var folderButton = new Button { Text = "Runtime folder", Left = 374, Top = 510, Width = 120, Height = 30 };
            var closeButton = new Button { Text = "Close", Left = 642, Top = 510, Width = 98, Height = 30 };

            syncButton.Click += (sender, args) => syncNow();
            refreshButton.Click += (sender, args) => refresh("settings");
            toggleButton.Click += (sender, args) => toggleAutoSync();
            folderButton.Click += (sender, args) => openRuntime();
            closeButton.Click += (sender, args) => Hide();

            Controls.Add(title);
            Controls.Add(subtitle);
            Controls.Add(httpPill);
            Controls.Add(syncPill);
            Controls.Add(statusList);
            Controls.Add(accountList);
            Controls.Add(storageText);
            Controls.Add(syncButton);
            Controls.Add(refreshButton);
            Controls.Add(toggleButton);
            Controls.Add(folderButton);
            Controls.Add(closeButton);
        }

        public void Render(TrayState state, bool refreshInFlight)
        {
            subtitle.Text = refreshInFlight ? "Refreshing in background. Menu actions remain available." : state.LastMessage;
            SetPill(httpPill, state.HttpStatus == "running" ? "HTTP on" : "HTTP off", state.HttpStatus == "running");
            SetPill(syncPill, state.Worker == "running" ? "Auto sync on" : "Auto sync off", state.Worker == "running");
            toggleButton.Text = state.Worker == "running" ? "Turn off auto sync" : "Turn on auto sync";

            statusList.Items.Clear();
            AddRow(statusList, "Local HTTP service", state.HttpStatus + " at " + state.HttpUrl);
            AddRow(statusList, "MCP stdio", "Launched by each calling agent");
            AddRow(statusList, "Auto sync worker", state.Worker);
            AddRow(statusList, "Live messages", state.LiveMessages.ToString(CultureInfo.InvariantCulture));
            AddRow(statusList, "Archive messages", state.ArchiveMessages.ToString(CultureInfo.InvariantCulture));
            AddRow(statusList, "Enabled accounts", state.EnabledAccounts + "/" + state.TotalAccounts);
            AddRow(statusList, "Last sync", string.IsNullOrWhiteSpace(state.LastRunAt) ? "Not recorded" : state.LastRunAt);
            AddRow(statusList, "Next sync", string.IsNullOrWhiteSpace(state.NextRunAt) ? "Not scheduled" : state.NextRunAt);
            AddRow(statusList, "Sync status file", state.StatusPath);

            accountList.Items.Clear();
            foreach (var account in state.AccountRows)
            {
                var item = new ListViewItem(account.Label);
                item.SubItems.Add(account.Provider);
                item.SubItems.Add(account.Enabled ? "Enabled" : "Disabled");
                item.SubItems.Add(account.StatusText);
                accountList.Items.Add(item);
            }

            storageText.Text = "Runtime data: " + state.DataDir + Environment.NewLine
                + "Ask your agent if you want to connect new accounts." + Environment.NewLine
                + "No send, mailbox mutation, account discovery, token discovery, or auto sync enablement happens without explicit approval.";
        }

        private static Label NewPill(string text)
        {
            return new Label { Text = text, Width = 100, Height = 26, TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI", 8.5F, FontStyle.Bold) };
        }

        private static ListView NewListView(int left, int top, int width, int height, Tuple<string, int>[] columns)
        {
            var list = new ListView { Left = left, Top = top, Width = width, Height = height, View = View.Details, FullRowSelect = true, HideSelection = false, BackColor = Color.White };
            foreach (var column in columns)
            {
                list.Columns.Add(column.Item1, column.Item2);
            }
            return list;
        }

        private static void SetPill(Label label, string text, bool ok)
        {
            label.Text = text;
            label.BackColor = ok ? Color.FromArgb(220, 252, 231) : Color.FromArgb(254, 243, 199);
            label.ForeColor = ok ? Color.FromArgb(22, 101, 52) : Color.FromArgb(146, 64, 14);
        }

        private static void AddRow(ListView list, string name, string value)
        {
            var item = new ListViewItem(name);
            item.SubItems.Add(value ?? "");
            list.Items.Add(item);
        }
    }
}
