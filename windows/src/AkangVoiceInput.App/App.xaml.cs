using System.Windows;

namespace AkangVoiceInput.App;

public partial class App : System.Windows.Application
{
    private const string ActivationEventName = "Local\\AkangVoiceInput.Windows.Activate.v1";
    private EventWaitHandle? _activationEvent;
    private CancellationTokenSource? _activationCancellation;

    protected override void OnStartup(StartupEventArgs e)
    {
        AppDiagnostics.Write("Application startup requested.");
        _activationEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ActivationEventName, out var firstInstance);
        if (!firstInstance)
        {
            AppDiagnostics.Write("Forwarding activation to the existing instance.");
            _activationEvent.Set();
            Shutdown();
            return;
        }

        try
        {
            base.OnStartup(e);
            var window = new MainWindow();
            MainWindow = window;
            window.Show();
            _activationCancellation = new CancellationTokenSource();
            _ = Task.Run(() => WatchActivationAsync(window, _activationCancellation.Token));
            AppDiagnostics.Write("Main window shown.");
        }
        catch (Exception exception)
        {
            AppDiagnostics.Write("Application startup failed.", exception);
            System.Windows.MessageBox.Show(
                $"Noboard 启动失败。诊断日志：{AppDiagnostics.LogFilePath}\n\n{exception.Message}",
                "Noboard",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(-1);
        }
    }

    private async Task WatchActivationAsync(MainWindow window, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            var signaled = await Task.Run(() => WaitHandle.WaitAny(new[] { _activationEvent!, token.WaitHandle }, 1000), token).ConfigureAwait(false);
            if (signaled == 0) await Dispatcher.InvokeAsync(window.ShowFromExternalActivation);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        AppDiagnostics.Write($"Application exiting with code {e.ApplicationExitCode}.");
        _activationCancellation?.Cancel();
        if (MainWindow is MainWindow window) window.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _activationCancellation?.Dispose();
        _activationEvent?.Dispose();
        base.OnExit(e);
    }
}
