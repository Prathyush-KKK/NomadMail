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
        public bool ShowOnStartup { get; private set; }

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
            var showOnStartup = false;

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
                else if (key == "--show-on-startup")
                {
                    showOnStartup = true;
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
                IconPath = Path.Combine(repoRoot, "assets", "nomadinbox-tray.ico"),
                ShowOnStartup = showOnStartup
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
        private System.Windows.Forms.Timer startupPopupTimer;
        private readonly JavaScriptSerializer serializer;
        private readonly object stateLock = new object();
        private readonly Icon appIcon;
        private readonly bool ownsAppIcon;
        private TrayState state = TrayState.Initial();
        private Process httpProcess;
        private bool httpStartedByTray;
        private bool refreshInFlight;
        private bool disposed;
        private StatusPopupForm statusPopup;
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
                if (args.Button == MouseButtons.Left)
                {
                    ShowStatusPopup();
                }
                else if (args.Button == MouseButtons.Right)
                {
                    BuildMenuFromCache();
                    menu.Show(Cursor.Position);
                }
            };
            notify.DoubleClick += (sender, args) =>
            {
                ShowStatusPopup();
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
            if (options.ShowOnStartup)
            {
                ScheduleStartupPopup();
            }
            notify.ShowBalloonTip(2500, "NomadInbox", "NomadInbox is running. Click the tray icon for Refresh, Sync now, auto sync, and status.", ToolTipIcon.Info);
            Application.Run(new ApplicationContext());
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            refreshTimer.Stop();
            refreshTimer.Dispose();
            if (startupPopupTimer != null)
            {
                startupPopupTimer.Stop();
                startupPopupTimer.Dispose();
                startupPopupTimer = null;
            }
            if (statusPopup != null && !statusPopup.IsDisposed) statusPopup.Close();
            if (settingsForm != null && !settingsForm.IsDisposed) settingsForm.Close();
            StopHttpServiceIfOwned();
            notify.Visible = false;
            notify.Dispose();
            if (ownsAppIcon) appIcon.Dispose();
            menu.Dispose();
            invoker.Dispose();
        }

        private void ScheduleStartupPopup()
        {
            startupPopupTimer = new System.Windows.Forms.Timer { Interval = 900 };
            startupPopupTimer.Tick += (sender, args) =>
            {
                startupPopupTimer.Stop();
                startupPopupTimer.Dispose();
                startupPopupTimer = null;
                ShowStatusPopup();
            };
            startupPopupTimer.Start();
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
            if (refreshInFlight)
            {
                UpdateTransientMessage("Status refresh is already running.");
                return;
            }
            refreshInFlight = true;
            UpdateTransientMessage("Refreshing status...");
            Task.Run(async () =>
            {
                TrayState next = null;
                try
                {
                    await EnsureHttpServiceAsync();
                    var serviceTask = RequestJsonAsync("GET", "/service/status", null, 15000);
                    var accountsTask = RequestJsonAsync("GET", "/accounts", null, 15000);
                    var backupTask = RequestJsonAsync("GET", "/backup/status", null, 15000);
                    await Task.WhenAll(serviceTask, accountsTask, backupTask);
                    next = BuildState(serviceTask.Result, accountsTask.Result, backupTask.Result, true, reason);
                }
                catch (Exception ex)
                {
                    next = ReadCachedState();
                    next.HttpStatus = "unavailable";
                    next.LastMessage = "Status refresh failed: " + ex.Message;
                }
                finally
                {
                    refreshInFlight = false;
                    if (next != null)
                    {
                        UpdateState(next);
                    }
                }
            });
        }

        private void UpdateTransientMessage(string message)
        {
            if (disposed) return;
            TrayState next;
            lock (stateLock)
            {
                next = state.Clone();
                next.LastMessage = message;
                next.LastUpdatedAt = DateTime.Now;
                state = next;
            }

            BeginUi(() =>
            {
                if (statusPopup != null && !statusPopup.IsDisposed)
                {
                    statusPopup.Render(next, refreshInFlight);
                }
                if (settingsForm != null && !settingsForm.IsDisposed)
                {
                    settingsForm.Render(next, refreshInFlight);
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
                if (statusPopup != null && !statusPopup.IsDisposed)
                {
                    statusPopup.Render(next, refreshInFlight);
                }
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
            AddMenuItem("Open status popup", true, (sender, args) => ShowStatusPopup());
            AddMenuItem("Refresh status", true, (sender, args) =>
            {
                ShowStatusPopup();
                BeginRefresh("manual");
            });
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
                UpdateTransientMessage("No enabled accounts. Ask your agent to connect one.");
                return;
            }

            UpdateTransientMessage("Manual sync started...");
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
                UpdateTransientMessage("Auto sync stays off until an account is enabled.");
                return;
            }

            UpdateTransientMessage(shouldStop ? "Turning off auto sync..." : "Turning on auto sync...");
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

            for (var i = 0; i < 30; i++)
            {
                await Task.Delay(500);
                if (await IsHttpRunningAsync()) return;
            }
        }

        private async Task<bool> IsHttpRunningAsync()
        {
            try
            {
                var result = await RequestJsonAsync("GET", "/workspace-state", null, 5000);
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

        private void ShowStatusPopup()
        {
            var snapshot = GetSnapshot();
            if (statusPopup == null || statusPopup.IsDisposed)
            {
                statusPopup = new StatusPopupForm(appIcon, BeginRefresh, BeginManualSync, BeginToggleAutoSync, ShowSettings, OpenRuntimeFolder);
            }
            statusPopup.Render(snapshot, refreshInFlight);
            PositionNearCursor(statusPopup);
            statusPopup.Show();
            statusPopup.Activate();
        }

        private static void PositionNearCursor(Form form)
        {
            var area = Screen.FromPoint(Cursor.Position).WorkingArea;
            var x = Cursor.Position.X - form.Width + 24;
            var y = Cursor.Position.Y - form.Height - 12;
            if (x < area.Left + 8) x = area.Left + 8;
            if (y < area.Top + 8) y = Cursor.Position.Y + 12;
            if (x + form.Width > area.Right - 8) x = area.Right - form.Width - 8;
            if (y + form.Height > area.Bottom - 8) y = area.Bottom - form.Height - 8;
            form.StartPosition = FormStartPosition.Manual;
            form.Location = new Point(x, y);
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
                    StatusText = SyncStatusText(sync)
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
            if (!GetBool(account, "enabled", false)) return "Disabled";
            if (sync == null) return "Enabled - no recent sync";
            return SyncStatusText(sync);
        }

        private static string SyncStatusText(Dictionary<string, object> sync)
        {
            var status = FriendlyStatus(GetString(sync, "status", "unknown"));
            var synced = GetString(sync, "synced", "0");
            var reason = FriendlyReason(GetString(sync, "reason", ""));
            var text = status + " - " + synced + " synced";
            return string.IsNullOrWhiteSpace(reason) ? text : text + " - " + reason;
        }

        private static string FriendlyStatus(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return "Unknown";
            return CultureInfo.CurrentCulture.TextInfo.ToTitleCase(value.Replace("-", " ").Replace("_", " ").ToLowerInvariant());
        }

        private static string FriendlyReason(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return "";
            return value.Replace("-", " ").Replace("_", " ");
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
            var local = parsed.ToLocalTime();
            var format = local.Date == DateTimeOffset.Now.Date ? "t" : "g";
            return local.ToString(format, CultureInfo.CurrentCulture);
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

    internal sealed class StatusPopupForm : Form
    {
        private readonly Action<string> refresh;
        private readonly Action syncNow;
        private readonly Action toggleAutoSync;
        private readonly Action openSettings;
        private readonly Action openRuntime;
        private readonly Label subtitle;
        private readonly Label updatedLabel;
        private readonly Label syncPill;
        private readonly Label liveCountLabel;
        private readonly Label archiveCountLabel;
        private readonly Label lastSyncLabel;
        private readonly Label nextSyncLabel;
        private readonly FlowLayoutPanel accountsPanel;
        private readonly Button refreshButton;
        private readonly Button syncButton;
        private readonly Button autoButton;
        private readonly ToolTip tips;

        public StatusPopupForm(Icon icon, Action<string> refresh, Action syncNow, Action toggleAutoSync, Action openSettings, Action openRuntime)
        {
            this.refresh = refresh;
            this.syncNow = syncNow;
            this.toggleAutoSync = toggleAutoSync;
            this.openSettings = openSettings;
            this.openRuntime = openRuntime;

            Text = "NomadInbox";
            Icon = icon;
            ClientSize = new Size(432, 492);
            MinimumSize = new Size(432, 492);
            MaximumSize = new Size(432, 492);
            ShowInTaskbar = false;
            TopMost = true;
            FormBorderStyle = FormBorderStyle.None;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Segoe UI", 9F);
            BackColor = Palette.Surface;
            Deactivate += (sender, args) => Hide();
            tips = new ToolTip { AutomaticDelay = 350, ReshowDelay = 100, ShowAlways = true };

            var headerIcon = new PictureBox { Left = 18, Top = 16, Width = 30, Height = 30, SizeMode = PictureBoxSizeMode.StretchImage, Image = icon.ToBitmap() };
            var title = new Label { Text = "NomadInbox", Left = 58, Top = 12, Width = 190, Height = 24, Font = new Font("Segoe UI", 13F, FontStyle.Bold), ForeColor = Palette.Text };
            subtitle = new Label { Text = "Loading status.", Left = 58, Top = 37, Width = 258, Height = 20, ForeColor = Palette.Muted };
            updatedLabel = new Label { Text = "", Left = 300, Top = 14, Width = 112, Height = 18, TextAlign = ContentAlignment.TopRight, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8F) };
            var closeButton = NewIconButton("", IconFactory.Close(Palette.Muted), 388, 36);
            closeButton.Size = new Size(28, 28);
            closeButton.Click += (sender, args) => Hide();

            syncPill = NewPill("Auto sync");
            syncPill.Left = 18;
            syncPill.Top = 72;
            syncPill.Width = 130;

            syncButton = NewIconButton("Sync now", IconFactory.Sync(Color.White), 18, 108);
            syncButton.Width = 96;
            syncButton.BackColor = Palette.Accent;
            syncButton.ForeColor = Color.White;
            syncButton.FlatAppearance.BorderColor = Palette.Accent;
            syncButton.Click += (sender, args) => syncNow();
            tips.SetToolTip(syncButton, "Run one sync cycle for enabled accounts.");
            refreshButton = NewIconButton("Refresh", IconFactory.Refresh(Palette.Accent), 118, 108);
            refreshButton.Width = 96;
            refreshButton.Click += (sender, args) => refresh("popup");
            tips.SetToolTip(refreshButton, "Refresh status from the local NomadMail service.");
            autoButton = NewIconButton("Auto", IconFactory.Power(Palette.Accent), 218, 108);
            autoButton.Width = 96;
            autoButton.Click += (sender, args) => toggleAutoSync();
            tips.SetToolTip(autoButton, "Turn background sync on or off.");
            var settingsButton = NewIconButton("Settings", IconFactory.Settings(Palette.Accent), 318, 108);
            settingsButton.Width = 96;
            settingsButton.Click += (sender, args) => openSettings();
            tips.SetToolTip(settingsButton, "Open diagnostics and runtime details.");

            var liveCard = NewMetricCard(18, 158, "Live messages");
            liveCountLabel = (Label)liveCard.Controls["value"];
            var archiveCard = NewMetricCard(154, 158, "Archive");
            archiveCountLabel = (Label)archiveCard.Controls["value"];
            var syncCard = NewMetricCard(290, 158, "Last sync");
            lastSyncLabel = (Label)syncCard.Controls["value"];

            var accountTitle = new Label { Text = "Accounts", Left = 18, Top = 244, Width = 170, Height = 22, Font = new Font("Segoe UI", 10F, FontStyle.Bold), ForeColor = Palette.Text };
            nextSyncLabel = new Label { Text = "", Left = 188, Top = 246, Width = 226, Height = 20, TextAlign = ContentAlignment.TopRight, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8.5F) };
            accountsPanel = new FlowLayoutPanel { Left = 18, Top = 272, Width = 396, Height = 146, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, BackColor = Palette.Surface };

            var note = new Label
            {
                Left = 18,
                Top = 426,
                Width = 396,
                Height = 44,
                ForeColor = Palette.Muted,
                Text = "Ask your agent to connect new accounts. The tray will not discover credentials or mailbox data."
            };

            Controls.Add(headerIcon);
            Controls.Add(title);
            Controls.Add(subtitle);
            Controls.Add(updatedLabel);
            Controls.Add(closeButton);
            Controls.Add(syncPill);
            Controls.Add(refreshButton);
            Controls.Add(syncButton);
            Controls.Add(autoButton);
            Controls.Add(settingsButton);
            Controls.Add(liveCard);
            Controls.Add(archiveCard);
            Controls.Add(syncCard);
            Controls.Add(accountTitle);
            Controls.Add(nextSyncLabel);
            Controls.Add(accountsPanel);
            Controls.Add(note);
        }

        public void Render(TrayState state, bool refreshInFlight)
        {
            subtitle.Text = refreshInFlight ? "Refreshing status..." : EmptyAs(state.LastMessage, "Status ready.");
            updatedLabel.Text = state.LastUpdatedAt == DateTime.MinValue ? "" : "Updated " + state.LastUpdatedAt.ToString("t", CultureInfo.CurrentCulture);
            SetPill(syncPill, state.Worker == "running" ? "Auto sync on" : "Auto sync off", state.Worker == "running");

            refreshButton.Enabled = !refreshInFlight;
            refreshButton.Text = refreshInFlight ? "Refreshing" : "Refresh";
            autoButton.Text = state.Worker == "running" ? "Auto on" : "Auto off";

            liveCountLabel.Text = state.LiveMessages.ToString(CultureInfo.InvariantCulture);
            archiveCountLabel.Text = state.ArchiveMessages.ToString(CultureInfo.InvariantCulture);
            lastSyncLabel.Text = EmptyAs(state.LastRunAt, "Never");
            nextSyncLabel.Text = "Next sync: " + EmptyAs(state.NextRunAt, "not scheduled");

            accountsPanel.SuspendLayout();
            accountsPanel.Controls.Clear();
            if (state.AccountRows.Count == 0)
            {
                accountsPanel.Controls.Add(NewEmptyAccountRow());
            }
            else
            {
                foreach (var account in state.AccountRows)
                {
                    accountsPanel.Controls.Add(NewAccountRow(account));
                }
            }
            accountsPanel.ResumeLayout();
        }

        private static Button NewIconButton(string text, Image image, int left, int top)
        {
            var button = new Button
            {
                Text = text,
                Image = image,
                ImageAlign = string.IsNullOrWhiteSpace(text) ? ContentAlignment.MiddleCenter : ContentAlignment.MiddleLeft,
                TextAlign = ContentAlignment.MiddleCenter,
                TextImageRelation = TextImageRelation.ImageBeforeText,
                Left = left,
                Top = top,
                Width = 128,
                Height = 34,
                FlatStyle = FlatStyle.Flat,
                BackColor = Palette.Card,
                ForeColor = Palette.Text,
                Font = new Font("Segoe UI", 9F, FontStyle.Bold),
                Padding = string.IsNullOrWhiteSpace(text) ? Padding.Empty : new Padding(8, 0, 8, 0),
                UseVisualStyleBackColor = false
            };
            button.FlatAppearance.BorderColor = Palette.Border;
            button.FlatAppearance.MouseOverBackColor = Palette.CardHover;
            button.FlatAppearance.MouseDownBackColor = Palette.CardPressed;
            return button;
        }

        private static Label NewPill(string text)
        {
            return new Label
            {
                Text = text,
                Width = 100,
                Height = 28,
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Segoe UI", 8.5F, FontStyle.Bold)
            };
        }

        private static Panel NewMetricCard(int left, int top, string labelText)
        {
            var panel = new Panel { Left = left, Top = top, Width = 124, Height = 72, BackColor = Palette.Card, BorderStyle = BorderStyle.FixedSingle };
            var label = new Label { Text = labelText, Left = 10, Top = 8, Width = 100, Height = 18, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8.5F) };
            var value = new Label { Name = "value", Text = "-", Left = 10, Top = 30, Width = 104, Height = 28, ForeColor = Palette.Text, Font = new Font("Segoe UI", 14F, FontStyle.Bold) };
            panel.Controls.Add(label);
            panel.Controls.Add(value);
            return panel;
        }

        private static Control NewEmptyAccountRow()
        {
            var row = new Panel { Width = 372, Height = 58, BackColor = Palette.Card, BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 0, 0, 8) };
            row.Controls.Add(new Label { Text = "No accounts connected", Left = 12, Top = 8, Width = 250, Height = 20, ForeColor = Palette.Text, Font = new Font("Segoe UI", 9F, FontStyle.Bold) });
            row.Controls.Add(new Label { Text = "Ask your agent to connect Outlook Desktop, Gmail, or Graph.", Left = 12, Top = 30, Width = 342, Height = 18, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8.5F) });
            return row;
        }

        private static Control NewAccountRow(AccountRow account)
        {
            var row = new Panel { Width = 372, Height = 64, BackColor = Palette.Card, BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 0, 0, 8) };
            var statusColor = StatusColor(account);
            var dot = new Label { Left = 12, Top = 18, Width = 12, Height = 12, BackColor = statusColor };
            var name = new Label { Text = Clamp(account.Label, 42), Left = 32, Top = 8, Width = 242, Height = 20, ForeColor = Palette.Text, Font = new Font("Segoe UI", 9F, FontStyle.Bold) };
            var provider = new Label { Text = ProviderLabel(account.Provider), Left = 32, Top = 30, Width = 130, Height = 18, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8.5F) };
            var status = new Label { Text = Clamp(account.StatusText, 34), Left = 166, Top = 30, Width = 190, Height = 18, ForeColor = Palette.Muted, Font = new Font("Segoe UI", 8.5F), TextAlign = ContentAlignment.MiddleRight };
            row.Controls.Add(dot);
            row.Controls.Add(name);
            row.Controls.Add(provider);
            row.Controls.Add(status);
            return row;
        }

        private static Color StatusColor(AccountRow account)
        {
            if (!account.Enabled) return Palette.Warning;
            var text = account.StatusText ?? "";
            if (text.IndexOf("fail", StringComparison.OrdinalIgnoreCase) >= 0 || text.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return Palette.Error;
            }
            if (text.IndexOf("running", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return Palette.Accent;
            }
            return Palette.Success;
        }

        private static void SetPill(Label label, string text, bool ok)
        {
            label.Text = text;
            label.BackColor = ok ? Color.FromArgb(20, 83, 45) : Color.FromArgb(120, 53, 15);
            label.ForeColor = ok ? Color.FromArgb(187, 247, 208) : Color.FromArgb(254, 215, 170);
        }

        private static string ProviderLabel(string provider)
        {
            if (provider == "outlook-desktop") return "Outlook Desktop";
            if (provider == "outlook-graph") return "Outlook Graph";
            if (provider == "gmail-api") return "Gmail";
            return string.IsNullOrWhiteSpace(provider) ? "Account" : provider;
        }

        private static string EmptyAs(string value, string fallback)
        {
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }

        private static string Clamp(string value, int maxLength)
        {
            if (string.IsNullOrEmpty(value) || value.Length <= maxLength) return value ?? "";
            return value.Substring(0, maxLength - 3) + "...";
        }
    }

    internal static class Palette
    {
        public static readonly Color Surface = Color.FromArgb(15, 23, 42);
        public static readonly Color Card = Color.FromArgb(30, 41, 59);
        public static readonly Color CardHover = Color.FromArgb(51, 65, 85);
        public static readonly Color CardPressed = Color.FromArgb(71, 85, 105);
        public static readonly Color Text = Color.FromArgb(241, 245, 249);
        public static readonly Color Muted = Color.FromArgb(148, 163, 184);
        public static readonly Color Border = Color.FromArgb(51, 65, 85);
        public static readonly Color Accent = Color.FromArgb(56, 189, 248);
        public static readonly Color Success = Color.FromArgb(34, 197, 94);
        public static readonly Color Warning = Color.FromArgb(245, 158, 11);
        public static readonly Color Error = Color.FromArgb(248, 113, 113);
    }

    internal static class IconFactory
    {
        public static Bitmap Refresh(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            using (var brush = new SolidBrush(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawArc(pen, 3, 3, 12, 12, 35, 270);
                graphics.FillPolygon(brush, new[] { new Point(13, 3), new Point(13, 8), new Point(16, 5) });
            }
            return bitmap;
        }

        public static Bitmap Sync(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            using (var brush = new SolidBrush(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawLine(pen, 3, 5, 13, 5);
                graphics.FillPolygon(brush, new[] { new Point(13, 2), new Point(17, 5), new Point(13, 8) });
                graphics.DrawLine(pen, 15, 12, 5, 12);
                graphics.FillPolygon(brush, new[] { new Point(5, 9), new Point(1, 12), new Point(5, 15) });
            }
            return bitmap;
        }

        public static Bitmap Power(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawArc(pen, 4, 5, 10, 10, 35, 290);
                graphics.DrawLine(pen, 9, 2, 9, 9);
            }
            return bitmap;
        }

        public static Bitmap Settings(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawEllipse(pen, 5, 5, 8, 8);
                graphics.DrawEllipse(pen, 8, 8, 2, 2);
                graphics.DrawLine(pen, 9, 1, 9, 4);
                graphics.DrawLine(pen, 9, 14, 9, 17);
                graphics.DrawLine(pen, 1, 9, 4, 9);
                graphics.DrawLine(pen, 14, 9, 17, 9);
                graphics.DrawLine(pen, 3, 3, 5, 5);
                graphics.DrawLine(pen, 13, 13, 15, 15);
                graphics.DrawLine(pen, 15, 3, 13, 5);
                graphics.DrawLine(pen, 5, 13, 3, 15);
            }
            return bitmap;
        }

        public static Bitmap Folder(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawLine(pen, 2, 5, 7, 5);
                graphics.DrawLine(pen, 7, 5, 9, 7);
                graphics.DrawLine(pen, 9, 7, 16, 7);
                graphics.DrawRectangle(pen, 2, 7, 14, 8);
            }
            return bitmap;
        }

        public static Bitmap Close(Color color)
        {
            var bitmap = NewBitmap();
            using (var graphics = Graphics.FromImage(bitmap))
            using (var pen = NewPen(color))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.DrawLine(pen, 5, 5, 13, 13);
                graphics.DrawLine(pen, 13, 5, 5, 13);
            }
            return bitmap;
        }

        private static Bitmap NewBitmap()
        {
            return new Bitmap(18, 18);
        }

        private static Pen NewPen(Color color)
        {
            return new Pen(color, 2F);
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
            AddRow(statusList, "User locale", CultureInfo.CurrentCulture.Name);
            AddRow(statusList, "Time zone", TimeZoneInfo.Local.DisplayName);
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
