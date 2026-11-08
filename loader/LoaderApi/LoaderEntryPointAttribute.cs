using System;

namespace Robust.LoaderApi
{
    [AttributeUsage(AttributeTargets.Assembly)]
    public sealed class LoaderEntryPointAttribute : Attribute
    {
        public LoaderEntryPointAttribute(Type loaderEntryPointType)
        {
            LoaderEntryPointType = loaderEntryPointType;
        }

        public Type LoaderEntryPointType { get; }
    }
}
