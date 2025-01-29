import 'package:flutter/material.dart';

class Stories extends StatelessWidget {
  final String imageUrl;
  final String songTitle;
  final String username;

  const Stories({Key? key, required this.imageUrl, required this.songTitle, required this.username})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          SizedBox(height:2.0),
          Text(username, style:TextStyle(color:const Color.fromARGB(255, 30, 222, 37), fontSize:10)),
          Container(
            height: 90.0,
            width: 90.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.pink,
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(height: 8.0),
          Text(songTitle, style: TextStyle(color: Colors.white, fontSize: 12))
        ],
      ),
    );
  }
}
