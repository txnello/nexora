// Native.cs - shared C# code. Compiled into Nexora.exe (fast startup, no compiler at runtime);
// when running from sources (Start-Nexora.ps1) it is compiled on the fly with Add-Type. C# 5 only (compatible with csc of .NET Framework 4).
using System;
using System.Runtime.InteropServices;

// Task table row (WPF binding + typed sorting)
public class TaskRow
{
    public string Id { get; set; }
    public bool BulkSelected { get; set; }
    public string Code { get; set; }
    public string Title { get; set; }
    public string Description { get; set; }
    public string Snippet { get; set; }
    public string Link { get; set; }
    public object LinkCommand { get; set; }
    public string Referent { get; set; }
    public string Project { get; set; }
    public string Group { get; set; }
    public string StatusName { get; set; }
    public string StatusColor { get; set; }
    public string StatusBg { get; set; }
    public int StatusOrder { get; set; }
    public string PriorityName { get; set; }
    public string PriorityColor { get; set; }
    public string PriorityBg { get; set; }
    public double PriorityValue { get; set; }
    public string DueText { get; set; }
    public string DueHint { get; set; }
    public DateTime DueSort { get; set; }
    public bool IsOverdue { get; set; }
    public bool IsUrgent { get; set; }
    public bool IsClosed { get; set; }
    public int Reminders { get; set; }
    public string ReminderText { get; set; }
    public string ReminderTip { get; set; }
    public double ScoreValue { get; set; }
    public double ScoreBar { get; set; }
    public string ScoreText { get; set; }
    public string ScoreColor { get; set; }
    public string RowState { get; set; }
    public int ClosedRank { get; set; }
    public DateTime UpdatedSort { get; set; }
    public string CompletedText { get; set; }
    public DateTime CompletedSort { get; set; }
}

namespace Stm
{
    public static class Dwm
    {
        // dark/light title bar (DWMWA_USE_IMMERSIVE_DARK_MODE = 20)
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    }

    public static class Native
    {
        [DllImport("shell32.dll")]
        private static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

        // Process identity for the taskbar: groups windows under NEXORA and links the shortcut's icon
        public static void SetAppId(string appId)
        {
            try { SetCurrentProcessExplicitAppUserModelID(appId); } catch (Exception) { }
        }
    }
}
