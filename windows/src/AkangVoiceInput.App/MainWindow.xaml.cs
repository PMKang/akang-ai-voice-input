using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using AkangVoiceInput.App.Platform;
using AkangVoiceInput.Audio;
using AkangVoiceInput.Core;
using AkangVoiceInput.Platform;
using AkangVoiceInput.Transcription;
using Forms = System.Windows.Forms;

namespace AkangVoiceInput.App;

public partial class MainWindow : Window, IAsyncDisposable
{
    private readonly WindowsCredentialStore _credentialStore = new();
    private readonly WindowsStartupService _startupService = new();
    private readonly GlobalHotkeyService _hotkey = new();
    private readonly WindowsAppState _appState;
    private readonly VoiceInputCoordinator _coordinator;
    private readonly FloatingStatusWindow _floating = new();
    private readonly Forms.NotifyIcon _trayIcon;
    private HwndSource? _windowSource;
    private DictionaryEntry? _editingDictionaryEntry;
    private bool _exitRequested;

    public MainWindow()
    {
        AppDiagnostics.Write("Constructing main window.");
        InitializeComponent();

        _appState = new WindowsAppState(new JsonAppDataStore());
        AppDiagnostics.Write("Local application data loaded.");
        DataContext = _appState;
        StartWithWindowsCheckBox.IsChecked = _startupService.IsEnabled();

        _coordinator = new VoiceInputCoordinator(
            new NAudioCaptureService(),
            new QwenRealtimeService(),
            _credentialStore,
            new WindowsTextInsertionService(),
            _appState.CreateTranscriptionOptions);
        _coordinator.StateChanged += CoordinatorOnStateChanged;
        _coordinator.SessionCompleted += CoordinatorOnSessionCompleted;
        _coordinator.PreviewChanged += (_, text) => Dispatcher.InvokeAsync(() => _floating.SetPreview(text));
        _coordinator.AudioLevelChanged += (_, e) => Dispatcher.InvokeAsync(() => _floating.SetLevel(e.Level));
        _hotkey.Triggered += async (_, _) => await ToggleAsync();

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = SystemIcons.Information,
            Text = "Noboard 语音输入",
            Visible = true,
            ContextMenuStrip = BuildTrayMenu()
        };
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowFromExternalActivation);
        SourceInitialized += OnSourceInitialized;
        Closing += OnClosing;
        RefreshCredentialStatus();
        PopulatePromptEditor();
        AppDiagnostics.Write("Main window construction completed.");
    }

    private Forms.ContextMenuStrip BuildTrayMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开 Noboard", null, (_, _) => Dispatcher.Invoke(ShowFromExternalActivation));
        menu.Items.Add("开始 / 停止录音", null, async (_, _) =>
        {
            await Dispatcher.InvokeAsync(() =>
            {
                if (_coordinator.State is VoiceSessionState.Idle or VoiceSessionState.Error)
                    ShowFromExternalActivation();
            });
            await Dispatcher.InvokeAsync(ToggleAsync);
        });
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Dispatcher.Invoke(RequestExit));
        return menu;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        _windowSource = HwndSource.FromHwnd(handle);
        _windowSource.AddHook(WindowProcedure);
        try
        {
            _hotkey.Register(handle);
        }
        catch (Exception ex)
        {
            StateMessage.Text = ex.Message;
        }
    }

    private IntPtr WindowProcedure(
        IntPtr hwnd,
        int message,
        IntPtr wParam,
        IntPtr lParam,
        ref bool handled)
    {
        handled = _hotkey.HandleMessage(message, wParam);
        return IntPtr.Zero;
    }

    private async void ToggleVoiceInput(object sender, RoutedEventArgs e) => await ToggleAsync();

    private async Task ToggleAsync()
    {
        if ((_coordinator.State is VoiceSessionState.Idle or VoiceSessionState.Error) && IsActive)
        {
            Hide();
            await Task.Delay(150);
        }

        await _coordinator.ToggleAsync();
    }

    private void CoordinatorOnStateChanged(object? sender, VoiceStateChangedEventArgs e) =>
        Dispatcher.InvokeAsync(() =>
        {
            StateTitle.Text = StateLabel(e.State);
            StateMessage.Text = e.Message;
            ToggleButton.Content = e.State == VoiceSessionState.Recording ? "停止录音" : "开始录音";
            ToggleButton.IsEnabled =
                e.State is VoiceSessionState.Idle or VoiceSessionState.Error or VoiceSessionState.Recording;

            if (e.State != VoiceSessionState.Inserting)
                _floating.UpdateState(e.State, e.Message);

            if (e.State is VoiceSessionState.Recording or VoiceSessionState.Transcribing or VoiceSessionState.Finalizing)
            {
                _floating.ShowWithoutActivation();
            }
            else if (e.State == VoiceSessionState.Idle)
            {
                if (e.Message == "已输入")
                    _floating.Hide();
                else
                    _floating.ShowTemporary(TimeSpan.FromSeconds(3));
            }
            else if (e.State == VoiceSessionState.Error)
            {
                _floating.ShowTemporary(TimeSpan.FromSeconds(3));
            }
        });

    private void CoordinatorOnSessionCompleted(object? sender, VoiceSessionCompletedEventArgs e) =>
        Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                await _appState.RecordSessionAsync(e.Item);
            }
            catch (Exception ex)
            {
                StateMessage.Text = $"文字已生成，但历史记录保存失败：{ex.Message}";
            }
        });

    private static string StateLabel(VoiceSessionState state) => state switch
    {
        VoiceSessionState.Idle => "待机",
        VoiceSessionState.Recording => "正在聆听",
        VoiceSessionState.Transcribing => "正在转写",
        VoiceSessionState.Finalizing => "正在整理",
        VoiceSessionState.Inserting => "正在写入",
        VoiceSessionState.Error => "需要处理",
        _ => state.ToString()
    };

    private void ShowHome(object sender, RoutedEventArgs e) => ShowPage(HomePanel);
    private void ShowHistory(object sender, RoutedEventArgs e) => ShowPage(HistoryPanel);
    private void ShowDictionary(object sender, RoutedEventArgs e) => ShowPage(DictionaryPanel);

    private void ShowExpressions(object sender, RoutedEventArgs e)
    {
        ShowPage(ExpressionsPanel);
        PopulatePromptEditor();
    }

    private void ShowVoiceModels(object sender, RoutedEventArgs e)
    {
        ShowPage(VoiceModelPanel);
        RefreshCredentialStatus();
    }

    private void ShowGeneralSettings(object sender, RoutedEventArgs e)
    {
        StartWithWindowsCheckBox.IsChecked = _startupService.IsEnabled();
        ShowPage(GeneralSettingsPanel);
    }

    private void ShowAbout(object sender, RoutedEventArgs e) => ShowPage(AboutPanel);

    private void ShowPage(FrameworkElement page)
    {
        foreach (var candidate in new FrameworkElement[]
                 {
                     HomePanel,
                     HistoryPanel,
                     DictionaryPanel,
                     ExpressionsPanel,
                     VoiceModelPanel,
                     GeneralSettingsPanel,
                     AboutPanel
                 })
        {
            candidate.Visibility = candidate == page ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void CopySelectedHistory(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedHistoryItem is not { } item) return;
        System.Windows.Clipboard.SetText(item.Text);
        StateMessage.Text = "所选历史记录已复制。";
    }

    private async void DeleteSelectedHistory(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedHistoryItem is not { } item) return;
        await RunDataActionAsync(() => _appState.DeleteHistoryAsync(item));
    }

    private async void ClearAllHistory(object sender, RoutedEventArgs e)
    {
        if (_appState.HistoryItems.Count == 0) return;
        if (System.Windows.MessageBox.Show(
                "确定清空全部历史记录吗？此操作无法撤销。",
                "清空历史记录",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        await RunDataActionAsync(_appState.ClearHistoryAsync);
    }

    private void DictionarySelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (DictionaryGrid.SelectedItem is not DictionaryEntry entry) return;
        _editingDictionaryEntry = entry;
        DictionaryTermBox.Text = entry.Term;
        DictionaryPronunciationBox.Text = entry.Pronunciation;
        DictionaryReplacementBox.Text = entry.Replacement;
    }

    private void NewDictionaryEntry(object sender, RoutedEventArgs e)
    {
        _editingDictionaryEntry = null;
        DictionaryGrid.SelectedItem = null;
        DictionaryTermBox.Clear();
        DictionaryPronunciationBox.Clear();
        DictionaryReplacementBox.Clear();
        DictionaryTermBox.Focus();
    }

    private async void SaveDictionaryEntry(object sender, RoutedEventArgs e)
    {
        var term = DictionaryTermBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(term))
        {
            System.Windows.MessageBox.Show(
                "请先填写词条。",
                "个人词典",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        var entry = (_editingDictionaryEntry ?? new DictionaryEntry()) with
        {
            Term = term,
            Pronunciation = DictionaryPronunciationBox.Text.Trim(),
            Replacement = DictionaryReplacementBox.Text.Trim()
        };
        await RunDataActionAsync(() => _appState.SaveDictionaryEntryAsync(entry));
        _editingDictionaryEntry = entry;
    }

    private async void DeleteDictionaryEntry(object sender, RoutedEventArgs e)
    {
        var entry = DictionaryGrid.SelectedItem as DictionaryEntry ?? _editingDictionaryEntry;
        if (entry is null) return;
        await RunDataActionAsync(() => _appState.DeleteDictionaryEntryAsync(entry));
        NewDictionaryEntry(sender, e);
    }

    private void PromptProfileSelectionChanged(object sender, SelectionChangedEventArgs e) =>
        PopulatePromptEditor();

    private void PopulatePromptEditor()
    {
        var profile = _appState.SelectedPromptProfile;
        if (profile is null) return;
        PromptNameBox.Text = profile.Name;
        PromptInstructionsBox.Text = profile.Instructions;
    }

    private async void ActivatePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(() => _appState.ActivatePromptProfileAsync(profile));
    }

    private async void DuplicatePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(async () =>
        {
            await _appState.DuplicatePromptProfileAsync(profile);
            PopulatePromptEditor();
        });
    }

    private async void NewPromptProfile(object sender, RoutedEventArgs e)
    {
        await RunDataActionAsync(async () =>
        {
            await _appState.CreatePromptProfileAsync("自定义表达", VoiceInputPrompt.Default);
            PopulatePromptEditor();
        });
    }

    private async void SavePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(async () =>
        {
            await _appState.UpdatePromptProfileAsync(
                profile,
                PromptNameBox.Text,
                PromptInstructionsBox.Text);
            PopulatePromptEditor();
        });
    }

    private async void DeletePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(async () =>
        {
            await _appState.DeletePromptProfileAsync(profile);
            PopulatePromptEditor();
        });
    }

    private void SaveCredentials(object sender, RoutedEventArgs e)
    {
        try
        {
            _credentialStore.Save(new VoiceCredentials(ApiKeyBox.Password));
            ApiKeyBox.Clear();
            RefreshCredentialStatus();
        }
        catch (Exception ex)
        {
            CredentialStatus.Text = ex.Message;
        }
    }

    private void DeleteCredentials(object sender, RoutedEventArgs e)
    {
        try
        {
            _credentialStore.Delete();
            ApiKeyBox.Clear();
            RefreshCredentialStatus();
        }
        catch (Exception ex)
        {
            CredentialStatus.Text = ex.Message;
        }
    }

    private async void TestConnection(object sender, RoutedEventArgs e)
    {
        TestConnectionButton.IsEnabled = false;
        CredentialStatus.Text = "正在测试连接；不会打开麦克风或发送音频。";
        try
        {
            await _coordinator.TestConnectionAsync();
            CredentialStatus.Text = "连接成功。";
        }
        catch (Exception ex)
        {
            CredentialStatus.Text = ex.Message;
        }
        finally
        {
            TestConnectionButton.IsEnabled = true;
        }
    }

    private void RefreshCredentialStatus()
    {
        try
        {
            var saved = _credentialStore.Read();
            var ready = saved?.IsValid == true;
            CredentialStatus.Text = ready
                ? "API Key 已安全保存在 Windows 凭据管理器。"
                : "尚未保存 API Key。";
            SidebarReadiness.Text = ready ? "● 已就绪" : "● 需要 API Key";
            SidebarReadiness.Foreground = ready
                ? System.Windows.Media.Brushes.LightGreen
                : System.Windows.Media.Brushes.Gold;
        }
        catch (Exception ex)
        {
            CredentialStatus.Text = ex.Message;
            SidebarReadiness.Text = "● 凭据读取失败";
        }
    }

    private async void SaveGeneralSettings(object sender, RoutedEventArgs e)
    {
        try
        {
            var startWithWindows = StartWithWindowsCheckBox.IsChecked == true;
            _startupService.SetEnabled(startWithWindows);
            await _appState.UpdatePreferencesAsync(_appState.Preferences with
            {
                StartWithWindows = startWithWindows
            });
            StateMessage.Text = "设置已保存。";
        }
        catch (Exception ex)
        {
            StartWithWindowsCheckBox.IsChecked = _startupService.IsEnabled();
            System.Windows.MessageBox.Show(
                ex.Message,
                "无法保存设置",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private void OpenDataFolder(object sender, RoutedEventArgs e)
    {
        var dataPath = _appState.DataFilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(dataPath)!);
        if (!File.Exists(dataPath))
        {
            _ = RunDataActionAsync(() => _appState.UpdatePreferencesAsync(_appState.Preferences));
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = File.Exists(dataPath)
                ? $"/select,\"{dataPath}\""
                : $"\"{Path.GetDirectoryName(dataPath)}\"",
            UseShellExecute = true
        });
    }

    private void OpenDiagnosticsLog(object sender, RoutedEventArgs e)
    {
        AppDiagnostics.Write("Diagnostics log opened by the user.");
        Process.Start(new ProcessStartInfo
        {
            FileName = AppDiagnostics.LogFilePath,
            UseShellExecute = true
        });
    }

    private async void ResetAllData(object sender, RoutedEventArgs e)
    {
        if (System.Windows.MessageBox.Show(
                "确定恢复默认本地数据吗？历史、词典和自定义表达方式都会被清空，API Key 不受影响。",
                "恢复默认数据",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        await RunDataActionAsync(async () =>
        {
            await _appState.ResetAllDataAsync();
            PopulatePromptEditor();
        });
    }

    private void OpenGitHub(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://github.com/jiangbo-wang/akang-ai-voice-input",
            UseShellExecute = true
        });

    private async Task RunDataActionAsync(Func<Task> action)
    {
        try
        {
            await action();
            StateMessage.Text = _appState.LastDataStatus;
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show(
                ex.Message,
                "操作失败",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_exitRequested) return;
        e.Cancel = true;
        Hide();
        _trayIcon.ShowBalloonTip(
            1500,
            "Noboard 仍在运行",
            "按 Ctrl+Alt+Space 可随时开始语音输入。",
            Forms.ToolTipIcon.Info);
    }

    public void ShowFromExternalActivation()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true;
        Topmost = false;
    }

    private void RequestExit()
    {
        _exitRequested = true;
        Close();
        System.Windows.Application.Current.Shutdown();
    }

    public async ValueTask DisposeAsync()
    {
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _windowSource?.RemoveHook(WindowProcedure);
        _hotkey.Dispose();
        _floating.Close();
        await _coordinator.DisposeAsync();
    }
}
