using System;
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
    string Description);

internal static class BuiltInPatches
{
    private static readonly string[] BlackholeWhitelist =
        { "say", "whisper", "me", "ooc", "looc", "observe", "suicide" };

    public static void Apply(Harmony harmony)
    {
        if (Flag("ILLUSIO_PATCH_HWID"))
            PatchHwid(harmony);
        if (Flag("ILLUSIO_PATCH_RPC"))
            PatchRpc(harmony);
        if (Flag("ILLUSIO_PATCH_JAM_DIALS"))
            PatchJamDials(harmony);
        if (Flag("ILLUSIO_PATCH_BLACKHOLE"))
            PatchBlackhole(harmony);
    }

    private static bool Flag(string name)
    {
        return Environment.GetEnvironmentVariable(name) == "1";
    }

    private static void PatchHwid(Harmony harmony)
    {
        var type = AccessTools.TypeByName("Robust.Client.HWId.BasicHWId");
        if (type == null)
        {
            Console.WriteLine("[ILLUSIO-PATCH] HWID: тип не найден");
            return;
        }

        var modern = AccessTools.Method(type, "GetModern");
        if (modern != null)
            harmony.Patch(modern, postfix: new HarmonyMethod(typeof(BuiltInPatches), nameof(HwidPostfix)));

        var legacy = AccessTools.Method(type, "GetLegacy");
        if (legacy != null)
            harmony.Patch(legacy, postfix: new HarmonyMethod(typeof(BuiltInPatches), nameof(HwidPostfix)));

        Console.WriteLine("[ILLUSIO-PATCH] HWID: подмена включена");
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

        var raw = RandomBytes(__result.Length - 1);
        Array.Copy(raw, 0, __result, 1, raw.Length);
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

        var contentZip = Environment.GetEnvironmentVariable("SS14_LOADER_OVERLAY_ZIP");
        var modZips = Environment.GetEnvironmentVariable("SS14_LOADER_OVERLAY_ZIPS");
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
            ApplyMods(overlays);

            var args = new MainArgs(_engineArgs, _fileApi, null, extraMounts);

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
    }

    private void ApplyMods(IReadOnlyList<(ZipFileApi Api, ZipArchive Archive)> overlays)
    {
        var paths = ParsePathList(Environment.GetEnvironmentVariable(ModsEnv));
        if (paths.Count == 0)
            return;

        var mods = LoadModAssemblies(paths);
        if (mods.Count == 0)
            return;

        var harmony = new Harmony(HarmonyId);
        var failed = ApplyModList(mods, harmony);
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
                var assembly = Assembly.Load(bytes);
                var marker = FindMarker(assembly);
                var name = ReadMarkerString(marker, "Name");
                var description = ReadMarkerString(marker, "Description");
                var displayName = string.IsNullOrWhiteSpace(name)
                    ? Path.GetFileNameWithoutExtension(path)
                    : name;
                Console.WriteLine($"[ILLUSIO-MODS] загружен {displayName} ({Path.GetFileName(path)})");
                result.Add(new ModInfo(path, assembly, marker, displayName, description ?? ""));
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
                if (type == null)
                    continue;

                var name = ReadMarkerString(type, "Name") ?? "";
                var description = ReadMarkerString(type, "Description") ?? "";
                var version = assembly.GetName().Version?.ToString() ?? "";
                results.Add(new
                {
                    file = Path.GetFileName(dll),
                    name,
                    description,
                    version,
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
