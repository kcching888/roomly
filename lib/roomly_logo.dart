import 'package:flutter/material.dart';

class RoomlyLogo extends StatelessWidget {
  const RoomlyLogo({
    super.key,
    this.height = 54,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/roomly-logo.png',
      height: height,
      width: height * 3,
      fit: BoxFit.contain,
      semanticLabel: 'Roomly',
    );
  }
}

class RoomlyPageTitle extends StatelessWidget {
  const RoomlyPageTitle({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const RoomlyLogo(height: 42),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}