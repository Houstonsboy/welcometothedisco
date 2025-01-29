import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/Searchicon.dart';
import 'package:welcometothedisco/StoriesTemplate.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
          body: SingleChildScrollView(
            child: Column(
              children: [
                StoriesTemplate(),
                SizedBox(height: 10.0),
                SearchIcon(),
                SizedBox(height: 25.0),
                Inbox(),
              ],
            ),
          ),
          bottomNavigationBar: const GNav(
            tabs: [
              GButton(
                icon: Icons.home,
                text: 'Home',
              ),
              GButton(
                icon: Icons.chat,
                text: 'Chat',
              ),
              GButton(
                icon: Icons.search,
                text: 'Kadmus',
              )
            ],
          ),
          floatingActionButton: FloatingActionButton(
  onPressed: () async {
  final response = await http.get(Uri.parse("http://192.168.126.205:5000/queue"));
  if (response.statusCode == 200) {
    // Extract the data from the response
    List<dynamic> tracks = jsonDecode(response.body);

    // Print the received data
    print('Received tracks:');
    for (var track in tracks) {
      print(track);
    }
  } else {
    print('Failed to fetch tracks. Status code: ${response.statusCode}');
  }
},

  backgroundColor: Colors.green,
  child: Icon(Icons.add),
),

          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
        ),
      ),
    );
  }
}
