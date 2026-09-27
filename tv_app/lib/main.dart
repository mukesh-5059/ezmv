import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'core/api_client.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ApiClient.init();
  runApp(const StreamTVApp());
}

class StreamTVApp extends StatelessWidget {
  const StreamTVApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamTV',
      theme: TVTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
