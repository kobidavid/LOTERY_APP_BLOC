import 'package:flutter/material.dart';

void main() {
  runApp(MyTextFields());
}

class MyTextFields extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Number Grid',
      home: NumberGrid(),
    );
  }
}

class NumberGrid extends StatefulWidget {
  @override
  _NumberGridState createState() => _NumberGridState();
}

class _NumberGridState extends State<NumberGrid> {
  final List<List<TextEditingController>> _controllers = List.generate(
    2,
    (_) => List.generate(3, (_) => TextEditingController()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Number Grid'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: 2,
              itemBuilder: (context, groupIndex) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(
                        3,
                        (fieldIndex) => TextField(
                          controller: _controllers[groupIndex][fieldIndex],
                          decoration: InputDecoration(
                            labelText: 'Field ${fieldIndex + 1}',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _controllers[0][1].text,
              style: TextStyle(fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final group in _controllers) {
      for (final controller in group) {
        controller.dispose();
      }
    }
    super.dispose();
  }
}
