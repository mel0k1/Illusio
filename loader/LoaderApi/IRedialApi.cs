using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;

namespace Robust.LoaderApi
{
    public interface IRedialApi
    {
        void Redial(Uri uri, string text = "");
    }
}
