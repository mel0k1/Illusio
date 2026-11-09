using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using HarmonyLib;

namespace SS14.Loader;

internal static class Envsey
{
    private static Dictionary<string, string?> _snapshot = new();

    public static void Capture()
    {
        _snapshot = Environment
            .GetEnvironmentVariables(EnvironmentVariableTarget.Process)
            .Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(
                entry => (string)entry.Key,
                entry => entry.Value as string,
                StringComparer.Ordinal);
    }

    public static string? Get(string name)
    {
        return _snapshot.TryGetValue(name, out var value) ? value : null;
    }

    public static void Scrub()
    {
        foreach (var key in Environment
                     .GetEnvironmentVariables(EnvironmentVariableTarget.Process)
                     .Cast<System.Collections.DictionaryEntry>()
                     .Select(entry => (string)entry.Key)
                     .Where(IsSensitive)
                     .ToList())
        {
            Environment.SetEnvironmentVariable(key, null);
        }
    }

    private static bool IsSensitive(string key)
    {
        return key.StartsWith("ILLUSIO_", StringComparison.Ordinal)
            || key.StartsWith("SS14_LOADER_", StringComparison.Ordinal)
            || key.StartsWith("MARSEY_", StringComparison.Ordinal)
            || key.Equals("SS14_DISABLE_SIGNING", StringComparison.Ordinal);
    }
}

internal enum HideLevel
{
    Disabled = 0,
    Duplicit = 1,
    Normal = 2,
    Explicit = 3,
    Unconditional = 4,
}

internal static class Hidesey
{
    internal static readonly string[] CoreNames =
    {
        "illusio-loader",
        "0Harmony",
        "NSec",
        "HarmonySharedState",
        "Anonymously Hosted DynamicMethods Assembly",
    };

    internal static readonly string[] CorePrefixes = { "Mono.Cecil", "MonoMod", "illusio-scan-", "Marsey", "Illusio" };

    private static HideLevel _level = HideLevel.Normal;
    private static readonly HashSet<string> ModNames = new(StringComparer.OrdinalIgnoreCase);
    private static readonly HashSet<MethodInfo> PatchMethods = new();

    internal static HideLevel Level => _level;

    internal static bool Active => _level >= HideLevel.Duplicit;

    internal static void Apply(Harmony harmony)
    {
        var raw = Envsey.Get("ILLUSIO_HIDE_LEVEL") ?? "2";
        if (!int.TryParse(raw.Trim(), out var parsed) || parsed < 0 || parsed > 4)
            parsed = 2;
        _level = (HideLevel)parsed;

        if (_level < HideLevel.Duplicit)
        {
            Console.WriteLine("[ILLUSIO-STEALTH] скрытие выключено (уровень 0)");
            return;
        }

        foreach (var name in CoreNames)
            ModNames.Add(name);

        PatchAppDomainAssemblies(harmony);
        PatchAssemblyTypes(harmony);
        PatchReferencedAssemblies(harmony);
        if (_level >= HideLevel.Explicit)
        {
            PatchAssemblyLocation(harmony);
            PatchLoadContextAssemblies(harmony);
        }
        if (_level >= HideLevel.Unconditional)
        {
            PatchStackTrace(harmony, AccessTools.PropertyGetter(typeof(Environment), "StackTrace"));
            PatchStackTrace(harmony, AccessTools.PropertyGetter(typeof(Exception), "StackTrace"));
        }

        foreach (var name in new[]
                 {
                     nameof(AssembliesPostfix),
                     nameof(TypesPostfix),
                     nameof(ReferencesPostfix),
                     nameof(LocationPostfix),
                     nameof(EnumerablePostfix),
                     nameof(StackTracePostfix),
                 })
        {
            if (typeof(Hidesey).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Static)
                is { } method)
                PatchMethods.Add(method);
        }

