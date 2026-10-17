@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$f='%~f0'; iex ((Get-Content -LiteralPath $f -Raw) -split ('#P'+'S#'),2)[1]"
exit /b
#PS#
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# Lets the script notice the Esc key even while another program (like Explorer) has focus.
$global:keysOk = $false
try {
    Add-Type -Namespace LK -Name Keys -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);' -ErrorAction Stop
    $global:keysOk = $true
} catch { }

# ---------- C# helpers: corrupted popups, glitch overlay, fake QR code ----------
$csCode = @'
using System;
using System.Drawing;
using System.Drawing.Text;
using System.Text;
using System.Windows.Forms;

public static class Corrupt
{
    public static Random R = new Random();
    public const string Syms = "\u2588\u2593\u2592\u2591\u2580\u2584\u25A0\u25B2\u25BC\u25C6\u03A9\u2211\u2206\u2248\u00A7\u00B6\u2021\u2020\u2620\u26A0\u00BF\u00D8\u00DE\u00D0\u00A4\u00A6\u0394\u03A8\u0416#@%&$?!*/|<>~^0123456789ABCDEF";

    public static string Pick() { return Syms[R.Next(Syms.Length)].ToString(); }

    public static string Scramble(string s, double amount)
    {
        char[] c = s.ToCharArray();
        for (int i = 0; i < c.Length; i++)
        {
            if (c[i] == ' ' || c[i] == '\n' || c[i] == '\r') continue;
            if (R.NextDouble() < amount) c[i] = Syms[R.Next(Syms.Length)];
        }
        return new string(c);
    }

    public static string Zalgo(string s, int level)
    {
        StringBuilder sb = new StringBuilder();
        foreach (char ch in s)
        {
            sb.Append(ch);
            if (ch == ' ' || ch == '\n') continue;
            int n = R.Next(0, level + 1);
            for (int k = 0; k < n; k++) sb.Append((char)R.Next(0x0300, 0x0370));
        }
        return sb.ToString();
    }

    public static string Hex(int digits)
    {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < digits; i++) sb.Append("0123456789ABCDEF"[R.Next(16)]);
        return sb.ToString();
    }

    public static string Noise(int len)
    {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < len; i++) sb.Append(Syms[R.Next(Syms.Length)]);
        return sb.ToString();
    }
}

public class CorruptPopup : Form
{
    string message, head, sub1, sub2;
    Timer t;
    int tick;
    Point basePos;
    static string[] titles = new string[] { "CRITICAL ERROR", "System Failure", "ERR_0xC000021A", "DISK FAILURE", "Windows", "fatal_exception", "SYSTEM32" };
    static string[] files = new string[] {
        "C:\\Windows\\System32\\kernel32.dll", "C:\\Windows\\System32\\ntoskrnl.exe", "C:\\Users\\Documents\\",
        "C:\\Users\\Pictures\\", "C:\\Windows\\boot.ini", "C:\\ProgramData\\registry.dat",
        "C:\\Users\\Desktop\\", "D:\\Backup\\archive.zip", "C:\\Windows\\System32\\config\\SAM" };

    public CorruptPopup(string msg)
    {
        message = msg;
        head = msg;
        DoubleBuffered = true;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        KeyPreview = true;
        BackColor = Color.Black;
        ClientSize = new Size(400, 150);
        Text = titles[Corrupt.R.Next(titles.Length)];
        Reroll();
        t = new Timer();
        t.Interval = 70;
        t.Tick += OnTick;
    }

    void Reroll()
    {
        sub1 = "ERR 0x" + Corrupt.Hex(8) + "   SECTOR " + Corrupt.R.Next(1000, 999999);
        sub2 = files[Corrupt.R.Next(files.Length)] + "  [" + Corrupt.R.Next(60, 101) + "% LOST]";
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        basePos = Location;
        t.Start();
    }

    void OnTick(object s, EventArgs e)
    {
        if (IsDisposed) return;
        tick++;
        Random r = Corrupt.R;
        head = message;
        double d = r.NextDouble();
        if (d < 0.35) head = Corrupt.Scramble(message, 0.18);
        else if (d < 0.55) head = Corrupt.Zalgo(message, 4);
        if (tick % 2 == 0) Reroll();
        if (r.NextDouble() < 0.3) Location = new Point(basePos.X + r.Next(-5, 6), basePos.Y + r.Next(-4, 5));
        else Location = basePos;
        Invalidate();
    }

    protected override void Dispose(bool disposing)
    {
        if (t != null) t.Stop();
        base.Dispose(disposing);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        Random r = Corrupt.R;
        g.Clear(Color.FromArgb(8, 0, 0));
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

        using (Pen border = new Pen(Color.FromArgb(200, 0, 0), 3))
            g.DrawRectangle(border, 1, 1, ClientSize.Width - 3, ClientSize.Height - 3);

        using (Brush ib = new SolidBrush(Color.FromArgb(200, 0, 0)))
            g.FillEllipse(ib, 22, 30, 46, 46);
        using (Pen xp = new Pen(Color.White, 5))
        {
            g.DrawLine(xp, 36, 44, 54, 62);
            g.DrawLine(xp, 54, 44, 36, 62);
        }

        using (Font hf = new Font("Consolas", 19, FontStyle.Bold))
        using (StringFormat sf = new StringFormat())
        {
            sf.LineAlignment = StringAlignment.Center;
            int off = r.NextDouble() < 0.4 ? r.Next(2, 6) : 1;
            RectangleF rc = new RectangleF(80, 24, 310, 60);
            using (Brush c1 = new SolidBrush(Color.FromArgb(0, 255, 255)))
                g.DrawString(head, hf, c1, new RectangleF(rc.X - off, rc.Y, rc.Width, rc.Height), sf);
            using (Brush c2 = new SolidBrush(Color.FromArgb(255, 0, 40)))
                g.DrawString(head, hf, c2, new RectangleF(rc.X + off, rc.Y, rc.Width, rc.Height), sf);
            if (r.NextDouble() < 0.8)
                using (Brush c3 = new SolidBrush(Color.White))
                    g.DrawString(head, hf, c3, rc, sf);
        }

        using (Font sfont = new Font("Consolas", 9))
        using (Brush gr = new SolidBrush(Color.FromArgb(220, 60, 60)))
        {
            g.DrawString(sub1, sfont, gr, 24, 96);
            g.DrawString(sub2, sfont, gr, 24, 114);
        }

        int n = r.Next(1, 5);
        for (int i = 0; i < n; i++)
        {
            int y = r.Next(0, ClientSize.Height);
            int h = r.Next(1, 6);
            int x = r.Next(0, 200);
            int w = r.Next(40, 300);
            Color c = r.Next(2) == 0 ? Color.FromArgb(255, 0, 0) : Color.FromArgb(0, 200, 200);
            using (Brush nb = new SolidBrush(c)) g.FillRectangle(nb, x, y, w, h);
        }

        using (Font nf = new Font("Consolas", 8))
        using (Brush nbr = new SolidBrush(Color.FromArgb(120, 0, 0)))
            g.DrawString(Corrupt.Noise(58), nf, nbr, 8, 133);
    }
}

public class GlitchOverlay : Form
{
    public int Intensity;
    Timer t;

