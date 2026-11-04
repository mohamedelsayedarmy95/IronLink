import 'package:flutter/material.dart';

/// Shared visual palette for the auth flow (welcome, phone, OTP, military
/// ID). Deliberately local to this feature — not IronColors — so the rest
/// of the app (chat, home, settings...) keeps its existing navy/gold look
/// untouched until it's redesigned too.
class AuthColors {
  static const bg = Color(0xFF070B14);
  static const bgVignette = Color(0xFF0C1424);
  static const surface = Color(0xFF0D1424);
  static const surfaceRaised = Color(0xFF111A2C);
  static const cyan = Color(0xFF22D3EE);
  static const cyanBright = Color(0xFF67E8F9);
  static const cyanDim = Color(0xFF0E7490);
  static const textHi = Color(0xFFF1F5F9);
  static const textLo = Color(0xFF7C8DA6);
  static const border = Color(0x3322D3EE);
  static const fill = Color(0x0D22D3EE);
  static const success = Color(0xFF34D399);
  static const error = Color(0xFFF87171);
}
