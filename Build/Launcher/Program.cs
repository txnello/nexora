// NEXORA launcher (Nexora.exe)
//
// Windows executable with no console. Hosts the Windows PowerShell engine (included in Windows 10/11) INSIDE its own
// process and launches app\Start-Nexora.ps1: the user only sees NEXORA's WPF window (no console, no
// technical window, the process is named Nexora.exe). Shows the splash screen immediately at startup, on a
// separate thread, and closes it when the main window is ready.
//
// C# 5 only (csc of .NET Framework 4.x, present in every Windows 10/11).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

namespace NexoraLauncher
{
    // Object exposed to the script as the $NexoraHost variable
    public class LauncherHost
    {
        private Form splash;
        private readonly Stopwatch shown = new Stopwatch();
        private const int MinSplashMs = 1400;
        private readonly object sync = new object();
        private bool closed;

        public void ShowSplash(string imagePath)
        {
            if (!File.Exists(imagePath)) return;
            // the event is not released: the splash thread signals it even after the wait (avoids ObjectDisposedException)
            ManualResetEvent ready = new ManualResetEvent(false);
            Thread t = new Thread(delegate()
            {
                try
                {
                    Application.EnableVisualStyles();
                    Image img = Image.FromFile(imagePath);
                    Rectangle wa = Screen.PrimaryScreen.WorkingArea;
                    int w = Math.Max(720, Math.Min(1100, (int)(wa.Width * 0.46)));
                    int h = (int)(w * 9.0 / 16.0);
                    Form f = new Form();
                    f.FormBorderStyle = FormBorderStyle.None;
                    f.StartPosition = FormStartPosition.CenterScreen;
                    f.ShowInTaskbar = false;
                    f.TopMost = true;
                    f.BackColor = Color.FromArgb(7, 11, 31);
                    f.ClientSize = new Size(w, h);
                    PictureBox pb = new PictureBox();
                    pb.Dock = DockStyle.Fill;
                    pb.SizeMode = PictureBoxSizeMode.Zoom;
                    pb.Image = img;
                    f.Controls.Add(pb);
                    f.Shown += delegate { shown.Start(); ready.Set(); };
                    lock (sync) { splash = f; }
                    Application.Run(f);
                }
                catch (Exception) { }
                finally { try { ready.Set(); } catch (Exception) { } }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            ready.WaitOne(4000);
        }

        // Called by the script when the main window has been rendered. Does not block the caller.
        public void CloseSplash()
        {
            Form f;
            lock (sync) { if (closed) return; closed = true; f = splash; }
            if (f == null) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                int wait = MinSplashMs - (int)shown.ElapsedMilliseconds;
                if (wait > 0) Thread.Sleep(wait);
                try { f.BeginInvoke((MethodInvoker)delegate { f.Close(); }); } catch (Exception) { }
            });
        }
    }

    public static class Program
    {
        private const string MutexName = "NEXORA.SingleInstance";   // also read by the installer (AppMutex)
        private const string ActivationEventName = "Local\\NEXORA.ActivateExisting";

        private static void ActivateExistingInstance()
        {
            try
            {
                using (EventWaitHandle activation = EventWaitHandle.OpenExisting(ActivationEventName))
                    activation.Set();
            }
            catch (WaitHandleCannotBeOpenedException)
            {
            }
        }

        [STAThread]
        public static int Main(string[] args)
        {
            bool created;
            Mutex single = new Mutex(true, MutexName, out created);
            if (!created)
            {
                ActivateExistingInstance();
                return 0;
            }
            int exitCode = 0;
            LauncherHost host = new LauncherHost();
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string appDir = Path.Combine(baseDir, "app");
                string script = Path.Combine(appDir, "Start-Nexora.ps1");
                if (!File.Exists(script))
                {
                    MessageBox.Show("NEXORA is not installed correctly (app\\Start-Nexora.ps1 not found).\r\nPlease reinstall the application.",
                        "NEXORA", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 2;
                }
                host.ShowSplash(Path.Combine(appDir, "Assets", "Branding", "nexora-splash.png"));

                // the PowerShell engine must run on an STA thread (WPF)
                Thread worker = new Thread(delegate() { exitCode = RunScript(host, script, args); });
                worker.SetApartmentState(ApartmentState.STA);
                worker.Start();
                worker.Join();
            }
            catch (Exception ex)
            {
                LogError("Launcher failure: " + ex);
                MessageBox.Show("NEXORA could not start:\r\n\r\n" + ex.Message, "NEXORA", MessageBoxButtons.OK, MessageBoxIcon.Error);
                exitCode = 1;
            }
            finally
            {
                host.CloseSplash();
                GC.KeepAlive(single);
            }
            return exitCode;
        }

        private static int RunScript(LauncherHost host, string script, string[] args)
        {
            try
            {
                InitialSessionState iss = InitialSessionState.CreateDefault();
                iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;   // valid only for this process
                using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
                {
                    rs.ApartmentState = ApartmentState.STA;
                    rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    rs.Open();
                    rs.SessionStateProxy.SetVariable("NexoraHost", host);
                    using (PowerShell ps = PowerShell.Create())
                    {
                        ps.Runspace = rs;
                        ps.AddCommand(script).AddParameter("NoRelaunch");
                        for (int i = 0; i + 1 < args.Length; i += 2)
                            if (args[i].StartsWith("-")) ps.AddParameter(args[i].TrimStart('-'), args[i + 1]);
                        ps.Invoke();
                        if (ps.Streams.Error.Count > 0)
                        {
                            List<string> errs = new List<string>();
                            foreach (ErrorRecord er in ps.Streams.Error) errs.Add(er.ToString());
                            LogError("PowerShell errors:\r\n" + string.Join("\r\n", errs.ToArray()));
                        }
                    }
                }
                return 0;
            }
            catch (Exception ex)
            {
                LogError("Startup failure: " + ex);
                host.CloseSplash();
                MessageBox.Show("NEXORA could not start:\r\n\r\n" + ex.Message + "\r\n\r\nDetails: %LOCALAPPDATA%\\Nexora\\Logs",
                    "NEXORA", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static void LogError(string text)
        {
            try
            {
                string dir = Environment.GetEnvironmentVariable("NEXORA_DATA");
                if (string.IsNullOrEmpty(dir))
                    dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nexora");
                dir = Path.Combine(dir, "Logs");
                Directory.CreateDirectory(dir);
                File.AppendAllText(Path.Combine(dir, "launcher.log"), DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + text + "\r\n");
            }
            catch (Exception) { }
        }
    }
}
