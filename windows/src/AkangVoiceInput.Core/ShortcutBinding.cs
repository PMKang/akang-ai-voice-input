using System.Text.Json;
using System.Text.Json.Serialization;

namespace AkangVoiceInput.Core;

[Flags]
public enum ShortcutModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4
}

public enum ShortcutKind
{
    Custom,
    SoloAlt
}

public enum ShortcutSide
{
    None,
    Left,
    Right
}

public sealed record ShortcutValidation(bool IsValid, string Message, bool IsWarning = false)
{
    public static ShortcutValidation Valid() => new(true, "此快捷键可以使用");
    public static ShortcutValidation Warning(string message) => new(true, message, true);
    public static ShortcutValidation Invalid(string message) => new(false, message);
}

[JsonConverter(typeof(ShortcutBindingJsonConverter))]
public sealed record ShortcutBinding
{
    public const int VkSpace = 0x20;
    public const int VkLeftAlt = 0xA4;
    public const int VkRightAlt = 0xA5;
    public const int VkF1 = 0x70;
    public const int VkF12 = 0x7B;

    public ShortcutKind Kind { get; init; } = ShortcutKind.SoloAlt;
    public ShortcutModifiers Modifiers { get; init; }
    public int VirtualKey { get; init; } = VkLeftAlt;
    public ShortcutSide Side { get; init; } = ShortcutSide.Left;

    public static ShortcutBinding LeftAlt { get; } = new();
    public static ShortcutBinding RightAlt { get; } = new()
    {
        VirtualKey = VkRightAlt,
        Side = ShortcutSide.Right
    };

    public static ShortcutBinding F2 { get; } = Custom(ShortcutModifiers.None, VkF1 + 1);

    public static ShortcutBinding Custom(ShortcutModifiers modifiers, int virtualKey) => new()
    {
        Kind = ShortcutKind.Custom,
        Modifiers = modifiers,
        VirtualKey = virtualKey,
        Side = ShortcutSide.None
    };

