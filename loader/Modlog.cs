using System;
using System.Collections.Generic;
using System.IO;

namespace SS14.Loader;

internal static class ModLog
{
    private static readonly object Gate = new();
    private static readonly List<string> Lines = new();

    public static void Record(string line)
    {
        lock (Gate)
        {
            Lines.Add($"{DateTime.UtcNow:O} {line}");
        }
    }

    public static void Flush()
    {
        List<string> copy;
        lock (Gate)
        {
            if (Lines.Count == 0)
                return;
            copy = new List<string>(Lines);
        }

        if (Envsey.Get("ILLUSIO_MOD_LOGS") != "1")
            return;

        var dir = (Envsey.Get("ILLUSIO_LOGS_DIR") ?? "").Trim();
        if (dir.Length == 0)
            return;

        try
        {
            Directory.CreateDirectory(dir);
            File.AppendAllLines(Path.Combine(dir, "mods.log"), copy);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-MODLOG] не удалось записать журнал: {e.Message}");
        }
    }
}
