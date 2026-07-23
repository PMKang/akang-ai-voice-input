using System.Windows;
using System.Windows.Media;
using MediaBrush = System.Windows.Media.Brush;
using MediaColor = System.Windows.Media.Color;
using MediaColorConverter = System.Windows.Media.ColorConverter;
using MediaSolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace AkangVoiceInput.App;

internal sealed class LiveWaveformControl : FrameworkElement
{
    private const int BarCount = 48;
    private static readonly MediaBrush Accent = Frozen("#1685F8");

    public static readonly DependencyProperty LevelProperty = DependencyProperty.Register(
        nameof(Level),
        typeof(double),
        typeof(LiveWaveformControl),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public LiveWaveformControl()
    {
        Loaded += (_, _) => CompositionTarget.Rendering += OnRendering;
        Unloaded += (_, _) => CompositionTarget.Rendering -= OnRendering;
    }

    public double Level
    {
        get => (double)GetValue(LevelProperty);
        set => SetValue(LevelProperty, Math.Clamp(value, 0, 1));
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth <= 0 || ActualHeight <= 0) return;

        const double barWidth = 4;
        var spacing = Math.Max(2, (ActualWidth - BarCount * barWidth) / (BarCount - 1));
        var now = DateTimeOffset.Now.TimeOfDay.TotalSeconds;
        var gated = Math.Max(0, (Level - 0.015) / 0.985);
        var visible = Math.Pow(gated, 0.34);
        var movement = 0.15 + visible * 0.85;

        for (var index = 0; index < BarCount; index++)
        {
            var wave = Math.Abs(Math.Sin(now * (2 + movement * 5.2) + index * 0.62));
            var envelope = 0.55 + 0.45 * Math.Abs(Math.Sin(index / (double)BarCount * Math.PI));
            var amplitude = visible * (7 + wave * envelope * 22);
            var height = Math.Min(30, 3 + amplitude);
            var x = index * (barWidth + spacing);
            var y = (ActualHeight - height) / 2;
            drawingContext.DrawRoundedRectangle(
                Accent,
                null,
                new Rect(x, y, barWidth, height),
                barWidth / 2,
                barWidth / 2);
        }
    }

    private void OnRendering(object? sender, EventArgs e) => InvalidateVisual();

    private static MediaBrush Frozen(string color)
    {
        var brush = new MediaSolidColorBrush((MediaColor)MediaColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }
}
