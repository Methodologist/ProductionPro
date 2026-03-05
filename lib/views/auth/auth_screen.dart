import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants.dart';
import 'auth_background.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _companyNameController = TextEditingController();

  bool _isJoiningExisting = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    if (savedEmail != null && mounted) setState(() => _emailController.text = savedEmail);
  }

  Future<void> _runAuthLogic(Future<void> Function() logic) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await logic();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', _emailController.text.trim());
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _cleanFirebaseError(e.message));
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll("Exception:", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignIn() async {
    await _runAuthLogic(() async {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim());

      if (cred.user != null) {
        if (!cred.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
              code: 'email-not-verified',
              message: "Email not verified. Please check your inbox.");
        }
      }
    });
  }

  Future<void> _handleCreateAccount() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Please enter your full name.");
      return;
    }
    if (!_isJoiningExisting && _companyNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Please enter a company name.");
      return;
    }

    await _runAuthLogic(() async {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final name = _nameController.text.trim();
      final joinCode = _joinCodeController.text.trim().toUpperCase();

      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);

      if (cred.user != null) {
        await cred.user!.updateDisplayName(name);
        await cred.user!.sendEmailVerification();
      }

      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
      String companyIdToUse = "";
      String companyName = "";
      String roleToAssign = "owner";

      try {
        if (_isJoiningExisting) {
          if (joinCode.length < 6) throw Exception("Invite code must be 6 characters.");
          final snapshot = await db.collection('companies').where('joinCode', isEqualTo: joinCode).limit(1).get();
          if (snapshot.docs.isEmpty) throw Exception("Invalid Invite Code.");
          companyIdToUse = snapshot.docs.first.id;
          companyName = snapshot.docs.first.data()['name'] ?? 'Org';
          roleToAssign = "user";
        } else {
          companyName = _companyNameController.text.trim();
          companyIdToUse = cred.user!.uid;
          final rnd = Random();
          const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
          String newCode = List.generate(6, (i) => chars[rnd.nextInt(chars.length)]).join();

          await db.collection('companies').doc(companyIdToUse).set({
            'name': companyName,
            'created_at': FieldValue.serverTimestamp(),
            'joinCode': newCode,
            'ownerId': cred.user!.uid
          });
        }

        final initialMembership = {'companyId': companyIdToUse, 'companyName': companyName, 'role': roleToAssign};

        await db.collection('users').doc(cred.user!.uid).set({
          'email': email,
          'role': roleToAssign,
          'companyId': companyIdToUse,
          'displayName': name,
          'memberships': [initialMembership],
          'connectedCompanyIds': [companyIdToUse],
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle
                    ),
                    child: const Icon(Icons.mark_email_read, size: 48, color: Colors.blue),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Verification Sent",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We have sent a confirmation link to:\n$email",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Please check your inbox (and spam) to activate your account.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text("OK, I'll Check It"),
                    ),
                  )
                ],
              ),
            )
          );
        }
      } catch (e) {
        if (cred.user != null) {
          await cred.user!.delete();
        }
        throw e;
      }
    });
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { setState(() => _errorMessage = "Please enter your email address first."); return; }
    await _runAuthLogic(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reset email sent!"), backgroundColor: Colors.green));
    });
  }

  String _cleanFirebaseError(String? msg) {
    if (msg == null) return "Authentication failed";
    if (msg.contains("email-already-in-use")) return "Email already registered.";
    if (msg.contains("wrong-password")) return "Incorrect password.";
    if (msg.contains("user-not-found")) return "No user found.";
    if (msg.contains("email-not-verified")) return "Please verify your email to log in.";
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    const Color textColor = Colors.white;
    const Color subTextColor = Colors.white70;

    return Scaffold(
      body: AuthScreenBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: screenHeight * 0.01),
                Column(children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Production Pro',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 1.5,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('v2.0', style: TextStyle(color: subTextColor, fontSize: 12)),
                ]),
                const SizedBox(height: 24),

                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: Color.fromARGB(179, 0, 0, 0)),
                    prefixIcon: Icon(Icons.email_outlined, color: Color.fromARGB(179, 0, 0, 0)),
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                  keyboardType: TextInputType.emailAddress
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: Color.fromARGB(179, 0, 0, 0)),
                    prefixIcon: Icon(Icons.lock_outline, color: Color.fromARGB(179, 0, 0, 0)),
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                  obscureText: true
                ),
                const SizedBox(height: 16),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Join existing team?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                  subtitle: const Text("I have a 6-digit invite code", style: TextStyle(fontSize: 12, color: subTextColor)),
                  value: _isJoiningExisting,
                  activeColor: kAccentColor,
                  trackColor: WidgetStateProperty.all(Colors.white24),
                  onChanged: (val) => setState(() => _isJoiningExisting = val),
                ),

                const Divider(height: 32, color: Colors.white24),

                const Text("New Account Details (Required for Sign Up)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.black87),
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                  textCapitalization: TextCapitalization.words
                ),

                if (_isJoiningExisting) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _joinCodeController,
                    style: const TextStyle(color: Colors.black87),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    inputFormatters: [LengthLimitingTextInputFormatter(6), FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]"))],
                    decoration: const InputDecoration(labelText: 'Enter Invite Code', prefixIcon: Icon(Icons.vpn_key, color: Colors.orange), hintText: 'e.g. XJ9KL2')
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _companyNameController,
                    style: const TextStyle(color: Colors.black87),
                    decoration: const InputDecoration(labelText: 'Company Name', prefixIcon: Icon(Icons.business), hintText: "e.g. Acme Industries"),
                    textCapitalization: TextCapitalization.words
                  ),
                ],

                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text("Forgot Password?", style: TextStyle(color: Colors.white))
                  )
                ),

                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))
                  ),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF081F3A),
                          elevation: 5,
                          shadowColor: Colors.black45,
                        ),
                        child: const Text('LOGIN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _handleCreateAccount,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))
                        ),
                        child: Text(_isJoiningExisting ? 'JOIN TEAM' : 'CREATE COMPANY', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ]
                  ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
