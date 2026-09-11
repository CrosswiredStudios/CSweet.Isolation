using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace CSweet.Isolation.Security;

/// <summary>Encoding shared by execution services. Each service supplies its own immutable purpose.</summary>
public static class WorkloadAuthorizationEnvelope
{
    public static string Digest(string value) =>
        "sha256:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    public static bool IsDigest(string? value) => value is { Length: 71 } &&
        value.StartsWith("sha256:", StringComparison.Ordinal) &&
        value.AsSpan(7).IndexOfAnyExcept("0123456789abcdef") < 0;

    public static byte[] Encode(string purpose, byte version, Guid hostId, Guid assignmentId,
        Guid workloadId, long epoch, string providerId, string digest,
        DateTimeOffset issuedAt, DateTimeOffset expiresAt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(purpose);
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        if (!IsDigest(digest)) throw new ArgumentException("Expected a canonical SHA-256 digest.", nameof(digest));
        if (expiresAt <= issuedAt) throw new ArgumentOutOfRangeException(nameof(expiresAt));
        using var stream = new MemoryStream();
        WriteBytes(stream, Encoding.UTF8.GetBytes(purpose));
        stream.WriteByte(version);
        WriteGuid(stream, hostId); WriteGuid(stream, assignmentId); WriteGuid(stream, workloadId);
        WriteLong(stream, epoch);
        WriteBytes(stream, Encoding.UTF8.GetBytes(providerId));
        WriteBytes(stream, Encoding.UTF8.GetBytes(digest));
        WriteLong(stream, issuedAt.ToUnixTimeSeconds()); WriteLong(stream, expiresAt.ToUnixTimeSeconds());
        return stream.ToArray();
    }

    private static void WriteGuid(Stream stream, Guid value)
    {
        Span<byte> buffer = stackalloc byte[16];
        value.TryWriteBytes(buffer, bigEndian: true, out _); stream.Write(buffer);
    }
    private static void WriteBytes(Stream stream, ReadOnlySpan<byte> bytes)
    {
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(length, bytes.Length);
        stream.Write(length); stream.Write(bytes);
    }
    private static void WriteLong(Stream stream, long value)
    {
        Span<byte> bytes = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(bytes, value); stream.Write(bytes);
    }
}