    public GlitchOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        DoubleBuffered = true;
        Bounds = Screen.PrimaryScreen.Bounds;
        t = new Timer();
        t.Interval = 55;
        t.Tick += delegate { Invalidate(); };
    }

    public void Begin() { t.Start(); }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000;
            return cp;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (t != null) t.Stop();
        base.Dispose(disposing);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.None;
        g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;
        g.Clear(Color.Magenta);
        int I = Intensity;
        if (I <= 0) return;
        Random r = Corrupt.R;
        int W = Width, H = Height;
        Color[] pal = new Color[] {
            Color.FromArgb(255, 0, 0), Color.FromArgb(1, 1, 1), Color.FromArgb(0, 255, 255),
            Color.White, Color.FromArgb(110, 0, 0), Color.FromArgb(0, 255, 70) };

        int bars = 1 + I / 7;
        for (int i = 0; i < bars; i++)
        {
            int h = r.Next(2, 6 + I / 3);
            int y = r.Next(0, H);
            int x = r.Next(-60, W / 2);
            int w = r.Next(W / 8, W);
            Color c = pal[r.Next(pal.Length)];
            using (Brush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, h);
            if (h > 14 && r.NextDouble() < 0.6)
            {
                bool dark = (c.R < 20 && c.G < 20 && c.B < 20);
                using (Font f = new Font("Consolas", Math.Max(6, h - 4), FontStyle.Bold))
                using (Brush tb = new SolidBrush(dark ? Color.Red : Color.Black))
                    g.DrawString(Corrupt.Noise(r.Next(8, 40)), f, tb, x + 4, y);
            }
        }

        int dots = I * 3;
        for (int i = 0; i < dots; i++)
        {
            int s = r.Next(2, 7);
            int v = r.Next(30, 255);
            using (Brush b = new SolidBrush(Color.FromArgb(v, v, v)))
                g.FillRectangle(b, r.Next(W), r.Next(H), s, s);
        }

        int glyphs = I / 3;
        for (int i = 0; i < glyphs; i++)
        {
            int sz = r.Next(9, 14 + I / 2);
            string s = r.NextDouble() < 0.5 ? Corrupt.Pick() : Corrupt.Noise(r.Next(2, 8));
            double q = r.NextDouble();
            Color c = q < 0.5 ? Color.FromArgb(200, 0, 0) : (q < 0.8 ? Color.White : Color.FromArgb(1, 1, 1));
            using (Font f = new Font("Consolas", sz))
            using (Brush b = new SolidBrush(c))
                g.DrawString(s, f, b, r.Next(W), r.Next(H));
        }

        if (r.NextDouble() < I / 350.0)
        {
            string word = r.NextDouble() < 0.5 ? "FILES CORRUPTED" : Corrupt.Scramble("FILES CORRUPTED", 0.3);
            int sz = r.Next(36, 40 + I);
            int x = r.Next(-20, Math.Max(1, W / 3));
            int y = r.Next(0, Math.Max(1, H - sz * 2));
            using (Font f = new Font("Consolas", sz, FontStyle.Bold))
            {
                using (Brush b1 = new SolidBrush(Color.FromArgb(0, 255, 255))) g.DrawString(word, f, b1, x - 4, y);
                using (Brush b2 = new SolidBrush(Color.FromArgb(255, 0, 40))) g.DrawString(word, f, b2, x + 4, y);
                using (Brush b3 = new SolidBrush(Color.White)) g.DrawString(word, f, b3, x, y);
            }
        }
    }
}

public class FakeQr : Control
{
    int n = 25;
    bool[,] m;

    public FakeQr()
    {
        DoubleBuffered = true;
        Size = new Size(120, 120);
        BackColor = Color.White;
        m = new bool[n, n];
        Random r = new Random(11);
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                m[i, j] = r.NextDouble() < 0.5;
        Finder(0, 0);
        Finder(n - 7, 0);
        Finder(0, n - 7);
    }

    void Finder(int ox, int oy)
    {
        for (int dx = -1; dx <= 7; dx++)
            for (int dy = -1; dy <= 7; dy++)
            {
                int x = ox + dx, y = oy + dy;
                if (x < 0 || y < 0 || x >= n || y >= n) continue;
                bool inside = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6;
                if (!inside) { m[x, y] = false; continue; }
                bool ring = dx == 0 || dx == 6 || dy == 0 || dy == 6;
                bool core = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
                m[x, y] = ring || core;
            }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(Color.White);
        int cell = (Width - 8) / n;
        using (Brush b = new SolidBrush(Color.Black))
            for (int i = 0; i < n; i++)
                for (int j = 0; j < n; j++)
                    if (m[i, j]) g.FillRectangle(b, 4 + i * cell, 4 + j * cell, cell, cell);
    }
}
'@

# ---------- settings file ----------
$dir = Split-Path -Parent $f
$settingsFile = Join-Path $dir 'Ignore (ugly cats).ini'
$cfg = @{}

$def = @{
    ShowMenu = 'true'; AllowEscape = 'true'; GlitchEffects = 'true'
    Image = 'image.jpg'; WaitSeconds = '3'
    PopupText = 'FILES CORRUPTED!'; PopupCount = '40'; PopupSeconds = '4'
    MinigameEnabled = 'true'; MinigameFiles = '7'; MinigameSeconds = '60'; MinigameSpeed = '5'
    TauntsEnabled = 'true'; TauntMin = '3'; TauntMax = '6'
    Sound = ''; BsodSeconds = '5'; ShutdownEnabled = 'true'
    JumpscareImage = ''; JumpscareSound = ''
}

function Load-Cfg {
    $script:cfg = @{}
    if (Test-Path -LiteralPath $settingsFile) {
        Get-Content -LiteralPath $settingsFile | ForEach-Object {
            if ($_ -match '^\s*([^#;=\s][^=]*?)\s*=\s*(.*?)\s*$') { $script:cfg[$matches[1]] = $matches[2] }
        }
    }
}
function Get-Val($key) {
    if ($cfg.ContainsKey($key) -and $null -ne $cfg[$key]) { return $cfg[$key] }
    return $def[$key]
}
function Get-Bool($key) { return ((Get-Val $key) -ne 'false') }
function Get-Num($key, $default) {
    $v = 0.0
    $s = Get-Val $key
    if ($s -and [double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
        return [Math]::Max(0, $v)
    }
    return $default
}
function Resolve-Setting($p) {
    if (-not $p) { return $p }
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $dir $p }
    return $p
}

# ---------- settings menu ----------
$global:ctl = @{}
$global:ctlOrder = New-Object System.Collections.ArrayList

function Add-Check($page, $key, $text, $y) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $text
    $c.SetBounds(16, $y, 500, 26)
    $c.Checked = (Get-Bool $key)
    $page.Controls.Add($c)
    $global:ctl[$key] = $c
    [void]$global:ctlOrder.Add($key)
    return ($y + 30)
}
function Add-Num($page, $key, $text, $y, $min, $max, $dec) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.SetBounds(16, ($y + 3), 340, 22)
    $n = New-Object Windows.Forms.NumericUpDown
    $n.DecimalPlaces = $dec
    $n.Minimum = [decimal]$min
    $n.Maximum = [decimal]$max
    if ($dec -gt 0) { $n.Increment = [decimal]0.5 }
    $val = [decimal](Get-Num $key 0)
    if ($val -lt $n.Minimum) { $val = $n.Minimum }
    if ($val -gt $n.Maximum) { $val = $n.Maximum }
    $n.Value = $val
    $n.SetBounds(370, $y, 90, 26)
    $page.Controls.Add($l)
    $page.Controls.Add($n)
    $global:ctl[$key] = $n
    [void]$global:ctlOrder.Add($key)
    return ($y + 34)
}
function Add-Text($page, $key, $text, $y) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.SetBounds(16, $y, 500, 20)
    $t = New-Object Windows.Forms.TextBox
    $t.Text = (Get-Val $key)
    $t.SetBounds(16, ($y + 22), 500, 26)
    $page.Controls.Add($l)
    $page.Controls.Add($t)
    $global:ctl[$key] = $t
    [void]$global:ctlOrder.Add($key)
    return ($y + 58)
}
function Add-Path($page, $key, $text, $y, $filter) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.SetBounds(16, $y, 500, 20)
    $t = New-Object Windows.Forms.TextBox
    $t.Text = (Get-Val $key)
    $t.SetBounds(16, ($y + 22), 456, 26)
    $b = New-Object Windows.Forms.Button
    $b.Text = '...'
    $b.SetBounds(478, ($y + 21), 38, 28)
    $b.Tag = @{ tb = $t; filter = $filter }
    $b.Add_Click({
        param($s, $e)
        $d = New-Object Windows.Forms.OpenFileDialog
        $d.Filter = $s.Tag.filter
        if ($d.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $s.Tag.tb.Text = $d.FileName }
    })
    $page.Controls.Add($l)
    $page.Controls.Add($t)
    $page.Controls.Add($b)
    $global:ctl[$key] = $t
    [void]$global:ctlOrder.Add($key)
    return ($y + 58)
}
function Add-Note($page, $text, $y, $h) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.ForeColor = [Drawing.Color]::FromArgb(110, 110, 120)
    $l.SetBounds(16, $y, 510, $h)
    $page.Controls.Add($l)
    return ($y + $h + 6)
}

