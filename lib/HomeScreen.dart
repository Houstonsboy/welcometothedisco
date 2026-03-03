import 'package:flutter/material.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/Searchicon.dart';
import 'package:welcometothedisco/StoriesTemplate.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _onTabTapped(BuildContext context, int index) {
    if (index == 0) return;
    if (index == 1) {
      Navigator.pushReplacementNamed(context, '/spotify');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          title: const Text(
            "Welcome to the Disco",
            style: TextStyle(
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
            SliverToBoxAdapter(child: SizedBox(height: 10.0)),
            SliverToBoxAdapter(child: SearchIcon()),
            SliverToBoxAdapter(child: SizedBox(height: 25.0)),
            SliverToBoxAdapter(
              child: RepaintBoundary(child: Inbox()),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 20.0)),
          ],
        ),
        bottomNavigationBar: BottomNavBar(
          selectedIndex: 0,
          onTap: (index) => _onTabTapped(context, index),
        ),
      ),
    );
  }
}
