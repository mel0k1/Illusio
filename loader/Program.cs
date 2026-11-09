using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading;
using HarmonyLib;
using NSec.Cryptography;
using Robust.LoaderApi;

namespace SS14.Loader;

internal sealed record ModInfo(
    string Path,
    Assembly Assembly,
    Type? Marker,
    string Name,
    string Description,
    bool Preload);

internal static class Subverters
{
    private const string EnvName = "SS14_LOADER_SUBVERTERS";

    private static List<string> _pending = new();
    private static MethodInfo? _initMod;

    public static void Apply(Harmony harmony)
    {
        _pending = ParsePaths(Envsey.Get(EnvName));
        if (_pending.Count == 0)
            return;

        var modLoader = AccessTools.TypeByName("Robust.Shared.ContentPack.ModLoader");
        var target = modLoader == null
            ? null
            : FindMethod(modLoader, "TryLoadModules") ?? FindMethod(modLoader, "LoadModules");
        if (target == null)
        {
            Console.WriteLine("[ILLUSIO-SUBVERT] Robust ModLoader не найден, сайдлоад отключён");
            _pending.Clear();
            return;
        }

        harmony.Patch(
            target,
            postfix: new HarmonyMethod(typeof(Subverters), nameof(TryLoadModulesPostfix)));
        Console.WriteLine($"[ILLUSIO-SUBVERT] сайдлоад {_pending.Count} мод(ей) через ModLoader");
    }

    private static void TryLoadModulesPostfix(object __instance)
    {
        if (_pending.Count == 0)
            return;

        var paths = _pending;
        _pending = new List<string>();

        if (_initMod == null)
        {
            var baseLoader = AccessTools.TypeByName("Robust.Shared.ContentPack.BaseModLoader");
            _initMod = baseLoader == null ? null : AccessTools.Method(baseLoader, "InitMod");
        }

        if (_initMod == null)
        {
            Console.WriteLine("[ILLUSIO-SUBVERT] BaseModLoader.InitMod не найден");
            return;
        }

        foreach (var path in paths)
        {
            try
            {
                Assembly? assembly = null;
                Hidesey.SuppressAssemblyLoadDuring(() => assembly = Assembly.LoadFrom(path));
                if (assembly == null)
                    continue;

                Hidesey.TrackMod(assembly);
                _initMod.Invoke(__instance, new object?[] { assembly });
                Console.WriteLine($"[ILLUSIO-SUBVERT] загружен {Path.GetFileName(path)}");
            }
            catch (Exception e)
            {
                Console.WriteLine(
                    $"[ILLUSIO-SUBVERT] {Path.GetFileName(path)}: {e.InnerException?.Message ?? e.Message}");
            }
        }
    }

    private static List<string> ParsePaths(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return new List<string>();

        return raw
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(File.Exists)
            .ToList();
    }

    private static MethodInfo? FindMethod(Type type, string name)
    {
        return AccessTools.GetDeclaredMethods(type)
            .FirstOrDefault(method => method.Name == name);
    }
}

internal static class ResourcePacks
{
    private const string PacksEnv = "SS14_LOADER_RES_PACKS";
    private const string DumpEnv = "ILLUSIO_DUMP";
    private const string DumpDirEnv = "SS14_LOADER_DUMP_DIR";
    private const string MetaFileName = "meta.json";

    private static readonly List<string> Replacements = new();

    private static Type? _resPath;
    private static ConstructorInfo? _resPathCtor;
    private static FieldInfo? _canonPath;
    private static MethodInfo? _findFiles;
    private static MethodInfo? _fileRead;
    private static string? _dumpDir;
    private static int _dumpStarted;

    public static void Apply(Harmony harmony)
    {
        var dumpFlag = Envsey.Get(DumpEnv) == "1";
        _dumpDir = Envsey.Get(DumpDirEnv);
        if (dumpFlag && !string.IsNullOrWhiteSpace(_dumpDir))
        {
            StartDumper(harmony);
            return;
        }

        foreach (var dir in ParseDirs(Envsey.Get(PacksEnv)))
        {
            try
            {
                CollectReplacements(dir);
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-RESPACK] {dir}: {e.Message}");
            }
        }

