import 'package:flutter/material.dart';
import 'package:welcometothedisco/Stories.dart';

class StoriesTemplate extends StatelessWidget {
  
  final List songs = [
    "kanye West: Famous",
    "aSap rocky: LSD",
    "Jaden: CabinFever",
    "Wakadinali: Marijuana",
    "Chris Brown: Dont be Gone too Long"
  ];
  final List images = [
    "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR8_X5BzAVApWQdDD7qH1U8Abjao55yOLnjqA&usqp=CAU",
    "https://i.pinimg.com/564x/12/7c/18/127c18d337018c197761539e1fdd1d15.jpg",
    "https://i.pinimg.com/474x/e7/72/8d/e7728d7d995be2aecfe8adcc5d2e304a.jpg",
    "https://i.pinimg.com/474x/0e/49/ca/0e49cab497fa5c819a6343de8f1337c4.jpg",
    "https://i.pinimg.com/474x/58/65/ff/5865ff80b2fb2e497642bc8ccad545a0.jpg"
  ];
  final List users = ["Allan", "Gift", "Stacy", "James", "Queen"];
  @override
  Widget build(BuildContext context) {
    return Card(
      //Stories from Stories.dart
      elevation: 3,
      margin: EdgeInsets.all(10),
      color: Colors.transparent,
      child: Container(
        height: 150.0,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          itemBuilder: (context, index) {
            return Stories(
                imageUrl: images[index],
                songTitle: songs[index],
                username: users[index]);
          },
        ),
      ),
    );
  }
}

