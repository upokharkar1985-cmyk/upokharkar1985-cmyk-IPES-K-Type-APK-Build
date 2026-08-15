import 'package:flutter/material.dart';

class ChannelTile extends StatelessWidget {
  final int number;
  final String name;
  final String unit;
  final double? value;

  const ChannelTile({super.key, required this.number, required this.name, required this.unit, required this.value});

  @override
  Widget build(BuildContext context) {
    final ok = value != null && value!.isFinite && value! >= -10.5 && value! <= 10.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151D27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ok ? const Color(0xFF2E9BFF) : const Color(0xFF58616D), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF203247), borderRadius: BorderRadius.circular(8)),
            child: Text('$number', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF61B5FF))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 2),
              Text(value == null ? '--' : value!.toStringAsFixed(4), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
          Text(unit, style: const TextStyle(fontSize: 14, color: Color(0xFF90A4B8))),
        ],
      ),
    );
  }
}
