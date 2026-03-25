import 'package:equatable/equatable.dart';

abstract class CounterEvent extends Equatable {
  const CounterEvent();
}

class IncreamentButtonPressed extends CounterEvent {
  @override
  List<Object> get props => [];
}

class DecreamentButtonPressed extends CounterEvent {
  @override
  List<Object> get props => [];
}
