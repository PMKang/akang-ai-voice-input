using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AkangVoiceInput.Core;
using AkangVoiceInput.Platform;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfRadioButton = System.Windows.Controls.RadioButton;

namespace AkangVoiceInput.App;

public partial class ShortcutSettingsDialog : Window
{
    private readonly ShortcutBinding _initialShortcut;
    private readonly ShortcutCaptureService _captureService = new();
    private ShortcutBinding? _candidate;
    private bool _initializing = true;

    public ShortcutSettingsDialog(ShortcutBinding currentShortcut)
    {
        _initialShortcut = currentShortcut;
        InitializeComponent();
        SelectInitialChoice();
        _initializing = false;
        UpdateCandidateVisual();
        Activated += (_, _) => Keyboard.Focus(this);
        SourceInitialized += (_, _) =>
        {
            _captureService.KeyChanged += CaptureServiceOnKeyChanged;
            _captureService.Start();
        };
        Closed += (_, _) =>
        {
            _captureService.KeyChanged -= CaptureServiceOnKeyChanged;
            _captureService.Dispose();
        };
    }

    public ShortcutBinding? SelectedShortcut { get; private set; }

    private void SelectInitialChoice()
    {
        if (_initialShortcut == ShortcutBinding.LeftAlt)
        {
            LeftAltChoice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.F2)
        {
            F2Choice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.RightAlt)
        {
            RightAltChoice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.ParseLegacy("Ctrl+Alt+Space"))
        {
            LegacyChoice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.ParseLegacy("Ctrl+Shift+Space"))
        {
            ControlShiftSpaceChoice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.ParseLegacy("Alt+Shift+Space"))
        {
            AltShiftSpaceChoice.IsChecked = true;
        }
        else if (_initialShortcut == ShortcutBinding.ParseLegacy("Ctrl+Alt+V"))
        {
            ControlAltVChoice.IsChecked = true;
        }
        else
        {
            _candidate = _initialShortcut;
            CustomChoice.IsChecked = true;
        }
    }

    private void PresetChecked(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfRadioButton { Tag: string preset }) return;

        _candidate = ShortcutBinding.ParseLegacy(preset);
        if (CapturePanel is not null) CapturePanel.Visibility = Visibility.Collapsed;
        if (!_initializing) UpdateCandidateVisual();
    }

    private void CustomChecked(object sender, RoutedEventArgs e)
    {
        if (CapturePanel is null) return;

        CapturePanel.Visibility = Visibility.Visible;
        if (!_initializing && IsPreset(_candidate))
        {
            _candidate = null;
        }
        UpdateCandidateVisual();
        Focus();
    }

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape)
        {
            DialogResult = false;
            e.Handled = true;
            return;
        }

        if (CustomChoice.IsChecked == true) e.Handled = true;
    }

    private void CaptureServiceOnKeyChanged(object? sender, ShortcutCaptureEvent e)
    {
        if (CustomChoice.IsChecked != true) return;

        if (e.WindowsKeyDown)
        {
            _candidate = null;
            CapturedShortcutText.Text = "Windows + …";
            ValidationText.Text = "暂不支持 Windows 键组合，请使用 Ctrl、Alt 或 Shift。";
            ValidationText.Foreground = WpfBrushes.Firebrick;
            UseShortcutButton.IsEnabled = false;
            return;
        }

        if (e.VirtualKey is null)
        {
            CapturedShortcutText.Text = ModifierPrompt(e.Modifiers);
            ValidationText.Text = "请再按一个字母、数字、空格键或功能键";
            ValidationText.Foreground = WpfBrushes.Gray;
            UseShortcutButton.IsEnabled = false;
            return;
        }

        if (e.VirtualKey == 0x1B)
        {
            DialogResult = false;
            return;
        }

        if (e.VirtualKey == 0x08 && e.Modifiers == ShortcutModifiers.None)
        {
            _candidate = null;
            UpdateCandidateVisual();
            return;
        }

        _candidate = ShortcutBinding.Custom(e.Modifiers, e.VirtualKey.Value);
        UpdateCandidateVisual();
    }

    private void UpdateCandidateVisual()
    {
        if (_candidate is null)
        {
            if (CapturedShortcutText is not null) CapturedShortcutText.Text = "等待按键…";
            if (ValidationText is not null)
            {
                ValidationText.Text = "组合键需要包含主键；F2–F12 可以单独使用";
                ValidationText.Foreground = (WpfBrush)FindResource("SecondaryTextBrush");
            }
            if (UseShortcutButton is not null) UseShortcutButton.IsEnabled = false;
            return;
        }

        var validation = _candidate.Validate();
        if (CapturedShortcutText is not null)
            CapturedShortcutText.Text = _candidate.DisplayText;
        if (ValidationText is not null)
        {
            ValidationText.Text = validation.Message;
            ValidationText.Foreground = validation.IsValid
                ? validation.IsWarning
                    ? WpfBrushes.DarkOrange
                    : (WpfBrush)FindResource("AccentBrush")
                : WpfBrushes.Firebrick;
        }
        if (UseShortcutButton is not null)
            UseShortcutButton.IsEnabled = validation.IsValid;
    }

    private void UseShortcut(object sender, RoutedEventArgs e)
    {
        if (_candidate is null || !_candidate.Validate().IsValid) return;
        SelectedShortcut = _candidate;
        DialogResult = true;
    }

    private void CancelDialog(object sender, RoutedEventArgs e) => DialogResult = false;

    private void DragWindow(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private static bool IsPreset(ShortcutBinding? shortcut) =>
        shortcut is not null
        && (shortcut == ShortcutBinding.LeftAlt
            || shortcut == ShortcutBinding.RightAlt
            || shortcut == ShortcutBinding.F2
            || shortcut == ShortcutBinding.ParseLegacy("Ctrl+Alt+Space")
            || shortcut == ShortcutBinding.ParseLegacy("Ctrl+Shift+Space")
            || shortcut == ShortcutBinding.ParseLegacy("Alt+Shift+Space")
            || shortcut == ShortcutBinding.ParseLegacy("Ctrl+Alt+V"));

    private static string ModifierPrompt(ShortcutModifiers modifiers)
    {
        var parts = new List<string>();
        if (modifiers.HasFlag(ShortcutModifiers.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(ShortcutModifiers.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(ShortcutModifiers.Shift)) parts.Add("Shift");
        return parts.Count == 0 ? "等待按键…" : string.Join(" + ", parts) + " + …";
    }
}
