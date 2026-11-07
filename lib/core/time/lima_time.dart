/// Lima (America/Lima) es UTC-5 todo el año, sin horario de verano.
const _limaOffset = Duration(hours: -5);

/// "Ahora" en Lima, independiente de la zona del dispositivo.
/// Los campos year/month/day/hour... son la hora de pared de Lima.
DateTime limaNow() => DateTime.now().toUtc().add(_limaOffset);

/// Convierte un valor de la API a hora de pared de Lima.
/// Si trae zona (Z / ±hh:mm) se convierte; si no, se asume que ya es de Lima.
DateTime? parseApiDateToLima(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)) {
    return parsed;
  }
  return parsed.toUtc().add(_limaOffset);
}

String _two(int v) => v.toString().padLeft(2, '0');

String limaIsoOffset(DateTime lima) =>
    '${lima.year}-${_two(lima.month)}-${_two(lima.day)}T${_two(lima.hour)}:${_two(lima.minute)}:${_two(lima.second)}-05:00';
