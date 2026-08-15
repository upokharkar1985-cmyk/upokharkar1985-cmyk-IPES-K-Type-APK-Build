class ChannelConfig {
  final String name;
  final String parameter;
  final String unit;
  final double scale;
  final double offset;
  final double voltageMin;
  final double externalMin;
  final double voltageMax;
  final double externalMax;

  const ChannelConfig({
    required this.name,
    this.parameter = 'Voltage',
    required this.unit,
    this.scale = 1.0,
    this.offset = 0.0,
    this.voltageMin = 0.0,
    this.externalMin = 0.0,
    this.voltageMax = 10.0,
    this.externalMax = 10.0,
  });

  double? apply(double? raw) => raw == null ? null : raw * scale + offset;

  ChannelConfig copyWith({
    String? name,
    String? parameter,
    String? unit,
    double? scale,
    double? offset,
    double? voltageMin,
    double? externalMin,
    double? voltageMax,
    double? externalMax,
  }) =>
      ChannelConfig(
        name: name ?? this.name,
        parameter: parameter ?? this.parameter,
        unit: unit ?? this.unit,
        scale: scale ?? this.scale,
        offset: offset ?? this.offset,
        voltageMin: voltageMin ?? this.voltageMin,
        externalMin: externalMin ?? this.externalMin,
        voltageMax: voltageMax ?? this.voltageMax,
        externalMax: externalMax ?? this.externalMax,
      );
}
