class ChannelConfig {
  final String name;
  final String unit;
  final double scale;
  final double offset;

  const ChannelConfig({
    required this.name,
    required this.unit,
    this.scale = 1.0,
    this.offset = 0.0,
  });

  double? apply(double? raw) => raw == null ? null : raw * scale + offset;

  ChannelConfig copyWith({String? name, String? unit, double? scale, double? offset}) => ChannelConfig(
        name: name ?? this.name,
        unit: unit ?? this.unit,
        scale: scale ?? this.scale,
        offset: offset ?? this.offset,
      );
}
