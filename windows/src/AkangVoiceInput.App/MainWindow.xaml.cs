using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using AkangVoiceInput.App.Platform;
using AkangVoiceInput.Audio;
using AkangVoiceInput.Core;
using AkangVoiceInput.Platform;
using AkangVoiceInput.Transcription;
using Forms = System.Windows.Forms;
using WpfButton = System.Windows.Controls.Button;
using WpfRadioButton = System.Windows.Controls.RadioButton;
using WpfBitmapImage = System.Windows.Media.Imaging.BitmapImage;
using WpfSolidColorBrush = System.Windows.Media.SolidColorBrush;
using DrawingIcon = System.Drawing.Icon;

namespace AkangVoiceInput.App;

public partial class MainWindow : Window, IAsyncDisposable
{
    private readonly WindowsCredentialStore _bailianCredentialStore = new();
    private readonly WindowsCredentialStore _doubaoCredentialStore = new("AkangVoiceInput/DoubaoRealtime");
    private readonly ProviderCredentialStore _credentialStore;
    private readonly WindowsStartupService _startupService = new();
    private readonly WindowsUpdateService _updateService = new();
    private readonly GlobalHotkeyService _hotkey = new();
    private readonly WindowsAppState _appState;
    private readonly VoiceInputCoordinator _coordinator;
    private readonly FloatingStatusWindow _floating = new();
    private readonly Forms.NotifyIcon _trayIcon;
    private DrawingIcon? _trayManagedIcon;
    private HwndSource? _windowSource;
    private DictionaryEntry? _editingDictionaryEntry;
    private bool _exitRequested;
    private bool _updateCheckedThisRun;
    private bool _updateBusy;
    private WindowsReleaseInfo? _availableUpdate;
    private PreparedWindowsUpdate? _preparedUpdate;

    public MainWindow()
    {
        AppDiagnostics.Write("Constructing main window.");
        InitializeComponent();

        _appState = new WindowsAppState(new JsonAppDataStore());
        _credentialStore = new ProviderCredentialStore(
            _bailianCredentialStore,
            _doubaoCredentialStore,
            () => _appState.Preferences.ActiveVoiceModelId);
        AppDiagnostics.Write("Local application data loaded.");
        DataContext = _appState;
        StartWithWindowsCheckBox.IsChecked = _startupService.IsEnabled();
        _floating.SetDisplayName(_appState.Preferences.ChineseDisplayName);

        _coordinator = new VoiceInputCoordinator(
            new NAudioCaptureService(),
            new ProviderTranscriptionService(),
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
            Text = "Noboard 语音输入",
            Visible = false,
            ContextMenuStrip = BuildTrayMenu()
        };
        ApplyIconTheme(_appState.Preferences.IconTheme);
        _trayIcon.Visible = true;
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowFromExternalActivation);
        SourceInitialized += OnSourceInitialized;
        Closing += OnClosing;
        RefreshCredentialStatus();
        UpdateModelSelectionVisual();
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
            _hotkey.Register(handle, _appState.Preferences.Shortcut);
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
            ToggleButtonText.Text = e.State == VoiceSessionState.Recording ? "停止录音" : "开始录音";
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

    private void ShowHome(object sender, RoutedEventArgs e) => ShowPage(HomePanel, HomeNavButton);
    private void ShowHistory(object sender, RoutedEventArgs e) => ShowPage(HistoryPanel, HistoryNavButton);
    private void ShowDictionary(object sender, RoutedEventArgs e) => ShowPage(DictionaryPanel, DictionaryNavButton);

    private void ShowExpressions(object sender, RoutedEventArgs e)
    {
        ShowPage(ExpressionsPanel, ExpressionsNavButton);
        PopulatePromptEditor();
    }

    private void ShowVoiceModels(object sender, RoutedEventArgs e)
    {
        ShowPage(VoiceModelPanel, VoiceModelsNavButton);
        RefreshCredentialStatus();
    }