function Save-Settings {
    $lines = @('# Lil Kitty settings - written by the settings menu. You can also edit this file by hand.')
    foreach ($k in $global:ctlOrder) {
        $c = $global:ctl[$k]
        if ($c -is [Windows.Forms.CheckBox]) { $v = $(if ($c.Checked) { 'true' } else { 'false' }) }
        elseif ($c -is [Windows.Forms.NumericUpDown]) { $v = ([decimal]$c.Value).ToString([Globalization.CultureInfo]::InvariantCulture) }
        else { $v = $c.Text }
        $lines += "$k=$v"
    }
    Set-Content -LiteralPath $settingsFile -Value $lines -Encoding UTF8
}

function Show-Menu {
    $global:ctl = @{}
    $global:ctlOrder = New-Object System.Collections.ArrayList
    $imgFilter = 'Pictures|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All files|*.*'
    $sndFilter = 'Sounds|*.mp3;*.wav;*.wma;*.m4a|All files|*.*'

    $m = New-Object Windows.Forms.Form
    $m.Text = 'Lil Kitty - Cute Cat Pics'
    $m.ClientSize = New-Object Drawing.Size(580, 612)
    $m.StartPosition = 'CenterScreen'
    $m.FormBorderStyle = 'FixedDialog'
    $m.MaximizeBox = $false
    $m.MinimizeBox = $false
    $m.BackColor = [Drawing.Color]::White
    $m.Font = New-Object Drawing.Font('Segoe UI', 9.5)

    $banner = New-Object Windows.Forms.Panel
    $banner.SetBounds(0, 0, 580, 84)
    $banner.BackColor = [Drawing.Color]::FromArgb(255, 190, 215)
    $t1 = New-Object Windows.Forms.Label
    $t1.AutoSize = $true
    $t1.Text = 'Lil Kitty'
    $t1.Font = New-Object Drawing.Font('Segoe UI', 26, [Drawing.FontStyle]::Bold)
    $t1.ForeColor = [Drawing.Color]::FromArgb(130, 30, 85)
    $t1.Location = New-Object Drawing.Point(16, 4)
    $t2 = New-Object Windows.Forms.Label
    $t2.AutoSize = $true
    $t2.Text = 'Cute Cat Pics Viewer  -  Settings'
    $t2.Font = New-Object Drawing.Font('Segoe UI', 11)
    $t2.ForeColor = [Drawing.Color]::FromArgb(130, 30, 85)
    $t2.Location = New-Object Drawing.Point(20, 54)
    $banner.Controls.Add($t1)
    $banner.Controls.Add($t2)
    $m.Controls.Add($banner)

    $tabs = New-Object Windows.Forms.TabControl
    $tabs.SetBounds(12, 96, 556, 454)

    function New-Page($title) {
        $p = New-Object Windows.Forms.TabPage
        $p.Text = $title
        $p.UseVisualStyleBackColor = $false
        $p.BackColor = [Drawing.Color]::White
        return $p
    }

    $pg = New-Page 'General'
    $y = 14
    $y = Add-Check $pg 'ShowMenu' 'Show this menu when the program starts (hold Shift while launching to bring it back)' $y
    $y = Add-Check $pg 'AllowEscape' 'Allow the Esc key to cancel everything' $y
    $y = Add-Check $pg 'GlitchEffects' 'Creepy glitch effects (screen glitches, corrupted popup text, fake QR code)' $y
    $y = $y + 10
    $y = Add-Path $pg 'Image' 'Cat pic shown first (fullscreen)' $y $imgFilter
    $y = Add-Num $pg 'WaitSeconds' 'Seconds the picture is shown' $y 0 60 1
    $tabs.TabPages.Add($pg)

    $pg = New-Page 'Popups'
    $y = 14
    $y = Add-Text $pg 'PopupText' 'Popup message' $y
    $y = Add-Num $pg 'PopupCount' 'Number of popups' $y 0 200 0
    $y = Add-Num $pg 'PopupSeconds' 'Seconds for all popups to appear' $y 0 60 1
    $tabs.TabPages.Add($pg)

    $pg = New-Page 'Minigame'
    $y = 14
    $y = Add-Check $pg 'MinigameEnabled' 'Enable the "save the cat pics" minigame' $y
    $y = Add-Note $pg 'Win = "You''re Lucky." and it all ends. Lose = the blue screen. Small cat pictures are created on the Desktop, Downloads, Screenshots, Documents and Pictures, and are deleted afterwards.' $y 54
    $y = Add-Num $pg 'MinigameFiles' 'Cat pics to drag into the moving window' $y 1 20 0
    $y = Add-Num $pg 'MinigameSeconds' 'Time limit (seconds)' $y 5 600 0
    $y = Add-Num $pg 'MinigameSpeed' 'Speed of the moving window' $y 0 30 0
    $y = $y + 6
    $y = Add-Check $pg 'TauntsEnabled' 'Taunting tabs that chase your cursor (they cannot be moved)' $y
    $y = Add-Num $pg 'TauntMin' 'Fewest taunt tabs' $y 0 10 0
    $y = Add-Num $pg 'TauntMax' 'Most taunt tabs' $y 0 10 0
    $tabs.TabPages.Add($pg)

    $pg = New-Page 'Ending'
    $y = 14
    $y = Add-Num $pg 'BsodSeconds' 'Seconds for the blue screen counter to reach 100%' $y 1 120 1
    $y = Add-Path $pg 'Sound' 'Blue screen sound' $y $sndFilter
    $y = Add-Check $pg 'ShutdownEnabled' 'Shut the PC down at 100%  (unchecked = jumpscare instead, nothing shuts down)' $y
    $y = $y + 6
    $y = Add-Path $pg 'JumpscareImage' 'Jumpscare image (used when shutdown is unchecked)' $y $imgFilter
    $y = Add-Path $pg 'JumpscareSound' 'Jumpscare sound' $y $sndFilter
    $tabs.TabPages.Add($pg)

    $m.Controls.Add($tabs)

    $status = New-Object Windows.Forms.Label
    $status.SetBounds(130, 566, 200, 22)
    $status.ForeColor = [Drawing.Color]::FromArgb(0, 130, 60)
    $m.Controls.Add($status)

    $bExit = New-Object Windows.Forms.Button
    $bExit.Text = 'Exit'
    $bExit.SetBounds(12, 560, 100, 34)
    $bExit.Add_Click({ param($s, $e) $s.FindForm().DialogResult = [Windows.Forms.DialogResult]::Cancel })
    $bSave = New-Object Windows.Forms.Button
    $bSave.Text = 'Save'
    $bSave.SetBounds(348, 560, 100, 34)
    $bSave.Tag = $status
    $bSave.Add_Click({ param($s, $e) Save-Settings; $s.Tag.Text = 'Settings saved.' })
    $bStart = New-Object Windows.Forms.Button
    $bStart.Text = 'Start'
    $bStart.SetBounds(460, 560, 108, 34)
    $bStart.BackColor = [Drawing.Color]::FromArgb(255, 190, 215)
    $bStart.Add_Click({ param($s, $e) Save-Settings; $s.FindForm().DialogResult = [Windows.Forms.DialogResult]::OK })
    $m.Controls.Add($bExit)
    $m.Controls.Add($bSave)
    $m.Controls.Add($bStart)

    $res = $m.ShowDialog()
    return ($res -eq [Windows.Forms.DialogResult]::OK)
}