        Console.WriteLine($"[ILLUSIO-STEALTH] скрытие активно, уровень {(int)_level}");
    }

    internal static void TrackMod(Assembly assembly)
    {
        if (_level < HideLevel.Normal)
            return;

        var name = assembly.GetName().Name;
        if (!string.IsNullOrEmpty(name))
            ModNames.Add(name);
    }

    internal static bool SuppressAssemblyLoadDuring(Action action)
    {
        if (_level < HideLevel.Normal)
        {
            action();
            return true;
        }

        var field = AccessTools.Field(typeof(AppDomain), "_AssemblyLoad");
        if (field?.GetValue(AppDomain.CurrentDomain) is not EventHandler handler)
        {
            action();
            return true;
        }

        field.SetValue(AppDomain.CurrentDomain, null);
        try
        {
            action();
            return true;
        }
        finally
        {
            field.SetValue(AppDomain.CurrentDomain, handler);
        }
    }

    internal static bool IsHidden(Assembly? assembly)
    {
        if (assembly == null)
            return false;

        return IsHiddenName(assembly.GetName().Name ?? string.Empty);
    }

    internal static bool IsHiddenName(string? name)
    {
        if (string.IsNullOrEmpty(name))
            return false;

        if (ModNames.Contains(name))
            return true;

        foreach (var prefix in CorePrefixes)
        {
            if (name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    private static bool FromHidden()
    {
        var frames = new StackTrace(false).GetFrames() ?? Array.Empty<StackFrame>();
        foreach (var frame in frames)
        {
            var method = frame.GetMethod();
            if (method == null)
                continue;

            if (PatchMethods.Contains(method))
                continue;

            var owner = method.DeclaringType?.Assembly;
            if (owner == null)
                continue;

            if (owner.GetName().Name == "0Harmony")
                continue;

            if (IsHidden(owner))
                return true;

            return false;
        }

        return false;
    }

    private static void PatchAppDomainAssemblies(Harmony harmony)
    {
        var target = AccessTools.Method(typeof(AppDomain), nameof(AppDomain.GetAssemblies));
        if (target == null)
            return;

        harmony.Patch(
            target,
            postfix: new HarmonyMethod(typeof(Hidesey), nameof(AssembliesPostfix)));
    }

    private static void PatchAssemblyTypes(Harmony harmony)
    {
        var targets = new List<MethodInfo?>();
        try
        {
            targets.Add(AccessTools.Method(typeof(Assembly), nameof(Assembly.GetTypes)));
        }
        catch
        {
        }

        var runtime = AccessTools.TypeByName("System.Reflection.RuntimeAssembly");
        if (runtime != null)
        {
            try
            {
                targets.Add(AccessTools.Method(runtime, "GetTypes"));
            }
            catch
            {
            }
        }

        foreach (var target in targets)
        {
            if (target == null)
                continue;

            try
            {
                harmony.Patch(
                    target,
                    postfix: new HarmonyMethod(typeof(Hidesey), nameof(TypesPostfix)));
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-STEALTH] GetTypes: {e.Message}");
            }
        }
    }

    private static void PatchReferencedAssemblies(Harmony harmony)
    {
        var targets = new List<MethodInfo?>();
        try
        {
            targets.Add(AccessTools.Method(typeof(Assembly), nameof(Assembly.GetReferencedAssemblies)));
        }
        catch
        {
        }

        var runtime = AccessTools.TypeByName("System.Reflection.RuntimeAssembly");
        if (runtime != null)
        {
            try
            {
                targets.Add(AccessTools.Method(runtime, "GetReferencedAssemblies"));
            }
            catch
            {
            }
        }

        foreach (var target in targets)
        {
            if (target == null)
                continue;

            try
            {
                harmony.Patch(
                    target,
                    postfix: new HarmonyMethod(typeof(Hidesey), nameof(ReferencesPostfix)));
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-STEALTH] GetReferencedAssemblies: {e.Message}");
            }
        }
    }

    private static void PatchAssemblyLocation(Harmony harmony)
    {
        var targets = new List<MethodInfo?>();
        try
        {
            targets.Add(AccessTools.PropertyGetter(typeof(Assembly), nameof(Assembly.Location)));
        }
        catch
        {
        }

        var runtime = AccessTools.TypeByName("System.Reflection.RuntimeAssembly");
        if (runtime != null)
        {
            try
            {
                targets.Add(AccessTools.PropertyGetter(runtime, "Location"));
            }
            catch
            {
            }
        }

        foreach (var target in targets)
        {
            if (target == null)
                continue;

            try
            {
                harmony.Patch(
                    target,
                    postfix: new HarmonyMethod(typeof(Hidesey), nameof(LocationPostfix)));
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-STEALTH] Location: {e.Message}");
            }
        }
    }

    private static void PatchLoadContextAssemblies(Harmony harmony)
    {
        var getter = AccessTools.PropertyGetter(typeof(AssemblyLoadContext), "Assemblies");
        if (getter == null)
            return;

        try
        {
            harmony.Patch(
                getter,
                postfix: new HarmonyMethod(typeof(Hidesey), nameof(EnumerablePostfix)));
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-STEALTH] ALC.Assemblies: {e.Message}");
        }
    }

    private static void PatchStackTrace(Harmony harmony, MethodInfo? getter)
    {
        if (getter == null)
            return;

        try
        {
            harmony.Patch(
                getter,
                postfix: new HarmonyMethod(typeof(Hidesey), nameof(StackTracePostfix)));
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-STEALTH] StackTrace: {e.Message}");
        }
    }

    private static void AssembliesPostfix(ref Assembly[] __result)
    {
        if (!Active || __result.Length == 0)
            return;

        var hidden = __result.Count(IsHidden);
        if (hidden == 0)
            return;

        if (FromHidden())
            return;

        __result = __result.Where(value => !IsHidden(value)).ToArray();
    }

    private static void TypesPostfix(Assembly __instance, ref Type[] __result)
    {
        if (!Active || __result.Length == 0)
            return;

        if (!IsHidden(__instance))
            return;

        if (FromHidden())
            return;

        __result = Array.Empty<Type>();
    }

    private static void ReferencesPostfix(ref AssemblyName[] __result)
    {
        if (!Active || __result.Length == 0)
            return;

        var hidden = __result.Count(value => IsHiddenName(value.Name));
        if (hidden == 0)
            return;

        if (FromHidden())
            return;

        __result = __result.Where(value => !IsHiddenName(value.Name)).ToArray();
    }

    private static void LocationPostfix(Assembly __instance, ref string __result)
    {
        if (!Active || __result.Length == 0)
            return;

        if (!IsHidden(__instance))
            return;

        if (FromHidden())
            return;

        __result = string.Empty;
    }

    private static void EnumerablePostfix(ref IEnumerable<Assembly>? __result)
    {
        if (!Active || __result == null)
            return;

        if (!__result.Any(IsHidden))
            return;

        if (FromHidden())
            return;

        __result = __result.Where(value => !IsHidden(value)).ToList();
    }

    private static void StackTracePostfix(ref string __result)
    {
        if (!Active || string.IsNullOrEmpty(__result))
            return;

        foreach (var name in ModNames)
        {
            if (__result.IndexOf(name, StringComparison.OrdinalIgnoreCase) < 0)
                continue;

            var lines = __result.Split('\n');
            __result = string.Join(
                '\n',
                lines.Where(line => line.IndexOf(name, StringComparison.OrdinalIgnoreCase) < 0));
        }
    }
}
