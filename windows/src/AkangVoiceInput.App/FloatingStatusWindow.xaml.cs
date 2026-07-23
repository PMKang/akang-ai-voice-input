using System.Windows;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.App;

public partial class FloatingStatusWindow : Window
{
    private CancellationTokenSource? _autoHideCancellation;

    public FloatingStatusWindow() => InitializeComponent();
    public void ShowWithoutActivation()
    {
        _autoHideCancellation?.Cancel();
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 70;
        if (!IsVisible) Show();
    }

    public async void ShowTemporary(TimeSpan duration)
    {
        ShowWithoutActivation();
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
        TitleText.Text = state switch { VoiceSessionState.Recording => "正在聆听", VoiceSessionState.Transcribing => "正在结束录音", VoiceSessionState.Finalizing => "正在整理", VoiceSessionState.Inserting => "正在写入", VoiceSessionState.Error => "语音输入失败", _ => "Noboard" };
        DetailText.Text = message; if (state != VoiceSessionState.Recording) AudioLevel.Value = 0;
    }
    public void SetPreview(string text) => PreviewText.Text = string.IsNullOrWhiteSpace(text) ? "正在捕捉你的语音…" : text;
    public void SetLevel(float level) => AudioLevel.Value = level;
    private void CloseClicked(object sender, RoutedEventArgs e)
    {
        _autoHideCancellation?.Cancel();
        Hide();
    }
}
