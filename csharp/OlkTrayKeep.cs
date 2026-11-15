using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace OlkTrayKeep
{
    internal static class Native
    {
        public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);

        public const int SW_HIDE = 0;
        public const int SW_SHOW = 5;
        public const int SW_RESTORE = 9;
        public const string OlkClass = "Outlook Host";

        public static IntPtr FindByPidClass(int pid, string cls)
        {
            IntPtr found = IntPtr.Zero;
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                uint p;
                GetWindowThreadProcessId(h, out p);
                if ((int)p != pid) return true;
                StringBuilder sb = new StringBuilder(512);
                GetClassName(h, sb, 512);
                if (sb.ToString() == cls) { found = h; return false; }
                return true;
            }, IntPtr.Zero);
            return found;
        }
    }

    internal class TrayContext : ApplicationContext
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValueName = "OutlookTrayKeep";
        private const string OlkRelPath = @"Microsoft\WindowsApps\olk.exe";

        private readonly NotifyIcon _tray;
        private readonly System.Windows.Forms.Timer _timer;
        private readonly string _logPath;
        private IntPtr _hwnd;
        private bool _hiddenByUs;
        private bool _armed;
        private bool _keepAlive = true;
        private bool _relaunching;
        private DateTime _lastRelaunch = DateTime.MinValue;

        public TrayContext(bool boot)
        {
            _logPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "olktraykeep.log");
            _tray = new NotifyIcon();
            _tray.Icon = LoadIcon();
            _tray.Text = "Outlook 后台保活";
            _tray.Visible = true;
            _tray.DoubleClick += delegate { Toggle(); };

            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem miShow = new ToolStripMenuItem("显示 Outlook");
            miShow.Click += delegate { ShowOutlook(); };
            ToolStripMenuItem miHide = new ToolStripMenuItem("隐藏到托盘");
            miHide.Click += delegate { HideOutlook(); };
            ToolStripMenuItem miKeep = new ToolStripMenuItem("关闭后自动重建（后台收信）");
            miKeep.Checked = _keepAlive;
            miKeep.Click += delegate { _keepAlive = !_keepAlive; miKeep.Checked = _keepAlive; Log("keepAlive=" + _keepAlive); };
            ToolStripMenuItem miAuto = new ToolStripMenuItem("开机自启（本助手）");
            miAuto.Checked = IsAutoStartEnabled();
            miAuto.Click += delegate { SetAutoStart(!miAuto.Checked); miAuto.Checked = IsAutoStartEnabled(); Log("autostart=" + miAuto.Checked); };
            ToolStripMenuItem miExit = new ToolStripMenuItem("退出助手");
            miExit.Click += delegate { Quit(); };

            menu.Items.Add(miShow);
            menu.Items.Add(miHide);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(miKeep);
            menu.Items.Add(miAuto);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(miExit);
            _tray.ContextMenuStrip = menu;

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 800;
            _timer.Tick += delegate { Tick(); };
            _timer.Start();

            Log("start boot=" + boot);
            if (boot) { LaunchThenHide(); }
        }

        private static Icon LoadIcon()
        {
            try
            {
                string alias = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), OlkRelPath);
                if (File.Exists(alias))
                {
                    Icon ic = Icon.ExtractAssociatedIcon(alias);
                    if (ic != null) return ic;
                }
            }
            catch { }
            return SystemIcons.Application;
        }

        private void Log(string msg)
        {
            try
            {
                File.AppendAllText(_logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + Environment.NewLine);
            }
            catch { }
        }

        private static Process Olk()
        {
            try
            {
                Process[] all = Process.GetProcessesByName("olk");
                if (all.Length == 0) return null;
                return all[0];
            }
            catch { return null; }
        }

        private void Tick()
        {
            try
            {
                Process p = Olk();
                if (p == null)
                {
                    _hwnd = IntPtr.Zero;
                    _hiddenByUs = false;
                    if (_armed && _keepAlive && !_relaunching && (DateTime.Now - _lastRelaunch).TotalSeconds > 25)
                    {
                        Log("outlook process gone -> relaunch");
                        LaunchThenHide();
                    }
                    return;
                }

                IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
                if (h == IntPtr.Zero) return;
                _hwnd = h;
                _armed = true;

                if (Native.IsIconic(h) && !_hiddenByUs)
                {
                    Native.ShowWindow(h, Native.SW_HIDE);
                    _hiddenByUs = true;
                    Log("minimized -> tray");
                }
                else if (_hiddenByUs && Native.IsWindowVisible(h))
                {
                    _hiddenByUs = false;
                    Log("visible again -> untrack");
                }
            }
            catch { }
        }

        private void LaunchThenHide()
        {
            _lastRelaunch = DateTime.Now;
            _relaunching = true;
            try
            {
                string alias = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), OlkRelPath);
                ProcessStartInfo psi = new ProcessStartInfo(alias);
                psi.UseShellExecute = true;
                psi.WorkingDirectory = Path.GetDirectoryName(alias);
                Process.Start(psi);
                System.Threading.ThreadPool.QueueUserWorkItem(delegate { HideWhenReady(false, 60); });
            }
            catch (Exception ex)
            {
                _relaunching = false;
                Log("launch failed: " + ex.Message);
            }
        }

        private void ShowWhenReady()
        {
            System.Threading.ThreadPool.QueueUserWorkItem(delegate { HideWhenReady(true, 60); });
        }

        private void HideWhenReady(bool showInstead, int timeoutSec)
        {
            DateTime end = DateTime.Now.AddSeconds(timeoutSec);
            while (DateTime.Now < end)
            {
                Process p = Olk();
                if (p != null)
                {
                    IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
                    if (h != IntPtr.Zero && Native.IsWindowVisible(h))
                    {
                        if (showInstead)
                        {
                            Native.ShowWindow(h, Native.SW_SHOW);
                            Native.ShowWindow(h, Native.SW_RESTORE);
                            Native.SetForegroundWindow(h);
                            _hiddenByUs = false;
                            Log("shown after launch");
                        }
                        else
                        {
                            Native.ShowWindow(h, Native.SW_HIDE);
                            _hiddenByUs = true;
                            Log("hidden after launch");
                        }
                        _relaunching = false;
                        _hwnd = h;
                        _armed = true;
                        return;
                    }
                }
                System.Threading.Thread.Sleep(400);
            }
            _relaunching = false;
            Log("launch wait timeout");
        }

        private void Toggle()
        {
            Process p = Olk();
            if (p == null) { LaunchThenHide(); ShowWhenReady(); return; }
            IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
            if (h == IntPtr.Zero) { ShowWhenReady(); return; }
            if (_hiddenByUs || !Native.IsWindowVisible(h)) ShowOutlook();
            else HideOutlook();
        }

        private void ShowOutlook()
        {
            Process p = Olk();
            if (p == null) { LaunchThenHide(); ShowWhenReady(); Log("show -> launch"); return; }
            IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
            if (h == IntPtr.Zero) { ShowWhenReady(); return; }
            Native.ShowWindow(h, Native.SW_SHOW);
            Native.ShowWindow(h, Native.SW_RESTORE);
            Native.SetForegroundWindow(h);
            _hwnd = h;
            _hiddenByUs = false;
            _armed = true;
            Log("show");
        }

        private void HideOutlook()
        {
            Process p = Olk();
            if (p == null) return;
            IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
            if (h == IntPtr.Zero) return;
            Native.ShowWindow(h, Native.SW_HIDE);
            _hwnd = h;
            _hiddenByUs = true;
            Log("hide");
        }

        internal static bool IsAutoStartEnabled()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKeyPath, false))
                {
                    if (k == null) return false;
                    object v = k.GetValue(RunValueName);
                    return v != null;
                }
            }
            catch { return false; }
        }

        internal static void SetAutoStart(bool enable)
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (k == null) return;
                    if (enable)
                    {
                        string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        k.SetValue(RunValueName, "\"" + exe + "\" --boot");
                    }
                    else
                    {
                        k.DeleteValue(RunValueName, false);
                    }
                }
            }
            catch { }
        }

        private void Quit()
        {
            Log("quit");
            _timer.Stop();
            _tray.Visible = false;
            _tray.Dispose();
            Application.Exit();
        }
    }

    internal static class Program
    {
        private static int RunMode(string[] args)
        {
            if (args.Length == 0) return -1;
            string m = args[0].ToLowerInvariant();
            if (m == "--status")
            {
                Process p = Proc();
                if (p == null) { Console.WriteLine("olk: not running"); return 0; }
                IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
                Console.WriteLine("olk pid=" + p.Id + " hwnd=" + h + " visible=" + Native.IsWindowVisible(h) + " iconic=" + Native.IsIconic(h));
                return 0;
            }
            if (m == "--simulate-close")
            {
                Process p = Proc();
                if (p == null) { Console.WriteLine("olk: not running"); return 1; }
                IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
                if (h == IntPtr.Zero) { Console.WriteLine("no Outlook Host window"); return 1; }
                Console.WriteLine("WM_CLOSE posted=" + Native.PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero));
                return 0;
            }
            if (m == "--hide" || m == "--show")
            {
                Process p = Proc();
                if (p == null) { Console.WriteLine("olk: not running"); return 1; }
                IntPtr h = Native.FindByPidClass(p.Id, Native.OlkClass);
                if (h == IntPtr.Zero) { Console.WriteLine("no window"); return 1; }
                if (m == "--hide") Native.ShowWindow(h, Native.SW_HIDE);
                else { Native.ShowWindow(h, Native.SW_SHOW); Native.ShowWindow(h, Native.SW_RESTORE); Native.SetForegroundWindow(h); }
                Console.WriteLine(m + " done hwnd=" + h);
                return 0;
            }
            if (m == "--autostart-on") { TrayContext.SetAutoStart(true); Console.WriteLine("autostart=" + TrayContext.IsAutoStartEnabled()); return 0; }
            if (m == "--autostart-off") { TrayContext.SetAutoStart(false); Console.WriteLine("autostart=" + TrayContext.IsAutoStartEnabled()); return 0; }
            return -1;
        }

        internal static Process Proc()
        {
            try { Process[] all = Process.GetProcessesByName("olk"); return all.Length == 0 ? null : all[0]; }
            catch { return null; }
        }

        [STAThread]
        private static void Main(string[] args)
        {
            int handled = RunMode(args);
            if (handled >= 0) return;
            bool boot = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i].ToLowerInvariant() == "--boot") boot = true;
            }
            bool created = false;
            System.Threading.Mutex mutex = new System.Threading.Mutex(true, "OlkTrayKeep_SingleInstance_v1", out created);
            if (!created) return;
            Application.EnableVisualStyles();
            Application.Run(new TrayContext(boot));
            GC.KeepAlive(mutex);
        }
    }
}