Load-Cfg
$shiftHeld = (([Windows.Forms.Control]::ModifierKeys -band [Windows.Forms.Keys]::Shift) -ne 0)
if ((Get-Bool 'ShowMenu') -or $shiftHeld) {
    $go = Show-Menu
    if (-not $go) { exit }
    Load-Cfg
}

# ---------- derived settings ----------
$imgPath = Get-Val 'Image'
if (-not $imgPath) { $imgPath = 'image.jpg' }
$imgPath = Resolve-Setting $imgPath

$wait         = Get-Num 'WaitSeconds' 3
$popupCount   = [int](Get-Num 'PopupCount' 40)
$popupSeconds = Get-Num 'PopupSeconds' 4
$bsodSeconds  = Get-Num 'BsodSeconds' 5
$popupText    = Get-Val 'PopupText'
if (-not $popupText) { $popupText = 'FILES CORRUPTED!' }
$soundPath    = Resolve-Setting (Get-Val 'Sound')
$jsImgPath    = Resolve-Setting (Get-Val 'JumpscareImage')
$jsSoundPath  = Resolve-Setting (Get-Val 'JumpscareSound')
$useFx        = Get-Bool 'GlitchEffects'
$allowEsc     = Get-Bool 'AllowEscape'

$mgEnabled    = Get-Bool 'MinigameEnabled'
$mgFiles      = [int](Get-Num 'MinigameFiles' 7)
$mgSeconds    = Get-Num 'MinigameSeconds' 60
$mgSpeed      = Get-Num 'MinigameSpeed' 5
$tauntsOn     = Get-Bool 'TauntsEnabled'
$tauntMin     = [int](Get-Num 'TauntMin' 3)
$tauntMax     = [int](Get-Num 'TauntMax' 6)
if ($tauntMax -lt $tauntMin) { $tauntMax = $tauntMin }

$global:doShutdown = (Get-Bool 'ShutdownEnabled')
$global:cancelled = $false
$global:imageOk = $false
$global:fx = $false
$global:popups = New-Object System.Collections.ArrayList
$global:popupsMade = 0
$global:bsod = $null
$global:jump = $null
$global:glitch = $null
$global:pctLabel = $null
$global:l2 = $null
$global:l2Orig = ''
$global:rand = New-Object Random
$bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds

# minigame state
$global:gameFiles = New-Object System.Collections.ArrayList
$global:gameDone = 0
$global:gameTotal = 0
$global:gameActive = $false
$global:winPending = $false
$global:box = $null
$global:lucky = $null
$global:taunts = New-Object System.Collections.ArrayList
$global:vx = 0
$global:vy = 0
$global:tickN = 0
$global:hint = ''
$global:gameWatch = New-Object Diagnostics.Stopwatch
$logFile = Join-Path $env:TEMP 'lilkitty_files.txt'
$catNames = @('Whiskers', 'Mittens', 'Luna', 'Oreo', 'Tiger', 'Shadow', 'Simba', 'Bella', 'Felix', 'Cleo', 'Pumpkin', 'Smokey')
$global:tauntLines = @('Too slow, kitty.', 'Is your mouse broken?', 'My grandma drags faster.', 'Tick tock...', 'Even a cat is faster than you.', 'Nice dragging. NOT.', 'You call that a drag?', 'Skill issue.', 'Give up yet?', 'Cats > you.', 'Are you even trying?', 'Wow. Just wow.', 'Lol. Lmao even.', 'Missed me!', 'Over here, slowpoke.', 'Your PC is mine now. Meow.')
$global:tauntReact = @("Beginner's luck.", 'Hmph. One down.', 'Okay, okay...', 'Not bad. For a human.')

# ---------- effects setup ----------
function Init-Fx {
    if (-not $useFx) { return }
    try {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $csCode -Language CSharp -ErrorAction Stop
        $global:fx = $true
    } catch { $global:fx = $false }
}

function Start-Glitch {
    if (-not $global:fx -or $global:glitch) { return }
    try {
        $g = New-Object GlitchOverlay
        $global:glitch = $g
        $g.Intensity = 12
        $g.Show()
        $g.Begin()
    } catch { $global:glitch = $null }
}
function Raise-Glitch {
    if ($global:glitch) { try { $global:glitch.TopMost = $false; $global:glitch.TopMost = $true } catch { } }
}
function Set-Glitch($v) {
    if ($global:glitch) { try { $global:glitch.Intensity = [int]$v } catch { } }
}

# ---------- sound ----------
$global:sndKind = 'none'
$global:wmp = $null
$global:mp = $null
$global:sawPlaying = $false
$global:soundWatch = New-Object Diagnostics.Stopwatch

function Start-Sound($path) {
    $global:soundWatch.Restart()
    $global:sawPlaying = $false
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { $global:sndKind = 'none'; return }
    try {
        $global:wmp = New-Object -ComObject WMPlayer.OCX
        $global:wmp.settings.volume = 100
        $global:wmp.URL = $path
        $global:wmp.controls.play()
        $global:sndKind = 'wmp'
        return
    } catch { }
    try {
        Add-Type -AssemblyName PresentationCore
        $global:mp = New-Object System.Windows.Media.MediaPlayer
        $global:mp.Open([Uri]$path)
        $global:mp.Play()
        $global:sndKind = 'wpf'
        return
    } catch { }
    $global:sndKind = 'none'
}

function Stop-Sound {
    try { if ($global:sndKind -eq 'wmp') { $global:wmp.controls.stop() } } catch { }
    try { if ($global:sndKind -eq 'wpf') { $global:mp.Stop() } } catch { }
}

function Test-SoundEnded {
    $t = $global:soundWatch.Elapsed.TotalSeconds
    if ($global:sndKind -eq 'wmp') {
        try {
            $st = $global:wmp.playState
            if ($st -eq 3) { $global:sawPlaying = $true }
            if ($global:sawPlaying -and ($st -eq 1 -or $st -eq 8)) { return $true }
            if (-not $global:sawPlaying -and $t -gt 10) { return $true }
            return $false
        } catch { return $true }
    }
    if ($global:sndKind -eq 'wpf') {
        try {
            if ($global:mp.NaturalDuration.HasTimeSpan) {
                return ($global:mp.Position -ge ($global:mp.NaturalDuration.TimeSpan - [TimeSpan]::FromMilliseconds(150)))
            }
            return ($t -gt 10)
        } catch { return $true }
    }
    return $true
}

# ---------- minigame: cat pictures ----------
function P($x, $y) { return (New-Object Drawing.PointF([single]$x, [single]$y)) }

