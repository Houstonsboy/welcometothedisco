import 'package:flutter/material.dart';
import 'package:welcometothedisco/HomeScreen.dart';
import 'package:welcometothedisco/SpotifyAPIplayer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/spotify': (_) => const SpotifyAPIplayer(),
      },
    );
  }
}
