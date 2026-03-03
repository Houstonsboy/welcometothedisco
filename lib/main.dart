import 'package:flutter/material.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/Searchicon.dart';
import 'package:welcometothedisco/StoriesTemplate.dart';

// ignore: avoid_web_libraries_in_flutter

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(
              "Welcome to the Disco",
              style: const TextStyle(
                fontSize: 25.0,
                fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
                color: Color.fromARGB(255, 159, 181, 63),
              ),
            ),
          ),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: RepaintBoundary(child: StoriesTemplate()),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
              const SliverToBoxAdapter(child: SearchIcon()),
              const SliverToBoxAdapter(child: SizedBox(height: 25.0)),
              SliverToBoxAdapter(
                child: RepaintBoundary(child: Inbox()),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20.0)),
            ],
          ),
          bottomNavigationBar: const BottomNavBar(),
        ),
      ),
    );
  }
}