function Draw-CatFace($g, $x, $y, $s, $fur) {
    $bF = New-Object Drawing.SolidBrush($fur)
    $bP = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 150, 175))
    $bK = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(40, 30, 40))
    $bW = New-Object Drawing.SolidBrush([Drawing.Color]::White)
    $pn = New-Object Drawing.Pen([Drawing.Color]::FromArgb(60, 40, 50), [single]($s * 0.02 + 1))
    $g.FillPolygon($bF, [Drawing.PointF[]]@((P ($x + $s * 0.05) ($y + $s * 0.45)), (P ($x + $s * 0.12) $y), (P ($x + $s * 0.42) ($y + $s * 0.18))))
    $g.FillPolygon($bF, [Drawing.PointF[]]@((P ($x + $s * 0.95) ($y + $s * 0.45)), (P ($x + $s * 0.88) $y), (P ($x + $s * 0.58) ($y + $s * 0.18))))
    $g.FillPolygon($bP, [Drawing.PointF[]]@((P ($x + $s * 0.12) ($y + $s * 0.40)), (P ($x + $s * 0.15) ($y + $s * 0.12)), (P ($x + $s * 0.34) ($y + $s * 0.22))))
    $g.FillPolygon($bP, [Drawing.PointF[]]@((P ($x + $s * 0.88) ($y + $s * 0.40)), (P ($x + $s * 0.85) ($y + $s * 0.12)), (P ($x + $s * 0.66) ($y + $s * 0.22))))
    $g.FillEllipse($bF, [single]$x, [single]($y + $s * 0.12), [single]$s, [single]($s * 0.85))
    $g.FillEllipse($bW, [single]($x + $s * 0.24), [single]($y + $s * 0.42), [single]($s * 0.17), [single]($s * 0.2))
    $g.FillEllipse($bW, [single]($x + $s * 0.59), [single]($y + $s * 0.42), [single]($s * 0.17), [single]($s * 0.2))
    $g.FillEllipse($bK, [single]($x + $s * 0.30), [single]($y + $s * 0.47), [single]($s * 0.07), [single]($s * 0.12))
    $g.FillEllipse($bK, [single]($x + $s * 0.65), [single]($y + $s * 0.47), [single]($s * 0.07), [single]($s * 0.12))
    $g.FillPolygon($bP, [Drawing.PointF[]]@((P ($x + $s * 0.45) ($y + $s * 0.66)), (P ($x + $s * 0.55) ($y + $s * 0.66)), (P ($x + $s * 0.5) ($y + $s * 0.72))))
    $g.DrawLine($pn, [single]($x + $s * 0.5), [single]($y + $s * 0.72), [single]($x + $s * 0.43), [single]($y + $s * 0.79))
    $g.DrawLine($pn, [single]($x + $s * 0.5), [single]($y + $s * 0.72), [single]($x + $s * 0.57), [single]($y + $s * 0.79))
    $g.DrawLine($pn, [single]($x + $s * 0.30), [single]($y + $s * 0.70), [single]($x + $s * 0.05), [single]($y + $s * 0.66))
    $g.DrawLine($pn, [single]($x + $s * 0.30), [single]($y + $s * 0.74), [single]($x + $s * 0.05), [single]($y + $s * 0.78))
    $g.DrawLine($pn, [single]($x + $s * 0.70), [single]($y + $s * 0.70), [single]($x + $s * 0.95), [single]($y + $s * 0.66))
    $g.DrawLine($pn, [single]($x + $s * 0.70), [single]($y + $s * 0.74), [single]($x + $s * 0.95), [single]($y + $s * 0.78))
    foreach ($o in @($bF, $bP, $bK, $bW, $pn)) { $o.Dispose() }
}

function Get-FurColor {
    $c = @(
        [Drawing.Color]::FromArgb(240, 160, 70), [Drawing.Color]::FromArgb(170, 170, 180),
        [Drawing.Color]::FromArgb(90, 90, 100), [Drawing.Color]::FromArgb(240, 225, 190),
        [Drawing.Color]::FromArgb(250, 250, 250))
    return $c[$global:rand.Next($c.Count)]
}

