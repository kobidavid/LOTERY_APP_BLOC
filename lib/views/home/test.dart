import 'package:flutter/material.dart';

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('my app'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            height: 20,
            color: Colors.cyan,
          ),
          Positioned(
            top: 24,
            width: 80,
            left: 100,
            //right: 20,
            child: SizedBox(
              width: 1900,
              height: 25,
              child: Container(
                color: Colors.orange,
              ),
            ),
          )
        ],
      ),
    );
  }
}
