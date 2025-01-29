import 'package:flutter/material.dart';
import 'package:welcometothedisco/Inbox.dart';

class InboxedSongs extends StatelessWidget {
  final Artist artist;

  const InboxedSongs({Key? key, required this.artist}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color:Colors.transparent,
      child: ListTile(
        
        onTap: (){},
        title:Text(artist.songTitle),
        leading: CircleAvatar(
          backgroundImage: NetworkImage(artist.coverImage),
        )
      ),
    );
  }
}
