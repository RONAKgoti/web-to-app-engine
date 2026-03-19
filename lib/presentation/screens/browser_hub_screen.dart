import 'package:flutter/material.dart';

class BrowserHubScreen extends StatelessWidget {
  const BrowserHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BrowserHub')),
      body: const Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Enter URL to submit',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: Center(child: Text('BrowserHub History'))),
        ],
      ),
    );
  }
}
