import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:template_app_bloc/interfaces/user_interface.dart';
import 'package:template_app_bloc/models/http_response_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:template_app_bloc/models/user_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService extends UserInterface {
  final String _baseUrl = dotenv.env['BASE_URL'] ?? "";
  final String _authTokenKey = dotenv.env['AUTH_TOKEN_KEY'] ?? "";
  final FirebaseDatabase database = FirebaseDatabase.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  /*  @override
  Future<HttpResponseModel> login(
      {required String email, required String password}) async {
    try {
      var url = Uri.parse('$_baseUrl/login');
      var response = await http.post(
        url,
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["token"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  } */

  @override
  Future<HttpResponseModel> login(
      {required String email, required String password}) async {
    // Get a reference to the collection

    //CollectionReference collection =
    //    FirebaseFirestore.instance.collection("users/doc");
    DocumentReference docs = FirebaseFirestore.instance.doc("users/docs");
    // Add the data to the collection
    await docs.update({"email": "kakakak"});
    return HttpResponseModel();
  }

  @override
  Future<String> create({required UserModel userModel}) async {
    // Get a reference to the collection

    //CollectionReference collection =
    final db = FirebaseFirestore.instance;
    final alovelaceDocumentRef = db.collection("users").doc("kobi_david");
    // Add the data to the collection
    await alovelaceDocumentRef.set(userModel.toMap());
    return "new user added";
  }

  @override
  Future<HttpResponseModel> create22(
      {required String email, required String password}) async {
    try {
      // Get a reference to the collection
      CollectionReference collection =
          FirebaseFirestore.instance.collection("users");

      // Add the data to the collection
      await collection.add({"email": "addfd"});

      return HttpResponseModel(
        statusCode: 200,
        //data: jsonDecode("response.body")["data"],  user sign up successfuly
        data: "data_data",
        //message: jsonDecode("response.body")["message"],
        message: "user sign up successfuly",
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  @override
  Future<HttpResponseModel> delete({required String id}) async {
    try {
      var url = Uri.parse('$_baseUrl/users/$id');
      var response = await http.delete(url);

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  @override
  Future<HttpResponseModel> getById({required String id}) async {
    try {
      var url = Uri.parse('$_baseUrl/users/$id');
      var response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  @override
  Future<HttpResponseModel> update({required UserModel userModel}) async {
    try {
      var url = Uri.parse('$_baseUrl/users/${userModel.id}');
      var response = await http.put(
        url,
        body: jsonEncode({
          'first_name': userModel.firstName,
          'last_name': userModel.lastName,
          'profile_photo': userModel.profilePhoto,
          'date_of_birth': userModel.dateOfBirth.toUtc().toIso8601String(),
          'gender': userModel.gender,
        }),
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  @override
  Future<HttpResponseModel> validate({required String token}) async {
    try {
      var url = Uri.parse('$_baseUrl/validate');
      var response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  Future<void> saveAuthTokenToSP(String authToken) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_authTokenKey.isNotEmpty) {
      await prefs.setString(_authTokenKey, authToken);
    }
  }

  Future<String?> getAuthTokenFromSP() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  Future<void> deleteAuthTokenFromSP() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  }

  @override
  Future<HttpResponseModel> check({required String email}) async {
    try {
      var url = Uri.parse('$_baseUrl/users/check/$email');
      var response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }

  @override
  Future<HttpResponseModel> updatePassword(
      {required String userId, required String password}) async {
    try {
      var url = Uri.parse('$_baseUrl/users/$userId');
      var response = await http.put(
        url,
        body: jsonEncode({
          'password': password,
        }),
      );

      return HttpResponseModel(
        statusCode: response.statusCode,
        data: jsonDecode(response.body)["data"],
        message: jsonDecode(response.body)["message"],
      );
    } catch (e) {
      return HttpResponseModel(
        message: 'An error occurred: $e',
      );
    }
  }
}
