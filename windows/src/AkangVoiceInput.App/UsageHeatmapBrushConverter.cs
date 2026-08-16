using System.Globalization;
using System.Windows.Data;
using System.Windows;
using MediaBrush = System.Windows.Media.Brush;
using MediaColor = System.Windows.Media.Color;
using MediaColorConverter = System.Windows.Media.ColorConverter;
using MediaSolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace AkangVoiceInput.App;

internal sealed class UsageHeatmapBrushConverter : IValueConverter
{
    private static readonly MediaBrush Empty = Frozen("#F3F4F6");
    private static readonly MediaBrush Low = Frozen("#DCEBFF");
    private static readonly MediaBrush Medium = Frozen("#A9CDFB");
    private static readonly MediaBrush High = Frozen("#6CA7F8");
    private static readonly MediaBrush Peak = Frozen("#1685F8");

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var characters = value is int count ? count : 0;
        return characters switch
        {
            <= 0 => Empty,
            < 100 => Low,
            < 500 => Medium,
            < 1500 => High,
            _ => Peak
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        System.Windows.Data.Binding.DoNothing;

    private static MediaBrush Frozen(string color)
    {
        var brush = new MediaSolidColorBrush((MediaColor)MediaColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }
}

internal sealed class PromptProfileSummaryConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        (value as string) switch
        {
            "智能整理" => "去除口语冗余，补足标点与段落；适合大多数日常输入。",
            "原声直达" => "忠实保留原有措辞和语气，只进行必要的断句整理。",
            "清晰表达" => "把零散口述组织成自然完整、读者容易理解的日常表达。",
            "正式成文" => "转换为完整、克制、礼貌的书面表达，适合邮件和正式沟通。",
            "要点速记" => "提炼结论、事项和待办，用清晰要点快速呈现。",
            _ => "这是本机保存的自定义规则，可按你的偏好随时调整。"
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        System.Windows.Data.Binding.DoNothing;
}

internal sealed class PromptProfileIsActiveConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        if (values.Length < 2) return false;
        if (values[0] is Guid profileId && values[1] is Guid activeId) return profileId == activeId;
        return string.Equals(values[0]?.ToString(), values[1]?.ToString(), StringComparison.Ordinal);
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        targetTypes.Select(_ => System.Windows.Data.Binding.DoNothing).ToArray();
}

internal sealed class EmptyStringVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        string.IsNullOrEmpty(value as string) ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        System.Windows.Data.Binding.DoNothing;
}
