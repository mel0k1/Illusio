using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;

namespace Robust.LoaderApi
{
    public interface IFileApi
    {
        bool TryOpen(string path, [NotNullWhen(true)] out Stream? stream);

        IEnumerable<string> AllFiles { get; }

        void AllowNonSeekableStreams()
        {
        }
    }
}
