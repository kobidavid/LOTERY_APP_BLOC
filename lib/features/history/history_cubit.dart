import 'package:flutter_bloc/flutter_bloc.dart';

enum HistorySection {
  submitted,
  saved,
}

class HistoryCubit extends Cubit<HistorySection?> {
  HistoryCubit() : super(HistorySection.submitted);

  void toggle(HistorySection section) {
    emit(state == section ? null : section);
  }
}
