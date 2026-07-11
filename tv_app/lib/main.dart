import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() async {
  // 1. Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize API client and load configuration
  await ApiClient.init();

  // 3. Run application
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