    private void ShowGeneralSettings(object sender, RoutedEventArgs e)
    {
        StartWithWindowsCheckBox.IsChecked = _startupService.IsEnabled();
        ShowPage(GeneralSettingsPanel, SettingsNavButton);
    }

    private async void ShowAbout(object sender, RoutedEventArgs e)
    {
        ShowPage(AboutPanel, AboutNavButton);
        if (!_updateCheckedThisRun)
            await CheckForUpdatesAsync();
    }

    private void DashboardScopeChecked(object sender, RoutedEventArgs e)
    {
        if (_appState is null || sender is not WpfRadioButton { Tag: string scope }) return;
        _appState.DashboardUsageScope = scope;
    }

    private void ShowPage(FrameworkElement page, WpfButton navigationButton)
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

        foreach (var button in new[]
                 {
                     HomeNavButton,
                     HistoryNavButton,
                     DictionaryNavButton,
                     ExpressionsNavButton,
                     VoiceModelsNavButton,
                     SettingsNavButton,
                     AboutNavButton
                 })
        {
            button.Tag = ReferenceEquals(button, navigationButton) ? "Selected" : null;
            if (button.Content is StackPanel panel &&
                panel.Children.OfType<TextBlock>().LastOrDefault() is { } label)
            {
                label.FontWeight = ReferenceEquals(button, navigationButton)
                    ? FontWeights.SemiBold
                    : FontWeights.Normal;
            }
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
        DictionaryEditorOverlay.Visibility = Visibility.Visible;
    }

    private void HistoryRangeChecked(object sender, RoutedEventArgs e)
    {
        if (_appState is null || sender is not WpfRadioButton { Tag: string value }) return;
        if (int.TryParse(value, out var index)) _appState.HistoryRangeIndex = index;
    }

    private void NewDictionaryEntry(object sender, RoutedEventArgs e)
    {
        _editingDictionaryEntry = null;
        DictionaryGrid.SelectedItem = null;
        DictionaryTermBox.Clear();
        DictionaryPronunciationBox.Clear();
        DictionaryReplacementBox.Clear();
        DictionaryEditorOverlay.Visibility = Visibility.Visible;
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
        DictionaryEditorOverlay.Visibility = Visibility.Collapsed;
    }

    private async void DeleteDictionaryEntry(object sender, RoutedEventArgs e)
    {
        var entry = DictionaryGrid.SelectedItem as DictionaryEntry ?? _editingDictionaryEntry;
        if (entry is null) return;
        await RunDataActionAsync(() => _appState.DeleteDictionaryEntryAsync(entry));
        _editingDictionaryEntry = null;
        DictionaryGrid.SelectedItem = null;
        DictionaryEditorOverlay.Visibility = Visibility.Collapsed;
    }

