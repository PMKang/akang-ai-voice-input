using System.Collections;
using System.Windows;
using System.Windows.Media;
using AkangVoiceInput.Core;
using MediaBrush = System.Windows.Media.Brush;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using MediaPen = System.Windows.Media.Pen;
using WpfPoint = System.Windows.Point;

namespace AkangVoiceInput.App;

public sealed class RecognitionTrendControl : FrameworkElement
{
    public static readonly DependencyProperty ItemsSourceProperty = DependencyProperty.Register(
        nameof(ItemsSource),
        typeof(IEnumerable),
        typeof(RecognitionTrendControl),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public IEnumerable? ItemsSource
    {
        get => (IEnumerable?)GetValue(ItemsSourceProperty);
        set => SetValue(ItemsSourceProperty, value);
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var width = Math.Max(0, ActualWidth);
        var height = Math.Max(0, ActualHeight);
        if (width < 10 || height < 10) return;

        var gridPen = new MediaPen(new SolidColorBrush(MediaColor.FromRgb(225, 228, 233)), 1)
        {
            DashStyle = new DashStyle([3d, 3d], 0)
        };
        gridPen.Freeze();
        foreach (var fraction in new[] { 0d, .5d, 1d })
        {
            var y = Math.Round(height * fraction) + .5;
            dc.DrawLine(gridPen, new WpfPoint(0, y), new WpfPoint(width, y));
        }

        var activities = ItemsSource?.Cast<object>().OfType<DailyUsage>().ToList() ?? [];
        var active = activities.Where(item => item.Sessions > 0 && item.ProcessingSeconds > 0).ToList();
        if (active.Count == 0)
        {
            var text = new FormattedText(
                "暂无趋势 · 积累更多使用记录后展示",
                System.Globalization.CultureInfo.CurrentUICulture,
                System.Windows.FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                12,
                MediaBrushes.Gray,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new WpfPoint(Math.Max(0, (width - text.Width) / 2), Math.Max(0, (height - text.Height) / 2)));
            return;
        }

        var maximum = Math.Max(1.2, active.Max(item => item.ProcessingSeconds / item.Sessions) * 1.15);
        var accent = (MediaBrush)(TryFindResource("AccentBrush") ?? MediaBrushes.DodgerBlue);
        var linePen = new MediaPen(accent, 1.8);
        WpfPoint? previous = null;
        for (var i = 0; i < activities.Count; i++)
        {
            var activity = activities[i];
            if (activity.Sessions <= 0 || activity.ProcessingSeconds <= 0)
            {
                previous = null;
                continue;
            }
            var average = activity.ProcessingSeconds / activity.Sessions;
            var x = activities.Count == 1 ? width / 2 : width * i / (activities.Count - 1d);
            var y = height * (1 - Math.Min(average / maximum, 1));
            var point = new WpfPoint(x, y);
            if (previous is { } prior) dc.DrawLine(linePen, prior, point);
            dc.DrawEllipse(accent, null, point, 2.6, 2.6);
            previous = point;
        }
    }
}
