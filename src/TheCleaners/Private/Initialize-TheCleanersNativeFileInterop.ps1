function Initialize-TheCleanersNativeFileInterop {
    <#
    .SYNOPSIS
        Load the Windows handle and file-identity interop type on demand.
    .DESCRIPTION
        The type is compiled only when a temp command executes. It opens files
        with a native handle, reads a volume/file identity, and marks an already
        opened handle for deletion. It does not enumerate or delete by path and
        it is never initialized during module import.
    .OUTPUTS
        System.Void
    #>
    [CmdletBinding()]
    param ()

    $InitializationMutex = [System.Threading.Mutex]::new($false, 'TheCleaners.NativeFileInterop.Initialize')
    $MutexAcquired = $false
    try {
        try {
            $MutexAcquired = $InitializationMutex.WaitOne()
        } catch [System.Threading.AbandonedMutexException] {
            $MutexAcquired = $true
        }

        $NativeType = ([System.Management.Automation.PSTypeName]'TheCleaners.NativeFileInterop').Type
        if ($null -ne $NativeType) {
            return
        }

        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace TheCleaners
{
    public sealed class NativeFileIdentity : IEquatable<NativeFileIdentity>
    {
        private readonly byte[] _fileId;

        public NativeFileIdentity(ulong volumeSerialNumber, byte[] fileId, long length, long lastWriteTimeUtcFileTime, uint attributes)
        {
            VolumeSerialNumber = volumeSerialNumber;
            _fileId = (byte[])fileId.Clone();
            Length = length;
            LastWriteTimeUtcFileTime = lastWriteTimeUtcFileTime;
            Attributes = attributes;
        }

        public ulong VolumeSerialNumber { get; private set; }
        public long Length { get; private set; }
        public long LastWriteTimeUtcFileTime { get; private set; }
        public DateTime LastWriteTimeUtc { get { return DateTime.FromFileTimeUtc(LastWriteTimeUtcFileTime); } }
        public uint Attributes { get; private set; }
        public bool IsDirectory { get { return (Attributes & 0x10U) != 0; } }
        public bool IsReparsePoint { get { return (Attributes & 0x400U) != 0; } }
        public string Key
        {
            get
            {
                return VolumeSerialNumber.ToString("X16") + ":" + BitConverter.ToString(_fileId).Replace("-", string.Empty);
            }
        }

        public bool Equals(NativeFileIdentity other)
        {
            if (ReferenceEquals(other, null) || VolumeSerialNumber != other.VolumeSerialNumber)
            {
                return false;
            }

            return _fileId.SequenceEqual(other._fileId);
        }

        public override bool Equals(object obj)
        {
            return Equals(obj as NativeFileIdentity);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = VolumeSerialNumber.GetHashCode();
                foreach (byte value in _fileId)
                {
                    hash = (hash * 31) + value;
                }

                return hash;
            }
        }
    }

    public static class NativeFileInterop
    {
        private const uint Delete = 0x00010000U;
        private const uint FileReadAttributes = 0x00000080U;
        private const uint FileShareRead = 0x00000001U;
        private const uint FileShareWrite = 0x00000002U;
        private const uint FileShareDelete = 0x00000004U;
        private const uint OpenExisting = 3U;
        private const uint FileFlagOpenReparsePoint = 0x00200000U;
        private const uint FileFlagBackupSemantics = 0x02000000U;
        private const int FileIdInfoClass = 0x12;
        private const int FileStandardInfoClass = 0x01;
        private const int FileBasicInfoClass = 0x00;
        private const int FileAttributeTagInfoClass = 0x09;
        private const int FileDispositionInfoClass = 0x04;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateFileW", SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileIdInfo fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileStandardInfo fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileBasicInfo fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileAttributeTagInfo fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileDispositionInfoData fileInformation,
            uint bufferSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdInfo
        {
            public ulong VolumeSerialNumber;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
            public byte[] FileId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileStandardInfo
        {
            public long AllocationSize;
            public long EndOfFile;
            public uint NumberOfLinks;
            public byte DeletePending;
            public byte Directory;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileBasicInfo
        {
            public long CreationTime;
            public long LastAccessTime;
            public long LastWriteTime;
            public long ChangeTime;
            public uint FileAttributes;
            public uint Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileAttributeTagInfo
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileDispositionInfoData
        {
            public byte DeleteFile;
        }

        private static SafeFileHandle Open(string path, uint desiredAccess, uint shareMode, bool directory)
        {
            uint flags = FileFlagOpenReparsePoint;
            if (directory)
            {
                flags |= FileFlagBackupSemantics;
            }

            SafeFileHandle handle = CreateFile(
                path,
                desiredAccess,
                shareMode,
                IntPtr.Zero,
                OpenExisting,
                flags,
                IntPtr.Zero);

            if (handle.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, "The Windows file handle could not be opened.");
            }

            return handle;
        }

        public static SafeFileHandle OpenForInspection(string path, bool directory)
        {
            return Open(path, FileReadAttributes, FileShareRead | FileShareWrite | FileShareDelete, directory);
        }

        public static SafeFileHandle OpenForIdentityInspection(string path)
        {
            // FILE_READ_ATTRIBUTES is sufficient for identity and reparse checks.
            // This handle retains the inspected object for revalidation but does
            // not request DELETE access, so callers must compare identity again.
            return Open(path, FileReadAttributes, FileShareRead | FileShareWrite, true);
        }

        public static SafeFileHandle OpenForStableEnumeration(string path)
        {
            // DELETE is requested only to hold the directory against rename or
            // replacement while the provider enumerates it; no disposition is set.
            return Open(path, Delete | FileReadAttributes, FileShareRead | FileShareWrite, true);
        }

        public static SafeFileHandle OpenForDeletion(string path, bool directory)
        {
            return Open(path, Delete | FileReadAttributes, FileShareRead, directory);
        }

        public static NativeFileIdentity ReadIdentity(SafeFileHandle handle)
        {
            FileIdInfo idInfo = new FileIdInfo { FileId = new byte[16] };
            if (!GetFileInformationByHandleEx(handle, FileIdInfoClass, ref idInfo, (uint)Marshal.SizeOf(typeof(FileIdInfo))))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The Windows file identity could not be read.");
            }

            FileStandardInfo standardInfo = new FileStandardInfo();
            if (!GetFileInformationByHandleEx(handle, FileStandardInfoClass, ref standardInfo, (uint)Marshal.SizeOf(typeof(FileStandardInfo))))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The Windows file standard information could not be read.");
            }

            FileBasicInfo basicInfo = new FileBasicInfo();
            if (!GetFileInformationByHandleEx(handle, FileBasicInfoClass, ref basicInfo, (uint)Marshal.SizeOf(typeof(FileBasicInfo))))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The Windows file basic information could not be read.");
            }

            FileAttributeTagInfo attributes = new FileAttributeTagInfo();
            if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfoClass, ref attributes, (uint)Marshal.SizeOf(typeof(FileAttributeTagInfo))))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The Windows file attributes could not be read.");
            }

            return new NativeFileIdentity(idInfo.VolumeSerialNumber, idInfo.FileId, standardInfo.EndOfFile, basicInfo.LastWriteTime, attributes.FileAttributes);
        }

        public static void MarkForDeletion(SafeFileHandle handle)
        {
            FileDispositionInfoData disposition = new FileDispositionInfoData { DeleteFile = 1 };
            if (!SetFileInformationByHandle(handle, FileDispositionInfoClass, ref disposition, (uint)Marshal.SizeOf(typeof(FileDispositionInfoData))))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The opened Windows file handle could not be marked for deletion.");
            }
        }
    }
}
'@ -ErrorAction Stop
    } finally {
        if ($MutexAcquired) {
            $null = $InitializationMutex.ReleaseMutex()
        }
        $InitializationMutex.Dispose()
    }
}

function Get-TheCleanersFileIdentity {
    <#
    .SYNOPSIS
        Read a filesystem identity using a native inspection handle.
    .DESCRIPTION
        The inspection handle requests no file-content access and is closed before
        the caller mutates anything. The returned FILE_ID_INFO identity is stable
        for the object on NTFS and ReFS while it exists.
    .PARAMETER LiteralPath
        Fully qualified filesystem path.
    .PARAMETER Directory
        Open the path with directory handle semantics.
    .OUTPUTS
        TheCleaners.NativeFileIdentity
    #>
    [CmdletBinding()]
    [OutputType('TheCleaners.NativeFileIdentity')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $LiteralPath,

        [Parameter()]
        [switch]
        $Directory
    )

    Initialize-TheCleanersNativeFileInterop
    $Handle = [TheCleaners.NativeFileInterop]::OpenForInspection($LiteralPath, $Directory.IsPresent)
    try {
        [TheCleaners.NativeFileInterop]::ReadIdentity($Handle)
    } finally {
        $Handle.Dispose()
    }
}
