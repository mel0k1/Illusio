using System;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32;

namespace SS14.Loader;

internal static class Registries
{
    private static readonly string[] TracedPaths =
    {
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
    };

    public static void Apply()
    {
        if (Envsey.Get("ILLUSIO_STEALTH_REGISTRIES") != "1")
            return;

        if (!OperatingSystem.IsWindows())
            return;

        var purged = 0;
        foreach (var path in TracedPaths)
        {
            purged += PurgeTree(Registry.CurrentUser, path, 2);
        }

        Console.WriteLine($"[ILLUSIO-STEALTH] реестр: зачищено записей {purged}");
        ModLog.Record($"registries: зачищено записей {purged}");
    }

    [SupportedOSPlatform("windows")]
    private static int PurgeTree(RegistryKey root, string path, int depth)
    {
        var removed = 0;
        try
        {
            using var key = root.OpenSubKey(path, writable: true);
            if (key == null)
                return 0;

            foreach (var name in key.GetValueNames())
            {
                if (!MentionsLauncher(name) && !MentionsLauncher(key.GetValue(name)))
                    continue;

                key.DeleteValue(name, throwOnMissingValue: false);
                removed++;
            }

            if (depth <= 0)
                return removed;

            foreach (var child in key.GetSubKeyNames())
            {
                removed += PurgeTree(root, $"{path}\\{child}", depth - 1);
            }

            return removed;
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-STEALTH] реестр {path}: {e.Message}");
            return removed;
        }
    }

    private static bool MentionsLauncher(object? value)
    {
        if (value == null)
            return false;

        var text = value switch
        {
            byte[] bytes => Encoding.Unicode.GetString(bytes)
                + "\0"
                + Encoding.ASCII.GetString(bytes),
            var other => other.ToString() ?? "",
        };
        return text.Contains("illusio", StringComparison.OrdinalIgnoreCase);
    }
}