function New-CatImage($path) {
    $bgs = @(
        [Drawing.Color]::FromArgb(255, 214, 226), [Drawing.Color]::FromArgb(210, 235, 255),
        [Drawing.Color]::FromArgb(220, 255, 220), [Drawing.Color]::FromArgb(255, 245, 200),
        [Drawing.Color]::FromArgb(235, 220, 255))
    $bmp = New-Object Drawing.Bitmap(160, 160)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear($bgs[$global:rand.Next($bgs.Count)])
    Draw-CatFace $g 20 22 120 (Get-FurColor)
    $g.Dispose()
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Get-GameFolders {
    $list = New-Object System.Collections.ArrayList
    $desk = [Environment]::GetFolderPath('Desktop')
    $pics = [Environment]::GetFolderPath('MyPictures')
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $dl = $null
    try { $dl = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    $shots = $null
    if ($pics -and (Test-Path -LiteralPath $pics)) {
        $sd = Get-ChildItem -LiteralPath $pics -Directory -Filter 'Screenshots*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sd) { $shots = $sd.FullName }
    }
    $cands = @(
        @{ Name = 'Desktop'; Path = $desk }, @{ Name = 'Downloads'; Path = $dl },
        @{ Name = 'Screenshots'; Path = $shots }, @{ Name = 'Documents'; Path = $docs },
        @{ Name = 'Pictures'; Path = $pics })
    foreach ($c in $cands) {
        if ($c.Path -and (Test-Path -LiteralPath $c.Path -PathType Container)) { [void]$list.Add($c) }
    }
    return $list
}

function New-GameFiles {
    $folders = Get-GameFolders
    $global:gameFiles.Clear()
    if ($folders.Count -eq 0) { $global:gameTotal = 0; return }
    for ($i = 0; $i -lt $mgFiles; $i++) {
        $placed = $false
        for ($try = 0; $try -lt 8 -and -not $placed; $try++) {
            $fo = $folders[$global:rand.Next($folders.Count)]
            $name = $catNames[$global:rand.Next($catNames.Count)] + '_' + $global:rand.Next(100, 1000) + '.png'
            $path = Join-Path $fo.Path $name
            if (Test-Path -LiteralPath $path) { continue }
            try {
                New-CatImage $path
                if (Test-Path -LiteralPath $path) {
                    [void]$global:gameFiles.Add(@{ Path = $path; Place = $fo.Name; Done = $false })
                    Add-Content -LiteralPath $logFile -Value $path
                    $placed = $true
                }
            } catch { }
        }
    }
    $global:gameTotal = $global:gameFiles.Count
}

function Update-Hint {
    $rem = @($global:gameFiles | Where-Object { -not $_.Done })
    if ($rem.Count -eq 0) { $global:hint = '-'; return }
    $global:hint = (($rem | Group-Object { $_.Place } | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')
}

function Remove-GameFiles {
    foreach ($g in @($global:gameFiles)) {
        try { if (Test-Path -LiteralPath $g.Path) { Remove-Item -LiteralPath $g.Path -Force -ErrorAction SilentlyContinue } } catch { }
    }
    $global:gameFiles.Clear()
    try { if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue } } catch { }
}

# removes cat pics left behind by an earlier run that was interrupted
function Clear-Leftovers {
    try {
        if (Test-Path -LiteralPath $logFile) {
            Get-Content -LiteralPath $logFile | ForEach-Object {
                $p = $_
                if ($p -and (Test-Path -LiteralPath $p)) {
                    $leaf = Split-Path -Leaf $p
                    $len = (Get-Item -LiteralPath $p).Length
                    if ($leaf -match '^(Whiskers|Mittens|Luna|Oreo|Tiger|Shadow|Simba|Bella|Felix|Cleo|Pumpkin|Smokey)_\d{3}\.png$' -and $len -lt 200000) {
                        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# ---------- closing / cancelling ----------
function Close-All {
    foreach ($p in @($global:popups)) { try { $p.Close() } catch { } }
    foreach ($t in @($global:taunts)) { try { $t.Close() } catch { } }
    try { if ($global:box) { $global:box.Close() } } catch { }
    try { if ($global:lucky) { $global:lucky.Close() } } catch { }
    try { if ($global:glitch) { $global:glitch.Close() } } catch { }
    try { if ($global:bsod) { $global:bsod.Close() } } catch { }
    try { if ($global:jump) { $global:jump.Close() } } catch { }
    Remove-GameFiles
    try { $form.Close() } catch { }
}

function Cancel-All {
    $global:cancelled = $true
    $global:gameActive = $false
    try { $timer1.Stop(); $timer2.Stop(); $timer3.Stop(); $timer4.Stop(); $timerG.Stop(); $timerL.Stop() } catch { }
    Stop-Sound
    Close-All
}

function Finish-Run {
    if ($global:doShutdown -and -not $global:cancelled) {
        # Leave the fake blue screen up and shut down right now.
        Start-Process -FilePath 'shutdown.exe' -ArgumentList '/s','/t','0','/f' -WindowStyle Hidden
    } else {
        Close-All
    }
}

# ---------- popups ----------
function New-Popup {
    if ($global:fx) {
        $p = New-Object CorruptPopup -ArgumentList $popupText
        $pw = $p.Width; $ph = $p.Height
    } else {
        $pw = 340; $ph = 150
        $p = New-Object Windows.Forms.Form
        $p.Text = 'Error'
        $p.FormBorderStyle = 'FixedDialog'
        $p.MaximizeBox = $false
        $p.MinimizeBox = $false
        $p.ShowInTaskbar = $false
        $p.StartPosition = 'Manual'
        $p.Size = New-Object Drawing.Size($pw, $ph)
        $p.TopMost = $true
        $p.BackColor = [Drawing.Color]::White
        $p.KeyPreview = $true
        $l = New-Object Windows.Forms.Label
        $l.Dock = 'Fill'
        $l.TextAlign = 'MiddleCenter'
        $l.ForeColor = [Drawing.Color]::Red
        $l.Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
        $l.Text = $popupText
        $p.Controls.Add($l)
    }
    $x = $global:rand.Next(0, [Math]::Max(1, $bounds.Width - $pw))
    $y = $global:rand.Next(0, [Math]::Max(1, $bounds.Height - $ph))
    $p.Location = New-Object Drawing.Point($x, $y)
    $p.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })
    [void]$global:popups.Add($p)
    $p.Show()
    Raise-Glitch
}

# ---------- minigame: moving drop zone + taunt tabs ----------
function New-Taunt {
    $t = New-Object Windows.Forms.Form
    $t.FormBorderStyle = 'None'
    $t.StartPosition = 'Manual'
    $t.Size = New-Object Drawing.Size(270, 96)
    $t.TopMost = $true
    $t.ShowInTaskbar = $false
    $t.BackColor = [Drawing.Color]::FromArgb(255, 240, 246)
    $t.Location = New-Object Drawing.Point($global:rand.Next(0, [Math]::Max(1, $bounds.Width - 270)), $global:rand.Next(0, [Math]::Max(1, $bounds.Height - 96)))
    $t.Tag = @{ ox = $global:rand.Next(-60, 61); oy = $global:rand.Next(-40, 41); sp = (3 + $global:rand.NextDouble() * 4) }

    $bar = New-Object Windows.Forms.Label
    $bar.SetBounds(0, 0, 270, 24)
    $bar.BackColor = [Drawing.Color]::FromArgb(180, 40, 90)
    $bar.ForeColor = [Drawing.Color]::White
    $bar.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $bar.Text = '  Lil Kitty says:'
    $bar.TextAlign = 'MiddleLeft'

    $body = New-Object Windows.Forms.Label
    $body.SetBounds(0, 24, 270, 72)
    $body.Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)
    $body.ForeColor = [Drawing.Color]::FromArgb(130, 20, 70)
    $body.TextAlign = 'MiddleCenter'
    $body.Text = $global:tauntLines[$global:rand.Next($global:tauntLines.Count)]

    # a fake close button that does nothing useful
    $x = New-Object Windows.Forms.Label
    $x.SetBounds(240, 0, 30, 24)
    $x.BackColor = [Drawing.Color]::FromArgb(150, 20, 60)
    $x.ForeColor = [Drawing.Color]::White
    $x.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $x.Text = 'X'
    $x.TextAlign = 'MiddleCenter'
    $x.Tag = $body
    $x.Add_Click({ param($s, $e) $s.Tag.Text = 'Nice try.' })

    $t.Controls.Add($body)
    $t.Controls.Add($bar)
    $t.Controls.Add($x)
    $x.BringToFront()
    $t.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })
    [void]$global:taunts.Add($t)
    $t.Show()
}

function Set-TauntText($lines) {
    foreach ($t in @($global:taunts)) {
        try {
            foreach ($c in $t.Controls) {
                if ($c.Font.Size -gt 11) { $c.Text = $lines[$global:rand.Next($lines.Count)] }
            }
        } catch { }
    }
}

function Handle-Drop($paths) {
    if (-not $global:gameActive) { return }
    $hit = $false
    foreach ($p in $paths) {
        foreach ($g in $global:gameFiles) {
            if (-not $g.Done -and ($g.Path -ieq $p)) {
                $g.Done = $true
                $global:gameDone++
                $hit = $true
                try { Remove-Item -LiteralPath $g.Path -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
    if ($hit) {
        Update-Hint
        if ($global:gameDone -ge $global:gameTotal) { $global:winPending = $true }
        else { Set-TauntText $global:tauntReact }
    }
}

function Start-Minigame {
    try {
        # clear the screen so the Desktop and Explorer stay usable
        foreach ($p in @($global:popups)) { try { $p.Close() } catch { } }
        $global:popups.Clear()
        $form.TopMost = $false
        $form.Opacity = 0
        $form.Bounds = New-Object Drawing.Rectangle(-32000, -32000, 1, 1)
        [Windows.Forms.Cursor]::Show()
        Start-Glitch
        Set-Glitch 20

        New-GameFiles
        if ($global:gameTotal -le 0) { [Windows.Forms.Cursor]::Hide(); Start-Bsod; return }
        $global:gameDone = 0
        $global:winPending = $false
        Update-Hint

        $global:brPink = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 190, 215))
        $global:brDark = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(130, 30, 85))
        $global:brGray = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(110, 100, 110))
        $global:brRed  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(210, 30, 50))
        $global:brBar  = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(235, 225, 232))
        $global:penBorder = New-Object Drawing.Pen([Drawing.Color]::FromArgb(200, 80, 130), 2)
        $global:fBold  = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
        $global:fBig   = New-Object Drawing.Font('Segoe UI', 30, [Drawing.FontStyle]::Bold)
        $global:fSmall = New-Object Drawing.Font('Segoe UI', 9)
        $global:boxFur = Get-FurColor

        $bx = New-Object Windows.Forms.Form
        $global:box = $bx
        $bx.FormBorderStyle = 'None'
        $bx.StartPosition = 'Manual'
        $bx.Size = New-Object Drawing.Size(380, 190)
        $bx.TopMost = $true
        $bx.ShowInTaskbar = $false
        $bx.BackColor = [Drawing.Color]::White
        $bx.AllowDrop = $true
        $bx.KeyPreview = $true
        try { $bx.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($bx, $true, $null) } catch { }
        $bx.Location = New-Object Drawing.Point($global:rand.Next(0, [Math]::Max(1, $bounds.Width - 380)), $global:rand.Next(0, [Math]::Max(1, $bounds.Height - 190)))
        $sgn = @(-1, 1)
        $global:vx = $mgSpeed * $sgn[$global:rand.Next(2)]
        $global:vy = $mgSpeed * 0.7 * $sgn[$global:rand.Next(2)]

        $bx.Add_DragEnter({ param($s, $e)
            if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy }
            else { $e.Effect = [Windows.Forms.DragDropEffects]::None }
        })
        $bx.Add_DragOver({ param($s, $e)
            if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy }
        })
        $bx.Add_DragDrop({ param($s, $e)
            Handle-Drop ($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
        })
        $bx.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })
        $bx.Add_Paint({ param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = 'AntiAlias'
            $g.TextRenderingHint = 'AntiAliasGridFit'
            $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
            $g.Clear([Drawing.Color]::White)
            $g.FillRectangle($global:brPink, 0, 0, $w, 34)
            $g.DrawString('Drag the cat pics here!', $global:fBold, $global:brDark, 12, 6)
            Draw-CatFace $g 14 44 58 $global:boxFur
            $g.DrawString("$($global:gameDone) / $($global:gameTotal)", $global:fBig, $global:brDark, 84, 40)
            $g.DrawString('cat pics saved', $global:fSmall, $global:brGray, 90, 92)
            $remain = [Math]::Max(0, $mgSeconds - $global:gameWatch.Elapsed.TotalSeconds)
            $brT = $global:brDark
            if ($remain -lt 10) { $brT = $global:brRed }
            $g.DrawString(("Time left: {0:0}s" -f [Math]::Ceiling($remain)), $global:fBold, $brT, 226, 58)
            $frac = $remain / [Math]::Max(1, $mgSeconds)
            $g.FillRectangle($global:brBar, 14, 114, ($w - 28), 12)
            $g.FillRectangle($brT, 14, 114, [int](($w - 28) * $frac), 12)
            $rc = New-Object Drawing.RectangleF(14, 134, ($w - 28), 52)
            $g.DrawString("Hiding in: $($global:hint)", $global:fSmall, $global:brGray, $rc)
            $g.DrawRectangle($global:penBorder, 1, 1, ($w - 3), ($h - 3))
        })
        $bx.Show()

        if ($tauntsOn -and $tauntMax -gt 0) {
            $n = $global:rand.Next($tauntMin, $tauntMax + 1)
            for ($i = 0; $i -lt $n; $i++) { New-Taunt }
        }
        Raise-Glitch

        $global:gameActive = $true
        $global:tickN = 0
        $global:gameWatch.Restart()
        $timerG.Start()
    } catch {
        $global:gameActive = $false
        Remove-GameFiles
        try { [Windows.Forms.Cursor]::Hide() } catch { }
        Start-Bsod
    }
}

