import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ApiClient.init();
  runApp(const EzMVApp());
}

class EzMVApp extends StatelessWidget {
  const EzMVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzMV',
      theme: TVTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
