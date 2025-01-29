import 'package:flutter/material.dart';
import 'package:welcometothedisco/InboxedSongs.dart';

class Inbox extends StatelessWidget {
  final List<Artist> artists = [
    Artist("Batman", "Chris Brown", "https://i.pinimg.com/736x/02/46/76/02467676bc633185e2a4ddec4d321d1b.jpg"),
    Artist("Priviledge", "TheWeeknd", "https://i.pinimg.com/474x/18/e6/e8/18e6e8e2d2b8c5b4dd77a4ae705bf96a.jpg"),
    Artist("Billie Jean", "Michael Jackson", "https://i.pinimg.com/474x/29/0a/c1/290ac132403be3c6f288f4262f8f26a1.jpg"),
    Artist("Sir Baudelaire", "Tyler the Creator", "https://i.pinimg.com/474x/82/e4/ba/82e4ba354a81b50f79ca6cbe94e41a48.jpg"),
    Artist("GET OFF ME", "Kid Cudi", "https://i.pinimg.com/474x/88/b6/6b/88b66be8f0241c0388175ea7983c8236.jpg"),
    Artist("Sunset for the dead", "Tommy Newport", "https://i.pinimg.com/474x/d0/bc/5e/d0bc5ee867837dcd3a8dcd98f54b1769.jpg"),
    Artist("Dont Break My Heart", "TheWeeknd", "https://i.pinimg.com/474x/c2/72/d3/c272d36d0366a9272d107a01db858387.jpg"),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.0),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
                ),
              ),
              width: 500.0,
              child: ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  return InboxedSongs(artist: artists[index]);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class Artist {
  String songTitle;
  String artistName;
  String coverImage;

  Artist(this.songTitle, this.artistName,this.coverImage);
}