        if (Replacements.Count == 0)
            return;

        if (!PrepareTargets(harmony, nameof(FindFilesSwapPostfix)))
            return;

        Console.WriteLine($"[ILLUSIO-RESPACK] {Replacements.Count} подмен путей");
    }

    private static void CollectReplacements(string directory)
    {
        var absolute = Path.GetFullPath(directory);
        foreach (var file in Directory.GetFiles(absolute, "*", SearchOption.AllDirectories))
        {
            if (file.EndsWith(MetaFileName, StringComparison.OrdinalIgnoreCase))
                continue;

            Replacements.Add(file);
        }
    }

    private static bool PrepareTargets(Harmony harmony, string postfixName)
    {
        var resourceManager = AccessTools.TypeByName("Robust.Shared.ContentPack.ResourceManager");
        _resPath = AccessTools.TypeByName("Robust.Shared.Utility.ResPath");
        if (resourceManager == null || _resPath == null)
        {
            Console.WriteLine("[ILLUSIO-RESPACK] ResourceManager или ResPath не найдены");
            return false;
        }

        _resPathCtor = AccessTools.Constructor(_resPath, new[] { typeof(string) });
        _canonPath = AccessTools.Field(_resPath, "CanonPath");
        _findFiles = FindMethodWithParam(resourceManager, "ContentFindFiles", _resPath);
        _fileRead = FindMethodWithParam(resourceManager, "ContentFileRead", _resPath);
        if (_resPathCtor == null || _canonPath == null || _findFiles == null)
        {
            Console.WriteLine("[ILLUSIO-RESPACK] не удалось собрать точки патча");
            return false;
        }

        harmony.Patch(
            _findFiles,
            postfix: new HarmonyMethod(typeof(ResourcePacks), postfixName));
        return true;
    }

    private static void FindFilesSwapPostfix(ref object? __result)
    {
        if (_resPathCtor == null || _canonPath == null || Replacements.Count == 0)
            return;

        if (__result is not IEnumerable source)
            return;

        var listType = typeof(List<>).MakeGenericType(_resPath!);
        if (Activator.CreateInstance(listType) is not IList replaced)
            return;

        var pending = new List<string>(Replacements);
        foreach (var item in source)
        {
            var canonPath = _canonPath.GetValue(item) as string ?? string.Empty;
            var swapped = false;
            for (var index = 0; index < pending.Count; index++)
            {
                if (canonPath.Length == 0 ||
                    !pending[index].EndsWith(canonPath, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                replaced.Add(_resPathCtor.Invoke(new object?[] { pending[index] }));
                pending.RemoveAt(index);
                swapped = true;
                break;
            }

            if (!swapped)
                replaced.Add(item);
        }

        __result = replaced;
    }

    private static void StartDumper(Harmony harmony)
    {
        if (!PrepareTargets(harmony, nameof(FindFilesDumpPostfix)))
            return;

        if (_fileRead == null)
        {
            Console.WriteLine("[ILLUSIO-DUMP] ContentFileRead не найден");
            return;
        }

        try
        {
            Directory.CreateDirectory(_dumpDir!);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-DUMP] каталог недоступен: {e.Message}");
            return;
        }

        Console.WriteLine($"[ILLUSIO-DUMP] выгрузка ресурсов в {_dumpDir}");
    }

    private static void FindFilesDumpPostfix(object __instance)
    {
        if (Interlocked.Exchange(ref _dumpStarted, 1) == 1)
            return;

        var instance = __instance;
        var findFiles = _findFiles;
        var fileRead = _fileRead;
        var resPathCtor = _resPathCtor;
        var canonPath = _canonPath;
        var dumpDir = _dumpDir;
        if (findFiles == null || fileRead == null || resPathCtor == null || canonPath == null)
            return;

        new Thread(() => DumpAll(
                instance,
                findFiles,
                fileRead,
                resPathCtor,
                canonPath,
                dumpDir ?? "dump"))
        { IsBackground = true }.Start();
    }

    private static void DumpAll(
        object instance,
        MethodInfo findFiles,
        MethodInfo fileRead,
        ConstructorInfo resPathCtor,
        FieldInfo canonPath,
        string dumpDir)
    {
        try
        {
            var root = resPathCtor.Invoke(new object?[] { "/" });
            if (findFiles.Invoke(instance, new object?[] { root }) is not IEnumerable files)
                return;

            var count = 0;
            foreach (var item in files)
            {
                var canon = canonPath.GetValue(item) as string ?? string.Empty;
                if (canon.Length == 0)
                    continue;

                var relative = canon.StartsWith('/') ? canon[1..] : canon;
                var target = Path.Combine(dumpDir, relative);
                try
                {
                    if (fileRead.Invoke(instance, new object?[] { item }) is not Stream stream)
                        continue;

                    using (stream)
                    {
                        var parent = Path.GetDirectoryName(target);
                        if (!string.IsNullOrEmpty(parent))
                            Directory.CreateDirectory(parent);

                        using var output = File.Create(target);
                        stream.CopyTo(output);
                    }

                    count++;
                }
                catch (Exception e)
                {
                    Console.WriteLine($"[ILLUSIO-DUMP] {canon}: {e.Message}");
                }
            }

            Console.WriteLine($"[ILLUSIO-DUMP] выгружено {count} файлов в {dumpDir}");
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-DUMP] ошибка выгрузки: {e.Message}");
        }
    }

    private static List<string> ParseDirs(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return new List<string>();

        return raw
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(Directory.Exists)
            .ToList();
    }

    private static MethodInfo? FindMethodWithParam(Type type, string name, Type param)
    {
        var nullableParam = typeof(Nullable<>).MakeGenericType(param);
        return AccessTools.GetDeclaredMethods(type)
            .Where(method => method.Name == name && method.GetParameters().Length == 1)
            .OrderBy(method => method.GetParameters()[0].ParameterType == param
                ? 0
                : method.GetParameters()[0].ParameterType == nullableParam
                    ? 1
                    : 2)
            .FirstOrDefault();
    }
}