function Show-Lucky {
    $l = New-Object Windows.Forms.Form
    $global:lucky = $l
    $l.FormBorderStyle = 'None'
    $l.StartPosition = 'Manual'
    $l.Size = New-Object Drawing.Size(420, 130)
    $l.Location = New-Object Drawing.Point([int](($bounds.Width - 420) / 2), [int](($bounds.Height - 130) / 2))
    $l.TopMost = $true
    $l.ShowInTaskbar = $false
    $l.BackColor = [Drawing.Color]::FromArgb(255, 190, 215)
    $lb = New-Object Windows.Forms.Label
    $lb.Dock = 'Fill'
    $lb.TextAlign = 'MiddleCenter'
    $lb.Font = New-Object Drawing.Font('Segoe UI', 30, [Drawing.FontStyle]::Bold)
    $lb.ForeColor = [Drawing.Color]::FromArgb(130, 30, 85)
    $lb.Text = "You're Lucky."
    $l.Controls.Add($lb)
    $l.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })
    $l.Show()
    $timerL.Start()
}

function Game-Win {
    if (-not $global:gameActive) { return }
    $global:gameActive = $false
    $timerG.Stop()
    foreach ($t in @($global:taunts)) { try { $t.Close() } catch { } }
    $global:taunts.Clear()
    try { $global:box.Close() } catch { }
    Remove-GameFiles
    Set-Glitch 0
    Show-Lucky
}

function Game-Lose {
    if (-not $global:gameActive) { return }
    $global:gameActive = $false
    $timerG.Stop()
    foreach ($t in @($global:taunts)) { try { $t.Close() } catch { } }
    $global:taunts.Clear()
    try { $global:box.Close() } catch { }
    Remove-GameFiles
    [Windows.Forms.Cursor]::Hide()
    Start-Bsod
}

function Next-Stage {
    if ($mgEnabled) { Start-Minigame } else { Start-Bsod }
}

# ---------- fake blue screen ----------
function Start-Bsod {
    $b = New-Object Windows.Forms.Form
    $global:bsod = $b
    $b.FormBorderStyle = 'None'
    $b.StartPosition = 'Manual'
    $b.Bounds = $bounds
    $b.TopMost = $true
    $b.ShowInTaskbar = $false
    $b.BackColor = [Drawing.Color]::FromArgb(0, 120, 215)
    $b.KeyPreview = $true
    $b.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })

    $W = $bounds.Width; $H = $bounds.Height
    $left = [int]($W * 0.12)

    $l1 = New-Object Windows.Forms.Label
    $l1.AutoSize = $true; $l1.ForeColor = [Drawing.Color]::White
    $l1.Font = New-Object Drawing.Font('Segoe UI', 96)
    $l1.Text = ':('
    $l1.Location = New-Object Drawing.Point($left, [int]($H * 0.10))

    $l2 = New-Object Windows.Forms.Label
    $l2.AutoSize = $true; $l2.ForeColor = [Drawing.Color]::White
    $l2.Font = New-Object Drawing.Font('Segoe UI', 24)
    $l2.MaximumSize = New-Object Drawing.Size([int]($W * 0.7), 0)
    $l2.Text = "Your PC ran into a problem and needs to restart. We're just collecting some error info, and then we'll restart for you."
    $l2.Location = New-Object Drawing.Point($left, [int]($H * 0.38))
    $global:l2 = $l2
    $global:l2Orig = $l2.Text

    $l3 = New-Object Windows.Forms.Label
    $l3.AutoSize = $true; $l3.ForeColor = [Drawing.Color]::White
    $l3.Font = New-Object Drawing.Font('Segoe UI', 24)
    $l3.Text = '0% complete'
    $l3.Location = New-Object Drawing.Point($left, [int]($H * 0.58))
    $global:pctLabel = $l3

    $textLeft = $left
    $b.Controls.AddRange(@($l1, $l2, $l3))

    if ($global:fx) {
        try {
            $qr = New-Object FakeQr
            $qr.Location = New-Object Drawing.Point($left, [int]($H * 0.70))
            $b.Controls.Add($qr)
            $textLeft = $left + 140
        } catch { }
    }

    $l4 = New-Object Windows.Forms.Label
    $l4.AutoSize = $true; $l4.ForeColor = [Drawing.Color]::White
    $l4.Font = New-Object Drawing.Font('Segoe UI', 12)
    $l4.Text = "For more information about this issue and possible fixes, visit https://www.windows.com/stopcode`n`nIf you call a support person, give them this info:`nStop code: CRITICAL_PROCESS_DIED"
    $l4.Location = New-Object Drawing.Point($textLeft, [int]($H * 0.70))
    $b.Controls.Add($l4)

    $b.Show()
    $b.Activate()

    # popups are no longer needed; the blue screen covers everything
    foreach ($p in @($global:popups)) { try { $p.Close() } catch { } }

    Start-Glitch
    Set-Glitch 55
    Raise-Glitch

    Start-Sound $soundPath
    $global:bsodWatch = [Diagnostics.Stopwatch]::StartNew()
    $timer3.Start()
}

# ---------- jumpscare (only when shutdown is turned off) ----------
function Start-Jumpscare {
    Stop-Sound
    Set-Glitch 0
    $j = New-Object Windows.Forms.Form
    $global:jump = $j
    $j.FormBorderStyle = 'None'
    $j.StartPosition = 'Manual'
    $j.Bounds = $bounds
    $j.TopMost = $true
    $j.ShowInTaskbar = $false
    $j.BackColor = [Drawing.Color]::Black
    $j.KeyPreview = $true
    $j.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })
    if ($jsImgPath -and (Test-Path -LiteralPath $jsImgPath)) {
        try {
            $jb = [IO.File]::ReadAllBytes($jsImgPath)
            $jms = New-Object IO.MemoryStream (,$jb)
            $jpb = New-Object Windows.Forms.PictureBox
            $jpb.Dock = 'Fill'
            $jpb.SizeMode = 'Zoom'
            $jpb.BackColor = [Drawing.Color]::Black
            $jpb.Image = [Drawing.Image]::FromStream($jms)
            $j.Controls.Add($jpb)
        } catch { }
    }
    $j.Show()
    $j.Activate()
    Start-Sound $jsSoundPath
    $timer4.Start()
}

