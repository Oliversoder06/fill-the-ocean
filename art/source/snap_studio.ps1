param([string]$Out)
# Captures only the gameplay Studio window (also while it's behind other windows).
if (-not ("Snap" -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Runtime.InteropServices;
public static class Snap {
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static Bitmap Window(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    var bmp = new Bitmap(r.R - r.L, r.B - r.T);
    using (var g = Graphics.FromImage(bmp)) { var dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); }
    return bmp;
  }
}
"@
}
$studio = Get-Process | Where-Object { $_.MainWindowTitle -eq "Gameplay - Roblox Studio" } | Select-Object -First 1
if (-not $studio) { throw "The gameplay Studio window isn't open" }
$bmp = [Snap]::Window($studio.MainWindowHandle)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
