import 'package:flutter_bloc/flutter_bloc.dart';

enum HistorySection {
  groupSubmitted,
  submitted,
  saved,
}

class HistoryCubit extends Cubit<HistorySection?> {
  HistoryCubit() : super(HistorySection.groupSubmitted);

  void toggle(HistorySection section) {
    emit(state == section ? null : section);
  }
}
