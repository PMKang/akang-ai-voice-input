using AkangVoiceInput.Core;
using NAudio.Wave;

namespace AkangVoiceInput.Audio;

public sealed class NAudioCaptureService : IAudioCaptureService
{
    public const int SampleRate = 16_000;
    public const int BitsPerSample = 16;
    public const int Channels = 1;
    public const int BufferMilliseconds = 100;

    private readonly object _sync = new();
    private WaveInEvent? _capture;
    private TaskCompletionSource? _stopped;
    private long _capturedByteCount;
    private bool _disposed;

    public event EventHandler<PcmAudioEventArgs>? PcmAvailable;
    public event EventHandler<AudioLevelEventArgs>? LevelChanged;

    public long CapturedByteCount => Interlocked.Read(ref _capturedByteCount);

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            if (_capture is not null) throw new InvalidOperationException("麦克风已经在录音。");
            if (WaveIn.DeviceCount == 0) throw new InvalidOperationException("没有检测到可用麦克风。");

            _capturedByteCount = 0;
            _stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            _capture = new WaveInEvent
            {
                DeviceNumber = 0,
                WaveFormat = new WaveFormat(SampleRate, BitsPerSample, Channels),
                BufferMilliseconds = BufferMilliseconds,
                NumberOfBuffers = 3
            };
            _capture.DataAvailable += OnDataAvailable;
            _capture.RecordingStopped += OnRecordingStopped;
            try
            {
                _capture.StartRecording();
            }
            catch
            {
                DisposeCapture();
                throw;
            }
        }

        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        Task? stoppedTask;
        lock (_sync)
        {
            if (_capture is null) return;
            stoppedTask = _stopped?.Task;
            _capture.StopRecording();
        }

        if (stoppedTask is not null)
        {
            await stoppedTask.WaitAsync(TimeSpan.FromSeconds(3), cancellationToken).ConfigureAwait(false);
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (e.BytesRecorded <= 0) return;
        var chunk = e.Buffer.AsMemory(0, e.BytesRecorded).ToArray();
        Interlocked.Add(ref _capturedByteCount, chunk.Length);
        PcmAvailable?.Invoke(this, new PcmAudioEventArgs(chunk));
        LevelChanged?.Invoke(this, new AudioLevelEventArgs(CalculatePeak(chunk)));
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        lock (_sync)
        {
            if (e.Exception is null) _stopped?.TrySetResult();
            else _stopped?.TrySetException(e.Exception);
            DisposeCapture();
        }
    }

    private static float CalculatePeak(ReadOnlySpan<byte> bytes)
    {
        var peak = 0;
        for (var i = 0; i + 1 < bytes.Length; i += 2)
        {
            var sample = Math.Abs((int)(short)(bytes[i] | bytes[i + 1] << 8));
            if (sample > peak) peak = sample;
        }
        return peak / 32768f;
    }

    private void DisposeCapture()
    {
        if (_capture is null) return;
        _capture.DataAvailable -= OnDataAvailable;
        _capture.RecordingStopped -= OnRecordingStopped;
        _capture.Dispose();
        _capture = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        lock (_sync)
        {
            try { _capture?.StopRecording(); } catch { }
            DisposeCapture();
        }
    }
}
