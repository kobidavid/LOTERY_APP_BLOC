import 'package:flutter_bloc/flutter_bloc.dart';
import 'counter_event.dart';
import 'counter_state.dart';

class CounterBloc extends Bloc<CounterEvent, CounterState> {
  //final int counterValue;
  CounterBloc() : super(const CounterState()) {
    //on<IncreamentButtonPressed>(_onCounterIncremented);
    on<IncreamentButtonPressed>((event, emit) async {
      emit(CounterState(counterValue: state.counterValue + 1));
    });
    on<DecreamentButtonPressed>((event, emit) async {
      emit(CounterState(counterValue: state.counterValue - 1));
    });
  }

/*   void _onCounterIncremented(
    AddButtonPressed event,
    Emitter<CounterState> emit,
  ) {
    emit(CounterState(counterValue: state.counterValue - 1));
  }*/
}
