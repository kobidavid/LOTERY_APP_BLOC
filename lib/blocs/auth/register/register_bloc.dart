import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:template_app_bloc/blocs/auth/register/register_event.dart';
import 'package:template_app_bloc/blocs/auth/register/register_state.dart';
import 'package:template_app_bloc/generated/locale_keys.g.dart';
import 'package:template_app_bloc/models/http_response_model.dart';
import 'package:template_app_bloc/models/user_model.dart';
import 'package:template_app_bloc/services/firebase_service.dart';
import 'package:template_app_bloc/services/user_service.dart';

class RegisterBloc extends Bloc<RegisterEvent, RegisterState> {
  final UserService userService;
  final kobiUser = UserModel(
      id: "1",
      email: "kobi5252@gmail.com",
      password: "Aa123123",
      firstName: "Kobi",
      lastName: "David",
      profilePhoto: "profilePhoto",
      dateOfBirth: DateTime.parse('1969-07-20 20:18:04Z'),
      gender: 51,
      joinDate: DateTime.parse('2024-05-27 19:00:00Z'));

  RegisterBloc({required this.userService}) : super(const RegisterState()) {
    on<RegisterButtonPressed>((event, emit) async {
      emit(const RegisterState(isLoading: false));
      try {
        await userService.create(userModel: kobiUser);
        emit(const RegisterState(isLoading: false));
      } catch (error) {
        emit(RegisterFailed(message: error.toString(), isLoading: false));
      }
    });

    on<CheckButtonPressed>((event, emit) async {
      emit(const RegisterState(isLoading: false));
      try {
        HttpResponseModel<dynamic> checkResponse =
            await userService.check(email: event.email);
        if (checkResponse.data != null) {
          if (!checkResponse.data) {
            int? verificationCode =
                await FirebaseService.sendVerificationCode(toMail: event.email);
            emit(
              CheckSuccess(
                email: event.email,
                password: event.password,
                verificationCode: verificationCode,
                isLoading: false,
                message: checkResponse.message,
                data: checkResponse.data,
              ),
            );
          } else {
            emit(
              CheckSuccess(
                email: event.email,
                password: event.password,
                isLoading: false,
                data: checkResponse.data,
                message: checkResponse.message,
              ),
            );
          }
        }
      } catch (error) {
        emit(CheckFailed(
            message: error.toString(), isLoading: false, data: null));
      }
    });

    on<ForgotPasswordButtonPressed>((event, emit) async {
      emit(const RegisterState(isLoading: true));
      try {
        HttpResponseModel<dynamic> checkResponse =
            await userService.check(email: event.email);
        if (checkResponse.data != null) {
          if (checkResponse.data) {
            int? verificationCode =
                await FirebaseService.sendVerificationCode(toMail: event.email);
            emit(
              ForgotPasswordCheckSuccess(
                email: event.email,
                verificationCode: verificationCode,
                isLoading: false,
                data: checkResponse.data,
                message: checkResponse.message,
              ),
            );
          } else {
            emit(
              ForgotPasswordCheckFailed(
                message: checkResponse.message,
                isLoading: false,
                data: checkResponse.data,
              ),
            );
          }
        }
      } catch (error) {
        emit(ForgotPasswordCheckFailed(
            message: error.toString(), isLoading: false, data: null));
      }
    });

    on<ClearRegisterData>((event, emit) async {
      emit(const RegisterState());
    });
  }
}
