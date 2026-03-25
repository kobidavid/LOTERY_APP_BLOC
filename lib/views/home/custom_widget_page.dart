import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:template_app_bloc/views/auth/login/widgets/custom_fab_widget.dart';

void main() {
  runApp(const MyAppWidget());
}

class MyAppWidget extends StatelessWidget {
  const MyAppWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Number Input',
      home: NumberInputScreen(),
    );
  }
}

class NumberInputScreen extends StatefulWidget {
  @override
  _NumberInputScreenState createState() => _NumberInputScreenState();
}

class _NumberInputScreenState extends State<NumberInputScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(33.0),
        child: AppBar(
          //shape: CircleBorder(side: BorderSide.none, eccentricity: 1),
          centerTitle: true,
          title: const Align(
              alignment: Alignment.center,
              child: Text('שליחת טופס לוטו', style: TextStyle(fontSize: 25))),
          backgroundColor: Colors.pink[100],
        ),
      ),
      body: const Center(
        child: Text('Press the FAB to toggle additional buttons'),
      ),
      floatingActionButton: CustomFAB(),
    );
  }
}