    private void CancelDictionaryEditor(object sender, RoutedEventArgs e)
    {
        DictionaryEditorOverlay.Visibility = Visibility.Collapsed;
        DictionaryGrid.SelectedItem = null;
        _editingDictionaryEntry = null;
    }

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
        PromptEditorOverlay.Visibility = Visibility.Collapsed;
    }

    private async void ActivatePromptProfileFromCard(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { CommandParameter: PromptProfile profile }) return;
        _appState.SelectedPromptProfile = profile;
        await RunDataActionAsync(() => _appState.ActivatePromptProfileAsync(profile));
    }

    private void InspectPromptProfileFromCard(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { CommandParameter: PromptProfile profile }) return;
        _appState.SelectedPromptProfile = profile;
        PopulatePromptEditor();
        PromptEditorOverlay.Visibility = Visibility.Visible;
    }

    private async void DuplicatePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(async () =>
        {
            await _appState.DuplicatePromptProfileAsync(profile);
            PopulatePromptEditor();
            PromptEditorOverlay.Visibility = Visibility.Visible;
        });
    }

    private async void NewPromptProfile(object sender, RoutedEventArgs e)
    {
        await RunDataActionAsync(async () =>
        {
            await _appState.CreatePromptProfileAsync("自定义表达", VoiceInputPrompt.Default);
            PopulatePromptEditor();
            PromptEditorOverlay.Visibility = Visibility.Visible;
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
            PromptEditorOverlay.Visibility = Visibility.Collapsed;
        });
    }

    private async void DeletePromptProfile(object sender, RoutedEventArgs e)
    {
        if (_appState.SelectedPromptProfile is not { } profile) return;
        await RunDataActionAsync(async () =>
        {
            await _appState.DeletePromptProfileAsync(profile);
            PopulatePromptEditor();
            PromptEditorOverlay.Visibility = Visibility.Collapsed;
        });
    }

    private void CancelPromptEditor(object sender, RoutedEventArgs e) =>
        PromptEditorOverlay.Visibility = Visibility.Collapsed;

    private void SaveCredentials(object sender, RoutedEventArgs e)
    {
        try
        {
            _bailianCredentialStore.Save(new VoiceCredentials(ApiKeyBox.Password));
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
            _bailianCredentialStore.Delete();
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
            var credentials = _bailianCredentialStore.Read()
                ?? throw new InvalidOperationException("请先保存阿里云百炼 API Key。");
            var modelId = TranscriptionOptions.IsDoubao(_appState.Preferences.ActiveVoiceModelId)
                ? TranscriptionOptions.QwenModelId
                : _appState.Preferences.ActiveVoiceModelId;
            await using var service = new QwenRealtimeService();
            await service.TestConnectionAsync(
                credentials,
                new TranscriptionOptions(modelId, VoiceInputPrompt.Default));
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

    private void SaveDoubaoCredentials(object sender, RoutedEventArgs e)
    {
        try
        {
            _doubaoCredentialStore.Save(new VoiceCredentials(DoubaoApiKeyBox.Password));
            DoubaoApiKeyBox.Clear();
            RefreshCredentialStatus();
        }
        catch (Exception ex)
        {
            DoubaoCredentialStatus.Text = ex.Message;
        }
    }

    private void DeleteDoubaoCredentials(object sender, RoutedEventArgs e)
    {
        try
        {
            _doubaoCredentialStore.Delete();
            DoubaoApiKeyBox.Clear();
            RefreshCredentialStatus();
        }
        catch (Exception ex)
        {
            DoubaoCredentialStatus.Text = ex.Message;
        }
    }

    private async void TestDoubaoConnection(object sender, RoutedEventArgs e)
    {
        TestDoubaoConnectionButton.IsEnabled = false;
        DoubaoCredentialStatus.Text = "正在测试豆包连接；不会打开麦克风或发送音频。";
        try
        {
            var credentials = _doubaoCredentialStore.Read()
                ?? throw new InvalidOperationException("请先保存豆包 API Key。");
            await using var service = new DoubaoRealtimeService();
            await service.TestConnectionAsync(
                credentials,
                new TranscriptionOptions(TranscriptionOptions.DoubaoModelId, string.Empty));
            DoubaoCredentialStatus.Text = "连接成功。";
        }
        catch (Exception ex)
        {
            DoubaoCredentialStatus.Text = ex.Message;
        }
        finally
        {
            TestDoubaoConnectionButton.IsEnabled = true;
        }
    }

    private async void SelectVoiceModel(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { Tag: string modelId } ||
            !VoiceModelCatalog.All.Any(option => option.Id == modelId)) return;
        await RunDataActionAsync(() => _appState.UpdatePreferencesAsync(
            _appState.Preferences with { ActiveVoiceModelId = modelId }));
        UpdateModelSelectionVisual();
        RefreshCredentialStatus();
    }

    private void UpdateModelSelectionVisual()
    {
        var activeId = _appState.Preferences.ActiveVoiceModelId;
        var accent = (System.Windows.Media.Brush)FindResource("AccentBrush");
        var soft = (System.Windows.Media.Brush)FindResource("AccentSoftBrush");
        var normalBackground = new WpfSolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#F7F7F8"));
        var normalBorder = new WpfSolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#D6D8DC"));
        foreach (var (id, button, indicator) in new[]
                 {
                     (TranscriptionOptions.QwenModelId, QwenFlashModelButton, QwenFlashModelIndicator),
                     (TranscriptionOptions.QwenPlusModelId, QwenPlusModelButton, QwenPlusModelIndicator),
                     (TranscriptionOptions.FunAsrModelId, FunAsrModelButton, FunAsrModelIndicator),
                     (TranscriptionOptions.DoubaoModelId, DoubaoModelButton, DoubaoModelIndicator)
                 })
        {
            var active = id == activeId;
            indicator.Text = active ? "●" : "○";
            button.Background = active ? soft : normalBackground;
            button.BorderBrush = active ? accent : normalBorder;
        }
    }

    private void RefreshCredentialStatus()
    {
        try
        {
            var bailianReady = _bailianCredentialStore.Read()?.IsValid == true;
            var doubaoReady = _doubaoCredentialStore.Read()?.IsValid == true;
            CredentialStatus.Text = bailianReady
                ? "API Key 已安全保存在 Windows 凭据管理器。"
                : "尚未保存阿里云百炼 API Key。";
            DoubaoCredentialStatus.Text = doubaoReady
                ? "API Key 已安全保存在 Windows 凭据管理器。"
                : "尚未保存豆包 API Key。";
            BailianConfiguredBadge.Text = bailianReady ? "已配置" : "未配置";
            DoubaoConfiguredBadge.Text = doubaoReady ? "已配置" : "未配置";
            var ready = TranscriptionOptions.IsDoubao(_appState.Preferences.ActiveVoiceModelId)
                ? doubaoReady : bailianReady;
            SidebarReadiness.Text = ready ? "已就绪" : "需要 API Key";
            var statusBrush = ready
                ? (System.Windows.Media.Brush)FindResource("AccentBrush")
                : System.Windows.Media.Brushes.Gray;
            SidebarReadiness.Foreground = statusBrush;
            SidebarReadinessDot.Fill = statusBrush;
        }
        catch (Exception ex)
        {
            CredentialStatus.Text = ex.Message;
            DoubaoCredentialStatus.Text = ex.Message;
            SidebarReadiness.Text = "凭据读取失败";
            SidebarReadiness.Foreground = System.Windows.Media.Brushes.Gray;
            SidebarReadinessDot.Fill = System.Windows.Media.Brushes.Gray;
        }
    }

    private async void SaveGeneralSettings(object sender, RoutedEventArgs e)
    {
        try
        {
            var startWithWindows = StartWithWindowsCheckBox.IsChecked == true;
            var shortcut = (ShortcutComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString()
                ?? _appState.Preferences.Shortcut;
            if (_windowSource is not null)
                _hotkey.Register(new WindowInteropHelper(this).Handle, shortcut);
            _startupService.SetEnabled(startWithWindows);
            await _appState.UpdatePreferencesAsync(_appState.Preferences with
            {
                StartWithWindows = startWithWindows,
                Shortcut = shortcut
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

    private void OpenMicrophonePrivacySettings(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo
        {
            FileName = "ms-settings:privacy-microphone",
            UseShellExecute = true
        });

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

    private async void SelectIconTheme(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { CommandParameter: string theme }) return;

        ApplyIconTheme(theme);
        await RunDataActionAsync(() => _appState.UpdatePreferencesAsync(
            _appState.Preferences with { IconTheme = theme }));
    }

    private void ApplyIconTheme(string? theme)
    {
        var normalized = theme?.Trim().ToLowerInvariant() switch
        {
            "violet" => "violet",
            "coral" => "coral",
            _ => "sky"
        };

        var (accent, soft, iconFile) = normalized switch
        {
            "violet" => ("#6659E8", "#F5F2FF", "NoboardIconViolet.png"),
            "coral" => ("#F26B5C", "#FFF5F2", "NoboardIconCoral.png"),
            _ => ("#1778FF", "#F0F7FF", "NoboardIconBlue.png")
        };

        System.Windows.Application.Current.Resources["AccentBrush"] =
            new WpfSolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(accent));
        System.Windows.Application.Current.Resources["AccentSoftBrush"] =
            new WpfSolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(soft));

        var source = new WpfBitmapImage(new Uri($"pack://application:,,,/Resources/{iconFile}", UriKind.Absolute));
        SidebarBrandIcon.Source = source;
        TitleBarBrandIcon.Source = source;
        Icon = source;
        _trayManagedIcon?.Dispose();
        _trayManagedIcon = CreateTrayIcon(iconFile);
        _trayIcon.Icon = _trayManagedIcon;
    }

    private static DrawingIcon CreateTrayIcon(string iconFile)
    {
        var resource = System.Windows.Application.GetResourceStream(
            new Uri($"/Resources/{iconFile}", UriKind.Relative))
            ?? throw new InvalidOperationException("无法加载托盘图标资源。");
        using var stream = resource.Stream;
        using var source = new Bitmap(stream);
        using var resized = new Bitmap(source, new System.Drawing.Size(32, 32));
        var handle = resized.GetHicon();
        try
        {
            using var icon = DrawingIcon.FromHandle(handle);
            return (DrawingIcon)icon.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private async void SaveBrandNames(object sender, RoutedEventArgs e)
    {
        var chinese = string.IsNullOrWhiteSpace(ChineseBrandNameBox.Text)
            ? "自在说"
            : ChineseBrandNameBox.Text.Trim();
        var english = string.IsNullOrWhiteSpace(EnglishBrandNameBox.Text)
            ? "No Board"
            : EnglishBrandNameBox.Text.Trim();

        await RunDataActionAsync(() => _appState.UpdatePreferencesAsync(
            _appState.Preferences with
            {
                ChineseDisplayName = chinese,
                EnglishDisplayName = english
            }));
        _floating.SetDisplayName(chinese);
        Title = $"{chinese} · {english}";
    }

    private async void ResetBrandNames(object sender, RoutedEventArgs e)
    {
        ChineseBrandNameBox.Text = "自在说";
        EnglishBrandNameBox.Text = "No Board";
        await RunDataActionAsync(() => _appState.UpdatePreferencesAsync(
            _appState.Preferences with
            {
                ChineseDisplayName = "自在说",
                EnglishDisplayName = "No Board"
            }));
        _floating.SetDisplayName("自在说");
        Title = "自在说 · No Board";
    }

    private async void HandleUpdateAction(object sender, RoutedEventArgs e)
    {
        if (_updateBusy) return;

        if (_preparedUpdate is not null)
        {
            InstallPreparedUpdate();
            return;
        }

        if (_availableUpdate is not null)
        {
            await DownloadUpdateAsync(_availableUpdate);
            return;
        }

        await CheckForUpdatesAsync();
    }

    private async Task CheckForUpdatesAsync()
    {
        SetUpdateBusy(true);
        _updateCheckedThisRun = true;
        _availableUpdate = null;
        _preparedUpdate = null;
        UpdateProgressBar.Visibility = Visibility.Collapsed;
        UpdateStatusText.Text = "正在连接 GitHub 检查更新…";
        UpdateActionButton.Content = "检查中…";

        try
        {
            var release = await _updateService.FetchLatestReleaseAsync();
            if (WindowsUpdateService.IsNewerVersion(release.Version, VersionInfo.ProductVersion))
            {
                _availableUpdate = release;
                UpdateStatusText.Text =
                    $"发现 {release.DisplayVersion} · Windows 安装包 {FormatBytes(release.Archive.Size)}";
                UpdateActionButton.Content = "下载并安装";
            }
            else if (WindowsUpdateService.IsNewerVersion(VersionInfo.ProductVersion, release.Version))
            {
                UpdateStatusText.Text =
                    $"当前 v{VersionInfo.ProductVersion} 高于线上 {release.DisplayVersion}（开发构建）。";
                UpdateActionButton.Content = "重新检查";
            }
            else
            {
                UpdateStatusText.Text = $"已是最新版本（{release.DisplayVersion}）。";
                UpdateActionButton.Content = "重新检查";
            }
        }
        catch (Exception exception)
        {
            AppDiagnostics.Write("Update check failed.", exception);
            UpdateStatusText.Text = $"检查失败：{exception.Message}";
            UpdateActionButton.Content = "重试";
        }
        finally
        {
            SetUpdateBusy(false);
        }
    }

    private async Task DownloadUpdateAsync(WindowsReleaseInfo release)
    {
        SetUpdateBusy(true);
        UpdateProgressBar.Value = 0;
        UpdateProgressBar.Visibility = Visibility.Visible;
        UpdateStatusText.Text = $"正在下载 {release.DisplayVersion}…";
        UpdateActionButton.Content = "下载中…";

        try
        {
            var progress = new Progress<double>(value =>
            {
                var percent = Math.Clamp(value * 100, 0, 100);
                UpdateProgressBar.Value = percent;
                UpdateStatusText.Text = $"正在下载并校验 {release.DisplayVersion} · {percent:0}%";
            });
            _preparedUpdate = await _updateService.DownloadAndPrepareAsync(release, progress);
            UpdateProgressBar.Value = 100;
            UpdateStatusText.Text = $"{release.DisplayVersion} 已下载并通过 SHA256 校验，重启后完成安装。";
            UpdateActionButton.Content = "重启并更新";
        }
        catch (Exception exception)
        {
            AppDiagnostics.Write("Update download failed.", exception);
            _preparedUpdate = null;
            _availableUpdate = release;
            UpdateStatusText.Text = $"下载失败：{exception.Message}";
            UpdateActionButton.Content = "重新下载";
        }
        finally
        {
            SetUpdateBusy(false);
        }
    }

    private void InstallPreparedUpdate()
    {
        if (_preparedUpdate is null) return;
        try
        {
            var processPath = Environment.ProcessPath
                ?? throw new InvalidOperationException("无法确定当前程序路径。");
            _updateService.ScheduleInstallAndRestart(
                _preparedUpdate,
                Environment.ProcessId,
                AppContext.BaseDirectory,
                processPath);
            AppDiagnostics.Write($"Update {_preparedUpdate.Version} scheduled; exiting for installation.");
            UpdateStatusText.Text = "正在退出并安装更新…";
            RequestExit();
        }
        catch (Exception exception)
        {
            AppDiagnostics.Write("Update installation could not start.", exception);
            UpdateStatusText.Text = $"无法安装：{exception.Message}";
            System.Windows.MessageBox.Show(
                exception.Message,
                "无法安装更新",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private void SetUpdateBusy(bool busy)
    {
        _updateBusy = busy;
        UpdateActionButton.IsEnabled = !busy;
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes >= 1024L * 1024L)
            return $"{bytes / (1024d * 1024d):0.0} MB";
        if (bytes >= 1024L)
            return $"{bytes / 1024d:0.0} KB";
        return $"{bytes} B";
    }

    private void OpenGitHub(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://github.com/PMKang/akang-ai-voice-input/releases/latest",
            UseShellExecute = true
        });

    private void OpenMacTieTie(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://github.com/PMKang/Mac-TieTie/releases/latest",
            UseShellExecute = true
        });

    private void MinimizeWindow(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void ToggleMaximizeWindow(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        MaximizeButton.Content = WindowState == WindowState.Maximized ? "\uE923" : "\uE922";
    }

    private void CloseWindow(object sender, RoutedEventArgs e) => Close();

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
            $"按 {_appState.Preferences.Shortcut} 可随时开始语音输入。",
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
        _trayManagedIcon?.Dispose();
        _windowSource?.RemoveHook(WindowProcedure);
        _hotkey.Dispose();
        _floating.Close();
        await _coordinator.DisposeAsync();
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
