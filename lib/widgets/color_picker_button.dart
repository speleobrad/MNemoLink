import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// A button widget that displays a color swatch and opens a color picker dialog when tapped.
class ColorPickerButton extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final String label;
  final bool enabled;

  const ColorPickerButton({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.label = '',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _showColorPicker(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: currentColor,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(label),
            ],
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    Color tempColor = currentColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label.isNotEmpty ? 'Pick $label color' : 'Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) => tempColor = color,
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsvWithHue,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onColorChanged(tempColor);
              Navigator.of(context).pop();
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
}

/// A row widget for displaying and editing a labeled color setting.
class ColorSettingRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final bool enabled;

  const ColorSettingRow({
    super.key,
    required this.label,
    required this.color,
    required this.onColorChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: enabled ? null : Colors.grey,
            ),
          ),
          ColorPickerButton(
            currentColor: color,
            onColorChanged: onColorChanged,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}
