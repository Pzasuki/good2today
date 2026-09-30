// 进度条组件：显示 0~1 的完成比例，带颜色。

import 'package:flutter/material.dart';

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.progress, // 0.0 ~ 1.0
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: color.withValues(alpha: 0.15),
        color: color,
      ),
    );
  }
}