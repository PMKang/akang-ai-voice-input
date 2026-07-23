using System.Windows;
using System.Windows.Threading;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.App;

public partial class FloatingStatusWindow : Window
{
    private readonly DispatcherTimer _elapsedTimer;
    private CancellationTokenSource? _autoHideCancellation;
    private DateTimeOffset _listeningStartedAt;
    private string _latestPreview = string.Empty;
    private string _displayName = "自在说";

    public FloatingStatusWindow()
    {
        InitializeComponent();
        _elapsedTimer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Normal, (_, _) =>
        {
            var elapsed = DateTimeOffset.Now - _listeningStartedAt;
            ElapsedText.Text = $"{Math.Max(0, (int)elapsed.TotalMinutes):00}:{Math.Max(0, elapsed.Seconds):00}";
        }, Dispatcher);
        _elapsedTimer.Stop();
    }

    public void ShowWithoutActivation()
    {
        _autoHideCancellation?.Cancel();
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 80;
        if (!IsVisible) Show();
    }

    public async void ShowTemporary(TimeSpan duration)
    {
        ShowWithoutActivation();
        _autoHideCancellation?.Cancel();
        _autoHideCancellation = new CancellationTokenSource();
        var token = _autoHideCancellation.Token;
        try
        {
            await Task.Delay(duration, token);
            if (!token.IsCancellationRequested) Hide();
        }
        catch (OperationCanceledException)
        {
        }
    }

    public void UpdateState(VoiceSessionState state, string message)
    {
        switch (state)
        {
            case VoiceSessionState.Recording:
                Width = 620;
                Height = 144;
                ListeningPanel.Visibility = Visibility.Visible;
                ProcessingPanel.Visibility = Visibility.Collapsed;
                ClipboardPanel.Visibility = Visibility.Collapsed;
                ListeningTitleText.Text = $"{_displayName} 正在聆听";
                if (!_elapsedTimer.IsEnabled)
                {
                    _listeningStartedAt = DateTimeOffset.Now;
                    ElapsedText.Text = "00:00";
                    _elapsedTimer.Start();
                }
                break;

            case VoiceSessionState.Transcribing:
            case VoiceSessionState.Finalizing:
            case VoiceSessionState.Inserting:
                _elapsedTimer.Stop();
                Width = 360;
                Height = 92;
                ListeningPanel.Visibility = Visibility.Collapsed;
                ProcessingPanel.Visibility = Visibility.Visible;
                ClipboardPanel.Visibility = Visibility.Collapsed;
                ProcessingTitleText.Text = state == VoiceSessionState.Inserting ? "正在写入" : "正在整理";
                break;

            case VoiceSessionState.Error:
                ShowClipboardState("语音输入失败", message);
                break;

            case VoiceSessionState.Idle when message != "已输入":
                ShowClipboardState(
                    message.Contains("剪贴板", StringComparison.OrdinalIgnoreCase) ||
                    message.Contains("复制", StringComparison.OrdinalIgnoreCase)
                        ? "未能自动写入，文字已复制"
                        : "语音输入提示",
                    message);
                break;

            default:
                _elapsedTimer.Stop();
                break;
        }
    }

    public void SetPreview(string text)
    {
        _latestPreview = text?.Trim() ?? string.Empty;
        PreviewText.Text = string.IsNullOrWhiteSpace(_latestPreview)
            ? "正在捕捉你的语音…"
            : _latestPreview;
    }

    public void SetLevel(float level) => Waveform.Level = level;

    public void SetDisplayName(string displayName)
    {
        _displayName = string.IsNullOrWhiteSpace(displayName) ? "自在说" : displayName.Trim();
        ListeningTitleText.Text = $"{_displayName} 正在聆听";
    }

    private void ShowClipboardState(string title, string detail)
    {
        _elapsedTimer.Stop();
        Width = 560;
        Height = 138;
        ListeningPanel.Visibility = Visibility.Collapsed;
        ProcessingPanel.Visibility = Visibility.Collapsed;
        ClipboardPanel.Visibility = Visibility.Visible;
        ClipboardTitleText.Text = title;
        ClipboardDetailText.Text = detail;
        ClipboardPreviewText.Text = _latestPreview;
    }

    private void CloseClicked(object sender, RoutedEventArgs e)
    {
        _autoHideCancellation?.Cancel();
        Hide();
    }
}