internal static class BuiltInPatches
{
    private static readonly string[] BlackholeWhitelist =
        { "say", "whisper", "me", "ooc", "looc", "observe", "suicide" };

    public static void Apply(Harmony harmony)
    {
        PatchHwid(harmony);
        if (Flag("ILLUSIO_PATCH_RPC"))
            PatchRpc(harmony);
        else if (Flag("ILLUSIO_RPC_FAKE"))
            PatchRpcFake(harmony);
        if (Flag("ILLUSIO_PATCH_JAM_DIALS"))
            PatchJamDials(harmony);
        if (Flag("ILLUSIO_PATCH_BLACKHOLE"))
            PatchBlackhole(harmony);
    }

    private static bool Flag(string name)
    {
        return Envsey.Get(name) == "1";
    }

    private static void PatchHwid(Harmony harmony)
    {
        var mode = (Envsey.Get("ILLUSIO_HWID_MODE") ?? "").Trim().ToLowerInvariant();
        if (mode.Length == 0)
        {
            if (!Flag("ILLUSIO_PATCH_HWID"))
                return;

            mode = "random";
        }

        if (mode == "off")
            return;

        var patched = 0;
        foreach (var name in new[] { "Robust.Client.HWId.BasicHWId", "Robust.Client.Hwid.BasicHwid" })
        {
            var type = AccessTools.TypeByName(name);
            if (type == null)
                continue;

            var modern = AccessTools.Method(type, "GetModern");
            if (modern != null)
            {
                harmony.Patch(modern, postfix: new HarmonyMethod(typeof(BuiltInPatches), nameof(HwidPostfix)));
                patched++;
            }

            var legacy = AccessTools.Method(type, "GetLegacy");
            if (legacy != null)
            {
                harmony.Patch(legacy, postfix: new HarmonyMethod(typeof(BuiltInPatches), nameof(HwidPostfix)));
                patched++;
            }
        }

        var shared = AccessTools.TypeByName("Robust.Shared.Network.HWId");
        var calc = shared == null ? null : AccessTools.Method(shared, "Calc");
        if (calc != null)
        {
            harmony.Patch(calc, postfix: new HarmonyMethod(typeof(BuiltInPatches), nameof(HwidPostfix)));
            patched++;
        }

        Console.WriteLine($"[ILLUSIO-PATCH] HWID: режим {mode}, точек патча {patched}");
    }

