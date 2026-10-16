import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool notificationsOn;
  final bool emailUpdatesOn;
  final bool largeTextOn;

  const AppSettings({
    required this.notificationsOn,
    required this.emailUpdatesOn,
    this.largeTextOn = false,
  });

  AppSettings copyWith({
    bool? notificationsOn,
    bool? emailUpdatesOn,
    bool? largeTextOn,
  }) {
    return AppSettings(
      notificationsOn: notificationsOn ?? this.notificationsOn,
      emailUpdatesOn: emailUpdatesOn ?? this.emailUpdatesOn,
      largeTextOn: largeTextOn ?? this.largeTextOn,
    );
  }
}

class AppSettingsController extends ValueNotifier<AppSettings> {
  AppSettingsController()
    : super(
        const AppSettings(
          notificationsOn: true,
          emailUpdatesOn: true,
          largeTextOn: false,
        ),
      );

  static const _notificationsKey = 'notificationsOn';
  static const _emailUpdatesKey = 'emailUpdatesOn';
  static const _largeTextKey = 'largeTextOn';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = AppSettings(
      notificationsOn: prefs.getBool(_notificationsKey) ?? true,
      emailUpdatesOn: prefs.getBool(_emailUpdatesKey) ?? true,
      largeTextOn: prefs.getBool(_largeTextKey) ?? false,
    );
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> setNotificationsOn(bool value) async {
    this.value = this.value.copyWith(notificationsOn: value);
    await _saveBool(_notificationsKey, value);
  }

  Future<void> setEmailUpdatesOn(bool value) async {
    this.value = this.value.copyWith(emailUpdatesOn: value);
    await _saveBool(_emailUpdatesKey, value);
  }

  Future<void> setLargeTextOn(bool value) async {
    this.value = this.value.copyWith(largeTextOn: value);
    await _saveBool(_largeTextKey, value);
  }
}

final appSettingsController = AppSettingsController();
