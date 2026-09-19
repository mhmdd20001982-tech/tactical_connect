import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tactical Connect'),
      ),
      body: const Center(
        child: Text('Home — Map goes here'),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Team'),
          BottomNavigationBarItem(icon: Icon(Icons.place), label: 'Point'),
          BottomNavigationBarItem(icon: Icon(Icons.sos), label: 'SOS'),
        ],
      ),
    );
  }
}