    private static void PatchRpc(Harmony harmony)
    {
        var type = AccessTools.TypeByName("Robust.Client.Utility.DiscordRichPresence");
        if (type == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] RPC: тип не найден");
            return;
        }

        var initialize = AccessTools.Method(type, "Initialize");
        if (initialize != null)
            harmony.Patch(initialize, prefix: new HarmonyMethod(typeof(BuiltInPatches), nameof(ReturnFalse)));

        var update = AccessTools.Method(type, "Update");
        if (update != null)
            harmony.Patch(update, prefix: new HarmonyMethod(typeof(BuiltInPatches), nameof(ReturnFalse)));

        Console.WriteLine("[ILLUSIO-PATCH] RPC: Discord отключён");
    }

    private static void PatchRpcFake(Harmony harmony)
    {
        var type = AccessTools.TypeByName("Robust.Client.Utility.DiscordRichPresence");
        if (type == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] RPC: тип не найден");
            return;
        }

        var update = AccessTools.Method(type, "Update");
        if (update == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] RPC: метод Update не найден");
            return;
        }

        harmony.Patch(update, prefix: new HarmonyMethod(typeof(BuiltInPatches), nameof(RpcFakePrefix)));
        Console.WriteLine("[ILLUSIO-PATCH] RPC: ник в Discord подменяется");
    }

    private static void RpcFakePrefix(ref string username)
    {
        var fake = (Envsey.Get("ILLUSIO_RPC_USERNAME") ?? "").Trim();
        if (fake.Length > 0)
            username = fake;
    }

    private static void PatchJamDials(Harmony harmony)
    {
        var type = AccessTools.TypeByName("Robust.Client.GameController");
        if (type == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] JAM: тип не найден");
            return;
        }

        var redial = AccessTools.Method(type, "Redial");
        if (redial != null)
            harmony.Patch(redial, prefix: new HarmonyMethod(typeof(BuiltInPatches), nameof(ReturnFalse)));

        Console.WriteLine("[ILLUSIO-PATCH] JAM: редиал заблокирован");
    }

    private static void PatchBlackhole(Harmony harmony)
    {
        var type = AccessTools.TypeByName("Robust.Client.Console.ClientConsoleHost");
        if (type == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] BLACKHOLE: тип не найден");
            return;
        }

        var execute = AccessTools.Method(type, "RemoteExecuteCommand");
        if (execute != null)
            harmony.Patch(execute, prefix: new HarmonyMethod(typeof(BuiltInPatches), nameof(BlackholePrefix)));

        Console.WriteLine("[ILLUSIO-PATCH] BLACKHOLE: удалённые команды фильтруются");
    }

    private static byte[] RandomBytes(int length)
    {
        var bytes = new byte[length];
        using var rng = System.Security.Cryptography.RandomNumberGenerator.Create();
        rng.GetBytes(bytes);
        return bytes;
    }

    private static void HwidPostfix(ref byte[] __result)
    {
        if (__result.Length <= 1)
            return;

        var mode = (Envsey.Get("ILLUSIO_HWID_MODE") ?? "").Trim().ToLowerInvariant();
        if (mode.Length == 0)
            mode = "random";

        if (mode == "fixed" && TryFillFixed(__result, (Envsey.Get("ILLUSIO_HWID_VALUE") ?? "").Trim()))
            return;

        var raw = RandomBytes(__result.Length - 1);
        Array.Copy(raw, 0, __result, 1, raw.Length);
    }

    private static bool TryFillFixed(byte[] result, string value)
    {
        if (value.Length == 0 || value.Length % 2 != 0 || value.Any(character => !Uri.IsHexDigit(character)))
            return false;

        var bytes = new byte[value.Length / 2];
        for (var index = 0; index < bytes.Length; index++)
            bytes[index] = Convert.ToByte(value.Substring(index * 2, 2), 16);

        for (var index = 1; index < result.Length; index++)
            result[index] = bytes[(index - 1) % bytes.Length];

        return true;
    }

    private static bool ReturnFalse()
    {
        return false;
    }

    private static bool BlackholePrefix(string command)
    {
        var trimmed = command.TrimStart().TrimStart('/').TrimStart();
        foreach (var allowed in BlackholeWhitelist)
        {
            if (trimmed.StartsWith(allowed, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }
}

internal class Program
{
    private const string MarkerType = "IllusioMod";
    private const string HarmonyId = "io.github.mel0k1.illusio.mods";
    private const string ModsEnv = "SS14_LOADER_MOD_DLLS";

    private readonly string[] _engineArgs;
    private const string RobustAssemblyName = "Robust.Client";

    private readonly IFileApi _fileApi;

    private Program(string robustPath, string[] engineArgs)
    {
        _engineArgs = engineArgs;
        var zipArchive = new ZipArchive(File.OpenRead(robustPath), ZipArchiveMode.Read);

        AssemblyLoadContext.Default.Resolving += LoadContextOnResolving;
        AssemblyLoadContext.Default.ResolvingUnmanagedDll += LoadContextOnResolvingUnmanaged;

        var prefix = "";
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            prefix = "Space Station 14.app/Contents/Resources/";
        }

        _fileApi = new ZipFileApi(zipArchive, prefix);
    }

    private IntPtr LoadContextOnResolvingUnmanaged(Assembly assembly, string unmanaged)
    {
        var ourDir = Path.GetDirectoryName(typeof(Program).Assembly.Location);
        var a = Path.Combine(ourDir!, unmanaged);
        if (NativeLibrary.TryLoad(a, out var handle))
            return handle;

        return IntPtr.Zero;
    }

    private bool Run()
    {
        if (!TryOpenAssembly(RobustAssemblyName, out var clientAssembly))
        {
            Console.WriteLine("Unable to locate Robust.Client.dll in engine build!");
            return false;
        }

        if (!TryGetLoader(clientAssembly, out var loader))
            return false;

        var contentZip = Envsey.Get("SS14_LOADER_OVERLAY_ZIP");
        var modZips = Envsey.Get("SS14_LOADER_OVERLAY_ZIPS");
        var overlays = ParseOverlayZips(
            string.Join(';', new[] { contentZip, modZips }.Where(part => !string.IsNullOrWhiteSpace(part))));
        var extraMounts = new List<ApiMount>();
        try
        {
            foreach (var (api, archive) in overlays)
            {
                extraMounts.Add(new ApiMount(api, "/"));
            }

            ApplyBuiltInPatches(clientAssembly);
            TryOpenAssembly("Robust.Shared", out _);
            ApplyMods(overlays);
            ApplyEnginePatches();
            ApplyBackports();

            var args = new MainArgs(_engineArgs, _fileApi, null, extraMounts);

            Envsey.Scrub();
            loader.Main(args);
        }
        finally
        {
            foreach (var (_, archive) in overlays)
            {
                archive.Dispose();
            }
        }
        return true;
    }

    private void ApplyBuiltInPatches(Assembly clientAssembly)
    {
        var harmony = new Harmony(HarmonyId);
        try
        {
            BuiltInPatches.Apply(harmony);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-PATCH] ошибка встроенных патчей: {e.Message}");
        }

        try
        {
            Hidesey.Apply(harmony);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-STEALTH] ошибка скрытия: {e.Message}");
        }
    }

    private void ApplyEnginePatches()
    {
        var harmony = new Harmony(HarmonyId);
        try
        {
            Subverters.Apply(harmony);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-SUBVERT] ошибка сайдлоада: {e.Message}");
        }

        try
        {
            ResourcePacks.Apply(harmony);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-RESPACK] ошибка ресурс-паков: {e.Message}");
        }
    }

    private void ApplyBackports()
    {
        var harmony = new Harmony(HarmonyId);
        try
        {
            BackportMan.Setup();
            BackportMan.PatchBackports(harmony, false);
        }
        catch (Exception e)
        {
            Console.WriteLine($"[ILLUSIO-BACKPORT] ошибка движковых бэкпортов: {e.Message}");
            return;
        }

        StartContentBackportsThread(harmony);
    }

    private static void StartContentBackportsThread(Harmony harmony)
    {
        new Thread(() =>
        {
            var deadline = DateTime.UtcNow.AddSeconds(60);
            while (DateTime.UtcNow < deadline)
            {
                var loaded = AppDomain.CurrentDomain
                    .GetAssemblies()
                    .Select(assembly => assembly.GetName().Name ?? "")
                    .ToHashSet(StringComparer.Ordinal);
                if (loaded.Contains("Content.Client") && loaded.Contains("Content.Shared"))
                    break;

                Thread.Sleep(400);
            }

            try
            {
                BackportMan.PatchBackports(harmony, true);
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-BACKPORT] ошибка контентных бэкпортов: {e.Message}");
            }
        })
        {
            IsBackground = true,
        }.Start();
    }

    private void ApplyMods(IReadOnlyList<(ZipFileApi Api, ZipArchive Archive)> overlays)
    {
        var paths = ParsePathList(Envsey.Get(ModsEnv));
        if (paths.Count == 0)
            return;

        var mods = LoadModAssemblies(paths);
        if (mods.Count == 0)
            return;

        var harmony = new Harmony(HarmonyId);
        var preload = mods.Where(mod => mod.Preload).ToList();
        var rest = mods.Where(mod => !mod.Preload).ToList();
        ApplyModList(preload, harmony);
        var failed = ApplyModList(rest, harmony);
        if (failed.Count > 0)
            StartContentPatchThread(failed, harmony, overlays);
    }

    private static List<string> ParsePathList(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return new List<string>();

        return raw
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(File.Exists)
            .ToList();
    }

    private static List<ModInfo> LoadModAssemblies(IReadOnlyList<string> paths)
    {
        var result = new List<ModInfo>();
        foreach (var path in paths)
        {
            try
            {
                var bytes = File.ReadAllBytes(path);
                Assembly? assembly = null;
                Hidesey.SuppressAssemblyLoadDuring(() => assembly = Assembly.Load(bytes));
                if (assembly == null)
                    continue;

                Hidesey.TrackMod(assembly);
                var marker = FindMarker(assembly);
                var name = ReadMarkerString(marker, "Name");
                var description = ReadMarkerString(marker, "Description");
                var preload = ReadMarkerBool(marker, "Preload");
                var displayName = string.IsNullOrWhiteSpace(name)
                    ? Path.GetFileNameWithoutExtension(path)
                    : name;
                Console.WriteLine($"[ILLUSIO-MODS] загружен {displayName} ({Path.GetFileName(path)})");
                result.Add(new ModInfo(path, assembly, marker, displayName, description ?? "", preload));
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-MODS] не удалось загрузить {Path.GetFileName(path)}: {e.Message}");
            }
        }

        return result;
    }

    private static string? ReadMarkerString(Type? marker, string field)
    {
        return marker
            ?.GetField(field, BindingFlags.Public | BindingFlags.Static)
            ?.GetValue(null) as string;
    }

    private static bool ReadMarkerBool(Type? marker, string field)
    {
        return marker
            ?.GetField(field, BindingFlags.Public | BindingFlags.Static)
            ?.GetValue(null) is true;
    }

    private static Type? FindMarker(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes().FirstOrDefault(type => type.Name == MarkerType)
                ?? assembly.GetType(MarkerType);
        }
        catch
        {
            return assembly.GetType(MarkerType);
        }
    }

    private static MethodInfo? FindPatchMethod(Type marker)
    {
        var candidates = marker.GetMethods(BindingFlags.Public | BindingFlags.Static)
            .Where(method => method.Name == "Patch" && !method.IsGenericMethod)
            .ToList();
        return candidates.FirstOrDefault(method => method.GetParameters().Length == 1)
            ?? candidates.FirstOrDefault(method => method.GetParameters().Length == 0);
    }

    private static List<ModInfo> ApplyModList(IReadOnlyList<ModInfo> mods, Harmony harmony)
    {
        var failed = new List<ModInfo>();
        foreach (var mod in mods)
        {
            if (mod.Marker == null)
            {
                Console.WriteLine($"[ILLUSIO-MODS] {mod.Name}: нет класса {MarkerType}, пропуск");
                continue;
            }

            var method = FindPatchMethod(mod.Marker);
            if (method == null)
            {
                Console.WriteLine($"[ILLUSIO-MODS] {mod.Name}: не найден публичный статический метод Patch");
                continue;
            }

            try
            {
                var parameters = method.GetParameters();
                method.Invoke(
                    null,
                    parameters.Length == 1 ? new object[] { harmony } : Array.Empty<object>());
                Console.WriteLine($"[ILLUSIO-MODS] {mod.Name}: патчи применены");
            }
            catch (Exception e)
            {
                Console.WriteLine($"[ILLUSIO-MODS] {mod.Name}: {e.InnerException?.Message ?? e.Message}");
                failed.Add(mod);
            }
        }

        return failed;
    }

    private static void StartContentPatchThread(
        IReadOnlyList<ModInfo> failed,
        Harmony harmony,
        IReadOnlyList<(ZipFileApi Api, ZipArchive Archive)> overlays)
    {
        var pending = failed.ToList();
        var hasContent = overlays.Count > 0;
        new Thread(() =>
        {
            var deadline = DateTime.UtcNow.AddSeconds(60);
            if (hasContent)
            {
                while (DateTime.UtcNow < deadline)
                {
                    var loaded = AppDomain.CurrentDomain
                        .GetAssemblies()
                        .Select(assembly => assembly.GetName().Name ?? "")
                        .ToHashSet(StringComparer.Ordinal);
                    if (loaded.Contains("Content.Client") && loaded.Contains("Content.Shared"))
                        break;

                    Thread.Sleep(400);
                }
            }

            var retried = ApplyModList(pending, harmony);
            foreach (var mod in retried)
            {
                Console.WriteLine($"[ILLUSIO-MODS] {mod.Name}: патчи не применились");
            }
        })
        {
            IsBackground = true,
        }.Start();
    }

    private static int RunScanMods(string dir)
    {
        if (!Directory.Exists(dir))
        {
            Console.Error.WriteLine("scan-mods: каталог не найден");
            return 1;
        }

        var dlls = Directory.GetFiles(dir, "*.dll")
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (dlls.Count == 0)
        {
            Console.WriteLine("[]");
            return 0;
        }

        var results = new List<object>();
        foreach (var dll in dlls)
        {
            var context = new AssemblyLoadContext(
                $"illusio-scan-{Path.GetFileName(dll)}",
                isCollectible: true);
            try
            {
                using var stream = File.OpenRead(dll);
                var assembly = context.LoadFromStream(stream);
                var type = FindMarker(assembly);
                var version = assembly.GetName().Version?.ToString() ?? "";
                if (type == null)
                {
                    results.Add(new
                    {
                        file = Path.GetFileName(dll),
                        name = assembly.GetName().Name ?? "",
                        description = "",
                        version,
                        preload = false,
                        game = true,
                    });
                    continue;
                }

                var name = ReadMarkerString(type, "Name") ?? "";
                var description = ReadMarkerString(type, "Description") ?? "";
                var preload = ReadMarkerBool(type, "Preload");
                results.Add(new
                {
                    file = Path.GetFileName(dll),
                    name,
                    description,
                    version,
                    preload,
                    game = false,
                });
            }
            catch (Exception e)
            {
                Console.Error.WriteLine($"scan-mods: {Path.GetFileName(dll)}: {e.Message}");
            }
            finally
            {
                context.Unload();
            }
        }

        Console.WriteLine(JsonSerializer.Serialize(
            results,
            new JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        return 0;
    }

    private static List<(ZipFileApi Api, ZipArchive Archive)> ParseOverlayZips(string raw)
    {
        var result = new List<(ZipFileApi, ZipArchive)>();
        foreach (var part in raw.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!File.Exists(part))
            {
                continue;
            }

            var archive = new ZipArchive(File.OpenRead(part), ZipArchiveMode.Read);
            result.Add((new ZipFileApi(archive, ""), archive));
        }
        return result;
    }

    private static bool TryGetLoader(Assembly clientAssembly, [NotNullWhen(true)] out ILoaderEntryPoint? loader)
    {
        loader = null;
        var attrib = clientAssembly.GetCustomAttribute<LoaderEntryPointAttribute>();
        if (attrib == null)
        {
            Console.WriteLine("No LoaderEntryPointAttribute found on Robust.Client assembly!");
            return false;
        }

        var type = attrib.LoaderEntryPointType;
        if (!type.IsAssignableTo(typeof(ILoaderEntryPoint)))
        {
            Console.WriteLine("Loader type '{0}' does not implement ILoaderEntryPoint!", type);
            return false;
        }

        loader = (ILoaderEntryPoint)Activator.CreateInstance(type)!;
        return true;
    }

    private Assembly? LoadContextOnResolving(AssemblyLoadContext arg1, AssemblyName arg2)
    {
        return TryOpenAssembly(arg2.Name!, out var assembly) ? assembly : null;
    }

    private bool TryOpenAssembly(string name, [NotNullWhen(true)] out Assembly? assembly)
    {
        if (!TryOpenAssemblyStream(name, out var asm, out var pdb))
        {
            assembly = null;
            return false;
        }

        assembly = AssemblyLoadContext.Default.LoadFromStream(asm, pdb);
        return true;
    }

    private bool TryOpenAssemblyStream(string name, [NotNullWhen(true)] out Stream? asm, out Stream? pdb)
    {
        asm = null;
        pdb = null;

        if (!_fileApi.TryOpen($"{name}.dll", out asm))
            return false;

        _fileApi.TryOpen($"{name}.pdb", out pdb);
        return true;
    }

    [STAThread]
    internal static int Main(string[] args)
    {
        Envsey.Capture();

        if (args.Length >= 2 && args[0] == "scan-mods")
        {
            return RunScanMods(args[1]);
        }

        if (args.Length < 3)
        {
            Console.WriteLine("Usage: illusio-loader <robustPath> <signature> <public key> [engineArg [engineArg...]]");
            return 1;
        }

        var robustPath = args[0];
        var sig = Convert.FromHexString(args[1]);
        var keyPath = args[2];

        var pubKey = PublicKey.Import(
            SignatureAlgorithm.Ed25519,
            File.ReadAllBytes(keyPath),
            KeyBlobFormat.PkixPublicKeyText);

        var robustBytes = File.ReadAllBytes(robustPath);

        if (!SignatureAlgorithm.Ed25519.Verify(pubKey, robustBytes, sig))
        {
            var disableVar = Environment.GetEnvironmentVariable("SS14_DISABLE_SIGNING");
            if (!string.IsNullOrEmpty(disableVar) && bool.Parse(disableVar))
            {
                Console.WriteLine("Failed to verify engine signature, ignoring because signing is disabled.");
            }
            else
            {
                Console.WriteLine("Failed to verify engine signature!");
                return 2;
            }
        }

        var program = new Program(robustPath, args[3..]);
        if (!program.Run())
        {
            return 3;
        }

        return 0;
    }
}