    public string DisplayText
    {
        get
        {
            if (Kind == ShortcutKind.SoloAlt)
            {
                return Side == ShortcutSide.Right ? "右 Alt" : "左 Alt";
            }

            var parts = new List<string>();
            if (Modifiers.HasFlag(ShortcutModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(ShortcutModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(ShortcutModifiers.Shift)) parts.Add("Shift");
            parts.Add(KeyDisplayName(VirtualKey));
            return string.Join(" + ", parts);
        }
    }

    public string CanonicalText
    {
        get
        {
            if (Kind == ShortcutKind.SoloAlt)
            {
                return Side == ShortcutSide.Right ? "RightAlt" : "LeftAlt";
            }

            var parts = new List<string>();
            if (Modifiers.HasFlag(ShortcutModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(ShortcutModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(ShortcutModifiers.Shift)) parts.Add("Shift");
            parts.Add(KeyStorageName(VirtualKey));
            return string.Join("+", parts);
        }
    }

    public ShortcutValidation Validate()
    {
        if (Kind == ShortcutKind.SoloAlt)
        {
            return Side is ShortcutSide.Left or ShortcutSide.Right
                && VirtualKey is VkLeftAlt or VkRightAlt
                ? ShortcutValidation.Valid()
                : ShortcutValidation.Invalid("单独 Alt 必须明确选择左 Alt 或右 Alt。");
        }

        if (!IsSupportedPrimaryKey(VirtualKey))
        {
            return ShortcutValidation.Invalid("请选择字母、数字、空格或 F2–F12 功能键。");
        }

        var isFunctionKey = VirtualKey is >= VkF1 + 1 and <= VkF12;
        if (Modifiers == ShortcutModifiers.None && !isFunctionKey)
        {
            return ShortcutValidation.Invalid("为避免影响正常打字，请加入 Ctrl、Alt 或 Shift。");
        }

        if (Modifiers == ShortcutModifiers.Alt && VirtualKey is VkSpace or VkF1 + 3)
        {
            return ShortcutValidation.Invalid("这个组合键由 Windows 使用，请换一个快捷键。");
        }

        if (Modifiers == ShortcutModifiers.Control && VirtualKey == VkSpace)
        {
            return ShortcutValidation.Warning("Ctrl + Space 可能与输入法切换冲突，建议换一个组合键。");
        }

        if (Modifiers.HasFlag(ShortcutModifiers.Control)
            && Modifiers.HasFlag(ShortcutModifiers.Shift)
            && VirtualKey == VkSpace)
        {
            return ShortcutValidation.Warning("这个组合键可能与输入法切换冲突。");
        }

        return ShortcutValidation.Valid();
    }

    public static ShortcutBinding ParseLegacy(string value)
    {
        if (string.Equals(value, "LeftAlt", StringComparison.OrdinalIgnoreCase)) return LeftAlt;
        if (string.Equals(value, "RightAlt", StringComparison.OrdinalIgnoreCase)) return RightAlt;

        var parts = value.Split(
            '+',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var modifiers = ShortcutModifiers.None;
        int? virtualKey = null;

        foreach (var part in parts)
        {
            switch (part.ToUpperInvariant())
            {
                case "CTRL":
                case "CONTROL":
                    modifiers |= ShortcutModifiers.Control;
                    break;
                case "ALT":
                    modifiers |= ShortcutModifiers.Alt;
                    break;
                case "SHIFT":
                    modifiers |= ShortcutModifiers.Shift;
                    break;
                case "SPACE":
                    virtualKey = VkSpace;
                    break;
                default:
                    virtualKey = ParsePrimaryKey(part);
                    break;
            }
        }

        if (virtualKey is null)
        {
            throw new FormatException($"快捷键缺少主键：{value}");
        }

        var binding = Custom(modifiers, virtualKey.Value);
        var validation = binding.Validate();
        if (!validation.IsValid)
        {
            throw new FormatException(validation.Message);
        }

        return binding;
    }

    public static bool IsSupportedPrimaryKey(int virtualKey) =>
        virtualKey is >= 0x41 and <= 0x5A
        || virtualKey is >= 0x30 and <= 0x39
        || virtualKey == VkSpace
        || virtualKey is >= VkF1 + 1 and <= VkF12;

    private static int ParsePrimaryKey(string value)
    {
        if (value.Length == 1)
        {
            var character = char.ToUpperInvariant(value[0]);
            if (character is >= 'A' and <= 'Z' or >= '0' and <= '9')
            {
                return character;
            }
        }

        if (value.Length is 2 or 3
            && value[0] is 'F' or 'f'
            && int.TryParse(value[1..], out var functionNumber)
            && functionNumber is >= 2 and <= 12)
        {
            return VkF1 + functionNumber - 1;
        }

        throw new FormatException($"不支持的快捷键主键：{value}");
    }

    private static string KeyDisplayName(int virtualKey)
    {
        if (virtualKey == VkSpace) return "Space";
        if (virtualKey is >= VkF1 and <= VkF12) return $"F{virtualKey - VkF1 + 1}";
        if (virtualKey is >= 0x41 and <= 0x5A or >= 0x30 and <= 0x39)
            return ((char)virtualKey).ToString();
        return $"0x{virtualKey:X2}";
    }

    private static string KeyStorageName(int virtualKey) => KeyDisplayName(virtualKey);
}

public sealed class ShortcutBindingJsonConverter : JsonConverter<ShortcutBinding>
{
    public override ShortcutBinding Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            try
            {
                return ShortcutBinding.ParseLegacy(reader.GetString() ?? "LeftAlt");
            }
            catch (FormatException ex)
            {
                throw new JsonException(ex.Message, ex);
            }
        }

        if (reader.TokenType != JsonTokenType.StartObject)
        {
            throw new JsonException("快捷键设置格式无效。");
        }

        using var document = JsonDocument.ParseValue(ref reader);
        var root = document.RootElement;
        var kind = root.TryGetProperty("kind", out var kindValue)
            ? kindValue.GetString()
            : "custom";

        if (string.Equals(kind, "soloAlt", StringComparison.OrdinalIgnoreCase))
        {
            var side = root.TryGetProperty("side", out var sideValue)
                ? sideValue.GetString()
                : "left";
            return string.Equals(side, "right", StringComparison.OrdinalIgnoreCase)
                ? ShortcutBinding.RightAlt
                : ShortcutBinding.LeftAlt;
        }

        var modifiers = root.TryGetProperty("modifiers", out var modifiersValue)
            ? (ShortcutModifiers)modifiersValue.GetInt32()
            : ShortcutModifiers.None;
        var virtualKey = root.TryGetProperty("virtualKey", out var keyValue)
            ? keyValue.GetInt32()
            : 0;
        var binding = ShortcutBinding.Custom(modifiers, virtualKey);
        var validation = binding.Validate();
        if (!validation.IsValid) throw new JsonException(validation.Message);
        return binding;
    }

    public override void Write(
        Utf8JsonWriter writer,
        ShortcutBinding value,
        JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        if (value.Kind == ShortcutKind.SoloAlt)
        {
            writer.WriteString("kind", "soloAlt");
            writer.WriteString("side", value.Side == ShortcutSide.Right ? "right" : "left");
        }
        else
        {
            writer.WriteString("kind", "custom");
            writer.WriteNumber("modifiers", (int)value.Modifiers);
            writer.WriteNumber("virtualKey", value.VirtualKey);
        }
        writer.WriteEndObject();
    }
}
