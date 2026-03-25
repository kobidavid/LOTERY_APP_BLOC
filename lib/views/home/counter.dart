import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:template_app_bloc/blocs/counter/counter_bloc.dart';
import 'package:template_app_bloc/blocs/counter/counter_event.dart';
import 'package:template_app_bloc/blocs/counter/counter_state.dart';

class Test_counter extends StatefulWidget {
  Test_counter({Key? key}) : super(key: key);

  @override
  State<Test_counter> createState() => _nameState();
}

class _nameState extends State<Test_counter> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("my app"),
          backgroundColor: Colors.deepOrangeAccent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BlocBuilder<CounterBloc, CounterState>(
              builder: (context, state) {
                return Text(
                  '${state.counterValue}',
                  style: const TextStyle(fontSize: 30),
                );
              },
            ),
            const SizedBox(
              height: 30,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<CounterBloc>()
                          .add(IncreamentButtonPressed());
                    },
                    child: const Text("+"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<CounterBloc>()
                          .add(DecreamentButtonPressed());
                    },
                    child: const Text("-"),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
