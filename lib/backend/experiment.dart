import 'dart:convert';
import 'package:http/http.dart' as http;

const String clientId = '9aafc2bea5134e1893987ed0d4c372bb';
const String clientSecret = 'b1a1a591023a499cadfb6b9f1067b326';

void main() async {
  try {
    var token = await getToken();
    print('Authorization Token: $token');
    var currentlyPlaying = await getCurrentlyPlaying(token);
    print('Currently Playing Song: ${currentlyPlaying['songName']}');
    print('Artist: ${currentlyPlaying['artistName']}');
  } catch (error) {
    print('Error: $error');
  }
}



Future<String> getToken() async {
  try {
    var response = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
      },
      body: {'grant_type': 'client_credentials'},
    );
    var data = json.decode(response.body);
    return data['access_token'];
  } catch (error) {
    print('Error getting Spotify access token: $error');
    throw error;
  }
}

Future<List<Map<String, dynamic>>> getQueue(String userId, String token) async {
  try {
    var response = await http.get(
      Uri.parse('https://api.spotify.com/v1/users/$userId/player/queue'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch queue: ${response.reasonPhrase}');
    }
    var data = json.decode(response.body);
    List<Map<String, dynamic>> queuedSongs = [];
    for (var item in data['items'].take(10)) {
      var songName = item['track']['name'];
      var artistName = item['track']['artists'][0]['name'];
      var albumName = item['track']['album']['name'];
      queuedSongs.add({
        'songName': songName,
        'artistName': artistName,
        'albumName': albumName
      });
    }
    return queuedSongs;
  } catch (error) {
    print('Error getting queue: $error');
    throw error;
  }
}
Future<Map<String, dynamic>> getCurrentlyPlaying(String token) async {
  try {
    var response = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch currently playing track: ${response.reasonPhrase}');
    }
    var data = json.decode(response.body);
    var songName = data['item']['name'];
    var artistName = data['item']['artists'][0]['name'];
    return {'songName': songName, 'artistName': artistName};
  } catch (error) {
    print('Error getting currently playing track: $error');
    throw error;
  }
}
