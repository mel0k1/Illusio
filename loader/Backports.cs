using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using HarmonyLib;

namespace SS14.Loader
{
    internal interface IBackport
    {
        string TargetType { get; set; }
        string TargetMethod { get; set; }
        bool Content { get; set; }
        bool Patch(Harmony harmony);
    }

    [AttributeUsage(AttributeTargets.Class, Inherited = false)]
    internal sealed class BackportTargetEngineAnyAttribute : Attribute;

    [AttributeUsage(AttributeTargets.Class, Inherited = false)]
    internal sealed class BackportTargetEngineAttribute(string version) : Attribute
    {
        public Version Ver { get; } = Version.Parse(version);
    }

    [AttributeUsage(AttributeTargets.Class, Inherited = false)]
    internal sealed class BackportTargetEngineBeforeAttribute(string version) : Attribute
    {
        public Version Ver { get; } = Version.Parse(version);
    }

    [AttributeUsage(AttributeTargets.Class, Inherited = false)]
    internal sealed class BackportTargetEngineAfterAttribute(string version) : Attribute
    {
        public Version Ver { get; } = Version.Parse(version);
    }

    [AttributeUsage(AttributeTargets.Class, Inherited = false)]
    internal sealed class BackportTargetForkAttribute(string forkId) : Attribute
    {
        public string ForkID { get; } = forkId;
    }

    internal static class BackportMan
    {
        private const string Namespace = "SS14.Loader.Backports";

        private static bool _enabled;
        private static bool _disableAny;
        private static string _fork = "";
        private static Version _engine = new();

        internal static void Setup()
        {
            _enabled = Envsey.Get("ILLUSIO_BACKPORTS") == "1";
            _disableAny = Envsey.Get("ILLUSIO_NO_ANY_BACKPORTS") == "1";
            _fork = (Envsey.Get("ILLUSIO_FORK_ID") ?? "").Trim();
            _engine = Version.TryParse((Envsey.Get("ILLUSIO_ENGINE_VER") ?? "").Trim(), out var parsed)
                ? parsed
                : new Version();
            if (_enabled)
            {
                Console.WriteLine(
                    $"[ILLUSIO-BACKPORT] движок {_engine}, форк '{_fork}'");
            }
        }

        private static IEnumerable<Type> Backports()
        {
            return typeof(BackportMan).Assembly.GetTypes()
                .Where(type => type.Namespace == Namespace && typeof(IBackport).IsAssignableFrom(type));
        }

        internal static bool ValidateBackport(Type backport)
        {
            var exact = backport.GetCustomAttribute<BackportTargetEngineAttribute>();
            var before = backport.GetCustomAttribute<BackportTargetEngineBeforeAttribute>();
            var after = backport.GetCustomAttribute<BackportTargetEngineAfterAttribute>();
            var any = backport.GetCustomAttribute<BackportTargetEngineAnyAttribute>();
            var fork = backport.GetCustomAttribute<BackportTargetForkAttribute>();

            if (fork != null
                && !string.Equals(fork.ForkID, _fork, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (before != null && after != null && before.Ver.CompareTo(after.Ver) <= 0)
            {
                Console.WriteLine(
                    $"[ILLUSIO-BACKPORT] {backport.Name}: диапазон {after.Ver}..{before.Ver} вывернут, пропуск");
                return false;
            }

            if (exact == null && before == null && after == null && any == null)
            {
                return false;
            }

            if (any != null && _disableAny && exact == null && before == null && after == null)
            {
                return false;
            }

            if (exact != null && _engine.CompareTo(exact.Ver) != 0)
            {
                return false;
            }

            if (after != null && _engine.CompareTo(after.Ver) < 0)
            {
                return false;
            }

            if (before != null && _engine.CompareTo(before.Ver) > 0)
            {
                return false;
            }

            return true;
        }

        internal static void PatchBackports(Harmony harmony, bool content)
        {
            if (!_enabled)
            {
                return;
            }

            var applied = 0;
            foreach (var backport in Backports())
            {
                if (!ValidateBackport(backport))
                {
                    continue;
                }

                try
                {
                    if (Activator.CreateInstance(backport) is not IBackport port || port.Content != content)
                    {
                        continue;
                    }

                    if (port.Patch(harmony))
                    {
                        applied++;
                        Console.WriteLine($"[ILLUSIO-BACKPORT] {backport.Name}: применён");
                    }
                    else
                    {
                        Console.WriteLine($"[ILLUSIO-BACKPORT] {backport.Name}: цель не найдена");
                    }
                }
                catch (Exception e)
                {
                    Console.WriteLine(
                        $"[ILLUSIO-BACKPORT] {backport.Name}: {e.InnerException?.Message ?? e.Message}");
                }
            }

            Console.WriteLine(
                $"[ILLUSIO-BACKPORT] фаза {(content ? "контент" : "движок")}: применено {applied}");
        }
    }

    namespace Backports
    {
        internal sealed class BindFix : IBackport
        {
            public string TargetType { get; set; } = "Robust.Client.Input.InputManager";
            public string TargetMethod { get; set; } = "LoadKeyFile";
            public bool Content { get; set; }

            public bool Patch(Harmony harmony)
            {
                var input = AccessTools.TypeByName(TargetType);
                var loadKeyFile = input == null ? null : AccessTools.Method(input, TargetMethod);
                if (loadKeyFile == null)
                {
                    return false;
                }

                harmony.Patch(
                    loadKeyFile,
                    transpiler: new HarmonyMethod(typeof(BindFix), nameof(Transpiler)));
                return true;
            }

            private static IEnumerable<CodeInstruction> Transpiler(
                IEnumerable<CodeInstruction> instructions)
            {
                var codes = instructions.ToList();
                for (var index = 0; index < codes.Count - 1; index++)
                {
                    if (codes[index].opcode != OpCodes.Ldarg_2
                        || codes[index + 1].opcode != OpCodes.Call
                        || codes[index + 1].operand is not MethodInfo target
                        || target.Name != "RegisterBinding")
                    {
                        continue;
                    }

                    codes.Insert(index + 1, new CodeInstruction(OpCodes.Ldc_I4_0));
                    codes.Insert(index + 2, new CodeInstruction(OpCodes.Ceq));
                    index += 2;
                }

                return codes.AsEnumerable();
            }
        }
    }
}