# ---------- main image form ----------
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.Bounds = $bounds
$form.TopMost = $true
$form.BackColor = [Drawing.Color]::Black
$form.KeyPreview = $true

if (Test-Path -LiteralPath $imgPath) {
    try {
        $bytes = [IO.File]::ReadAllBytes($imgPath)
        $ms = New-Object IO.MemoryStream (,$bytes)
        $pb = New-Object Windows.Forms.PictureBox
        $pb.Dock = 'Fill'
        $pb.SizeMode = 'Zoom'
        $pb.BackColor = [Drawing.Color]::Black
        $pb.Image = [Drawing.Image]::FromStream($ms)
        $form.Controls.Add($pb)
        $global:imageOk = $true
    } catch { }
}

if (-not $global:imageOk) {
    # Image missing or unreadable: show a message and do NOT run the prank or shut down.
    $lbl = New-Object Windows.Forms.Label
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.ForeColor = [Drawing.Color]::White
    $lbl.Font = New-Object Drawing.Font('Segoe UI', 24)
    $lbl.Text = "Could not load image:`n$imgPath`n`nCheck the Image setting in the Lil Kitty menu (hold Shift while starting)"
    $form.Controls.Add($lbl)
    $global:doShutdown = $false
    $wait = 6
}

# timer1: how long the image shows
$timer1 = New-Object Windows.Forms.Timer
$timer1.Interval = [Math]::Max(1, [int]($wait * 1000))
$timer1.Add_Tick({
    $timer1.Stop()
    if (-not $global:imageOk) { $form.Close(); return }
    Start-Glitch
    if ($popupCount -le 0) { Next-Stage; return }
    $timer2.Interval = [Math]::Max(10, [int]($popupSeconds * 1000 / $popupCount))
    $timer2.Start()
})

# timer2: spawns the popups one by one, glitching harder as they pile up
$timer2 = New-Object Windows.Forms.Timer
$timer2.Add_Tick({
    New-Popup
    $global:popupsMade++
    Set-Glitch (12 + 43 * $global:popupsMade / [Math]::Max(1, $popupCount))
    if ($global:popupsMade -ge $popupCount) { $timer2.Stop(); Next-Stage }
})

# timerG: the minigame loop (moves the drop zone, chases the cursor, checks the clock)
$timerG = New-Object Windows.Forms.Timer
$timerG.Interval = 30
$timerG.Add_Tick({
    if (-not $global:gameActive) { return }
    if ($global:winPending) { Game-Win; return }
    $global:tickN++
    $now = $global:gameWatch.Elapsed.TotalSeconds
    if ($now -ge $mgSeconds) { Game-Lose; return }

    # moving drop zone: bounces around the screen
    $b = $global:box
    if ($b) {
        if ($global:rand.NextDouble() -lt 0.012) {
            $sg = @(-1, 1)
            $global:vx = $mgSpeed * (0.6 + 0.8 * $global:rand.NextDouble()) * $sg[$global:rand.Next(2)]
            $global:vy = $mgSpeed * (0.6 + 0.8 * $global:rand.NextDouble()) * $sg[$global:rand.Next(2)]
        }
        $nx = $b.Left + $global:vx
        $ny = $b.Top + $global:vy
        if ($nx -lt 0) { $nx = 0; $global:vx = [Math]::Abs($global:vx) }
        elseif ($nx + $b.Width -gt $bounds.Width) { $nx = $bounds.Width - $b.Width; $global:vx = -[Math]::Abs($global:vx) }
        if ($ny -lt 0) { $ny = 0; $global:vy = [Math]::Abs($global:vy) }
        elseif ($ny + $b.Height -gt $bounds.Height) { $ny = $bounds.Height - $b.Height; $global:vy = -[Math]::Abs($global:vy) }
        $b.Location = New-Object Drawing.Point([int]$nx, [int]$ny)
        $b.Invalidate()
    }

    # taunt tabs: drift toward the cursor to get in the way (they can't be dragged by the user)
    $cp = [Windows.Forms.Cursor]::Position
    foreach ($t in @($global:taunts)) {
        $st = $t.Tag
        $tx = $cp.X + $st.ox - $t.Width / 2
        $ty = $cp.Y + $st.oy - $t.Height / 2
        $dx = $tx - $t.Left
        $dy = $ty - $t.Top
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -gt 4) {
            $step = [Math]::Min($d, $st.sp)
            $t.Location = New-Object Drawing.Point([int]($t.Left + $dx / $d * $step), [int]($t.Top + $dy / $d * $step))
        }
    }

    # new insults every couple of seconds
    if ($global:tickN % 80 -eq 0) { Set-TauntText $global:tauntLines }
    if ($global:tickN % 33 -eq 0) { Raise-Glitch }
    Set-Glitch (20 + 40 * $now / [Math]::Max(1, $mgSeconds))
})

# timerL: the "You're Lucky." tab disappears after 2 seconds
$timerL = New-Object Windows.Forms.Timer
$timerL.Interval = 2000
$timerL.Add_Tick({ $timerL.Stop(); Close-All })

# timer3: runs during the fake blue screen; at 100% it shuts down (or runs the jumpscare)
$timer3 = New-Object Windows.Forms.Timer
$timer3.Interval = 120
$timer3.Add_Tick({
    $el = $global:bsodWatch.Elapsed.TotalSeconds
    if ($bsodSeconds -gt 0) {
        $pct = [int][Math]::Min(100, [Math]::Floor($el / $bsodSeconds * 100))
    } else { $pct = 100 }
    try { $global:pctLabel.Text = "$pct% complete" } catch { }

    if ($global:fx) {
        Set-Glitch (55 + 45 * $pct / 100)
        if ($pct -lt 100 -and $global:rand.NextDouble() -lt 0.08) {
            $global:bsod.BackColor = [Drawing.Color]::Black
            $global:l2.Text = [Corrupt]::Scramble($global:l2Orig, 0.2)
        } else {
            $global:bsod.BackColor = [Drawing.Color]::FromArgb(0, 120, 215)
            $global:l2.Text = $global:l2Orig
        }
    }

    if ($pct -ge 100) {
        $timer3.Stop()
        if ($global:doShutdown) { Finish-Run } else { Start-Jumpscare }
    }
})

# timer4: runs during the jumpscare; closes everything when its sound has ended
$timer4 = New-Object Windows.Forms.Timer
$timer4.Interval = 200
$timer4.Add_Tick({
    if ($global:soundWatch.Elapsed.TotalSeconds -gt 1 -and (Test-SoundEnded)) {
        $timer4.Stop()
        Close-All
    }
})

# timer5: Esc works from anywhere (even while dragging files in Explorer)
$timer5 = New-Object Windows.Forms.Timer
$timer5.Interval = 80
$timer5.Add_Tick({
    if ($allowEsc -and $global:keysOk -and -not $global:cancelled) {
        if ([LK.Keys]::GetAsyncKeyState(0x1B) -lt 0) { Cancel-All }
    }
})

$form.Add_Shown({
    $form.Activate()
    $form.Refresh()
    Clear-Leftovers
    Init-Fx
    $timer5.Start()
    $timer1.Start()
})
$form.Add_KeyDown({ param($s, $e) if ($allowEsc -and $e.KeyCode -eq 'Escape') { Cancel-All } })

[Windows.Forms.Cursor]::Hide()
[void]$form.ShowDialog()
[Windows.Forms.Cursor]::Show()
Remove-GameFiles
