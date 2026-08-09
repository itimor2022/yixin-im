import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/constants/emoji_animations.dart';

class WebSafeLottie {
  WebSafeLottie._();

  static Widget asset(
    String name, {
    Animation<double>? controller,
    bool? animate,
    FrameRate? frameRate,
    bool? repeat,
    bool? reverse,
    void Function(LottieComposition)? onLoaded,
    Key? key,
    ImageErrorWidgetBuilder? errorBuilder,
    double? width,
    double? height,
    BoxFit? fit,
    AlignmentGeometry? alignment,
  }) {
    if (kIsWeb) {
      return _WebLottieFallback(
        name: name,
        width: width,
        height: height,
        alignment: alignment ?? Alignment.center,
        key: key,
      );
    }
    return Lottie.asset(
      name,
      controller: controller,
      animate: animate,
      frameRate: frameRate,
      repeat: repeat,
      reverse: reverse,
      onLoaded: onLoaded,
      key: key,
      errorBuilder: errorBuilder,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}

class _WebLottieFallback extends StatelessWidget {
  const _WebLottieFallback({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    required this.alignment,
  });

  final String name;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    var fallback = '*';
    for (final emoji in EmojiAnimations.all) {
      if (emoji.path == name) {
        fallback = emoji.emoji;
        break;
      }
    }
    return SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: alignment,
        child: Text(
          fallback,
          style: TextStyle(fontSize: (width ?? height ?? 24) * 0.72),
        ),
      ),
    );
  }
}
