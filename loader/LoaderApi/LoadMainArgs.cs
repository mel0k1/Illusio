using System.Collections.Generic;

namespace Robust.LoaderApi
{
    public interface IMainArgs
    {
        string[] Args { get; }

        IFileApi FileApi { get; }

        IRedialApi? RedialApi => null;

        IEnumerable<ApiMount>? ApiMounts => null;
    }
}
